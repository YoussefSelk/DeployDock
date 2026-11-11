# Verification results

Checks executed on 2026-11-11 using a dedicated Ubuntu 24.04 Linux environment on WSL 2 and a separate fresh QEMU Ubuntu Server 24.04.5 amd64 guest. The guest booted Ubuntu kernel `6.8.0-147-generic` and had no Docker executable before provisioning.

| Check | Observed result |
| --- | --- |
| `ci/validate` | ShellCheck, Bash and JavaScript syntax, Compose config, both Ansible syntax checks and Ansible lint passed. Ansible lint reported zero findings. |
| API and release unit checks | Four Python API tests and both invalid release-input assertions passed. |
| Container build | The web and API images built from digest-pinned bases with the hashed Python dependency lock. |
| `tests/integration/release.sh` | Started the real stack, tested a first-deployment failure and recovered from both readiness and smoke failures. Confirmed restored image identity, manual rollback, interrupted and failed recovery, a PostgreSQL outage and persistent notes across release switches. |
| Fresh VM provisioning over SSH | First recap `ok=25 changed=15 failed=0`. Second recap `ok=22 changed=0 failed=0`. Docker Engine 29.9.3 and Compose 5.7.1 were installed. |
| Fresh VM release and recovery | The key-only deploy account successfully ran the Ansible deploy playbook for two digest-pinned releases. An intentional bad release failed deployment. Automatic recovery restored `vm-good-b` and passed a fresh smoke check. Manual rollback restored `vm-good-a`, and a note created before the second deployment remained readable. |

The initial validation surfaced a Gunicorn control socket write on a read-only filesystem. The image disables that optional socket, and the container suite was rerun. The registry startup check also retries transient connection resets observed during testing.

Hosted GitLab credentials and externally reachable staging or production VMs were unavailable. See [CI setup](ci.md) for the GitHub bridge and the environment-specific settings.
