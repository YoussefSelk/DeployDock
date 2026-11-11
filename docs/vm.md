# Ubuntu VM setup

## Inventory and access

Start with a clean amd64 Ubuntu Server 24.04 LTS VM, systemd, Python 3 and OpenSSH. Size a small lab VM at 2 vCPU, 2 GiB RAM and 20 GiB disk. The VM needs outbound HTTPS to its APT sources, Docker's package and image servers and the chosen application registry. The Ansible controller needs SSH ingress. Restrict that ingress to trusted administrators and runners in your network perimeter.

From the root of the checkout, keep your real inventory in the ignored directory:

```bash
install -d -m 0700 .deploydock
cp infra/ansible/inventories/example.yml .deploydock/inventory.yml
ssh-keygen -t ed25519 -f ~/.ssh/deploydock-stage
```

Set the stage and production host addresses, the initial administrator account and the authorized deployment public keys. This is one complete stage-only inventory example:

```yaml
all:
  children:
    deploydock:
      hosts:
        stage:
          ansible_host: staging.example.invalid
          ansible_user: ubuntu
          deploydock_environment: staging
          deploydock_authorized_keys:
            - "ssh-ed25519 REPLACE_WITH_YOUR_DEPLOYMENT_PUBLIC_KEY"
```

Use a separate key for production. Verify and add each VM's SSH host key using the trusted fingerprint from the VM console. To enable UFW on a clean VM, set `deploydock_manage_firewall: true` and provide `deploydock_ssh_sources` with the actual controller, runner and management IPs or CIDRs. Set both `ansible_port` and `deploydock_ssh_port` if using a non-default SSH port. The role adds those allow rules before enabling the deny-inbound firewall. Review the rule set first on a host with existing services.

Run from the repo root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r ci/controller-requirements.txt
cd infra/ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i ../../.deploydock/inventory.yml playbooks/provision.yml --limit stage
ansible-playbook -i ../../.deploydock/inventory.yml playbooks/provision.yml --limit stage
```

The second pass on a stable host should report `changed=0`. APT cache refreshes can occur on a later pass. Docker packages come from the signed official Ubuntu Noble channel. The role defaults install the current available packages on a clean host. Supply exact APT package versions in `deploydock_docker_packages` if your environment requires repeatable package versions. Update the Docker signing-key checksum intentionally if Docker rotates the key. [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

The deploy account uses key-only SSH and cannot forward connections or allocate a TTY. Its Ansible sudo access grants effective root privileges because it applies trusted Compose releases and copies files on the target. Keep this key restricted to your deploy pipeline or trusted operators. Connect as the bootstrap administrator for interactive operations and SSH tunnels.

## Publish and deploy

Use the GitLab pipeline to publish images and retain its `release.json` artifact. For a manual release, use the following commands from a clean, committed checkout on an amd64 Linux Docker host. Set `REGISTRY_REPOSITORY` to your registry's project path such as `registry.gitlab.com/your-group/deploydock`, and log in as a publisher via `docker login`. Use a unique `RELEASE_ID` per build.

```bash
: "${REGISTRY_REPOSITORY:?Set the registry project path}"
revision=$(git rev-parse HEAD)
release="${revision}-$(date -u +%Y%m%d%H%M%S)"
web_tag="$REGISTRY_REPOSITORY/web:$release"
api_tag="$REGISTRY_REPOSITORY/api:$release"
docker build --label "org.opencontainers.image.revision=$revision" -t "$web_tag" -f app/frontend/Dockerfile .
docker build --label "org.opencontainers.image.revision=$revision" -t "$api_tag" -f app/backend/Dockerfile .
web=$(scripts/push-image "$web_tag")
api=$(scripts/push-image "$api_tag")
install -d -m 0700 .deploydock
jq -n --arg release "$release" --arg web "$web" --arg api "$api" \
  '{deploydock_release:$release,deploydock_web_image:$web,deploydock_api_image:$api}' > .deploydock/release.json
```

On each VM, provision pull access for the root-owned Docker client using a registry token with only `read_registry`. Enter the token when prompted. Store the token only on the VM and rotate it according to your environment's policy. Public images do not require host login.

```bash
sudo -H docker login registry.gitlab.com --username "$REGISTRY_READ_USER"
```

Run the following from the checkout that contains the matching `compose.yaml`. A passphrase-protected deployment key should already be unlocked in your SSH agent.

```bash
source .venv/bin/activate
cd infra/ansible
ansible-playbook -i ../../.deploydock/inventory.yml playbooks/deploy.yml --limit stage \
  -e ansible_user=deploydock --private-key ~/.ssh/deploydock-stage \
  -e @../../.deploydock/release.json
```

Open the UI from a controller by tunneling with the bootstrap administrator and the actual VM address:

```bash
ssh -N -L 127.0.0.1:8080:127.0.0.1:8080 ubuntu@staging.example.invalid
```

The inventory environment label identifies the target through `/api/version`. Keep `deploydock_project` stable on each host to preserve the Compose volume identity. Use separate VMs for staging and production-like environments.
