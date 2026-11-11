# GitHub and GitLab CI

The public GitHub repository is the canonical source and `main` is the synchronized branch. The bridge clones that source anonymously. The bridge workflow performs a normal fast-forward Git push to GitLab. A push creates a GitLab pipeline on the same commit, and GitLab owns validation, image build, publication, staging and promotion. This works with a normal GitLab Free project. GitLab's dedicated external-repository integration and pull mirroring are separate paid-tier options. [External-repository CI/CD](https://docs.gitlab.com/ci/ci_cd_for_external_repos/) · [GitLab pipeline sources](https://docs.gitlab.com/ci/pipelines/)

## Set up synchronization

1. Create an empty GitLab project with no generated README and enable its container registry. Configure `main` as the default and protected branch after the initial push. Allow your bridge token's identity to push to the protected branch. Keep force pushes disabled.
2. Create a GitLab token for the bridge with `write_repository` only. Use an expiring project-scoped token if your GitLab offering supports one. Otherwise use a short-lived personal token for a dedicated account with access only to this project. GitLab deploy tokens provide registry and read-repository access. [GitLab token scopes](https://docs.gitlab.com/security/tokens/access_token_scopes/) · [Branch protection](https://docs.gitlab.com/user/project/repository/branches/protection_rules/)
3. Set the GitHub Actions repository variable `GITLAB_REPOSITORY_URL` to the GitLab HTTPS clone URL including `.git`. Add `GITLAB_PUSH_TOKEN` as an Actions secret. GitHub-hosted runners need to reach that URL. Dispatch **Sync canonical main to GitLab** on `main`, or bootstrap the repository with the push below.
4. After protection and runner setup, trigger a GitLab pipeline on `main` if the first push arrived before protection was configured. Verify both remote branch SHAs and the pipeline's commit. Avoid direct GitLab commits so future GitHub updates remain fast-forward.

```bash
git fetch origin main
git remote add gitlab https://gitlab.com/YOUR_GROUP/DeployDock.git
git push gitlab refs/remotes/origin/main:refs/heads/main
git ls-remote origin refs/heads/main
git ls-remote gitlab refs/heads/main
```

The workflow reads GitHub's current `main` at execution time. It never uses a force push. The GitLab job token is for the build registry and does not authenticate the bridge.

## Runner and jobs

Register a dedicated Linux amd64 **project** runner with the shell executor, tag `deploydock-linux` and the protected setting. Install Docker Engine 28 or later and the Compose plugin, Bash, Git, curl, jq, OpenSSL, Python 3.12+ with venv, Node.js, ShellCheck and the OpenSSH client. Allow the runner user to access its dedicated Docker daemon. Shell execution and Docker access confer host-level privileges. Keep this runner dedicated to reviewed changes on protected refs and keep it separate from the target VMs. [Shell executor](https://docs.gitlab.com/runner/executors/shell/)

Install GitLab Runner with its official package, or place the runner executable in a directory the shell job user can traverse. The job user must be able to execute the runner binary for artifact upload and download.

| Stage | Job behavior |
| --- | --- |
| Validate | ShellCheck, Bash and JS syntax, Compose config, Ansible syntax and lint |
| Test | API contract and release input tests |
| Build | Build both images with the commit SHA label and save an image archive |
| Integration | Load the exact archive and run a real Compose deployment and recovery suite, then record the archive checksum |
| Publish | Check the tested archive checksum, push to the GitLab registry with job credentials and export a release manifest |
| Staging | Apply and verify the published release via Ansible, then save the manifest that passed staging |
| Production | Manually promote the saved staging manifest |

The build archive expires after one day. The published and staged release manifests expire after 30 days. Keep current and previous tags exempt from registry cleanup for each target. Run a new pipeline if artifacts for a manual promotion have expired.

The push helper publishes the tested Linux amd64 manifest. This keeps the executable image and its Git revision label and avoids a GitLab registry compatibility issue with BuildKit attestation indexes. [Docker image push](https://docs.docker.com/reference/cli/docker/image/push/) · [GitLab registry support note](https://support.gitlab.com/hc/en-us/articles/29426166749596-Push-to-Container-Registry-Fails-Error-error-from-registry-blob-unknown-to-registry)

## Enable deployment

Provision separate staging and production-like VMs before enabling deployment. Set project variables `DEPLOYDOCK_STAGING_ENABLED=true` and, when ready, `DEPLOYDOCK_PRODUCTION_ENABLED=true`. Protect both variables. Define these protected environment-scoped variables for each target:

| Variable | Meaning |
| --- | --- |
| `DEPLOY_HOST` | Reachable target DNS name or IPv4 address |
| `DEPLOY_SSH_PORT` | Optional SSH port, defaults to 22 |
| `DEPLOY_SSH_USER` | Optional account name, defaults to `deploydock` |
| `DEPLOY_SSH_PRIVATE_KEY` | File variable containing the environment's dedicated unencrypted deploy key, with trailing newline |
| `DEPLOY_SSH_KNOWN_HOSTS` | File variable with host keys verified out-of-band |

The runner uses batch mode and strict host key checking. The root Docker client on each VM uses its own read-only registry credentials. GitLab's publish job uses temporary Docker client configuration and `--password-stdin`. Keep CI debug tracing disabled. [GitLab registry authentication](https://docs.gitlab.com/user/packages/container_registry/authenticate_with_container_registry/)

Enable **Prevent outdated deployment jobs** and limit who can run production jobs. Use a protected production environment and deployment approvals where your GitLab tier supports them. On Free, restrict project membership and protected-branch permissions to trusted deployers. The production job is manual and blocks a promotion-enabled pipeline until it runs. Each target has a CI resource group, and the host controller also holds a lock through activation, validation and any rollback. [Deployment safety](https://docs.gitlab.com/ci/environments/deployment_safety/) · [Resource groups](https://docs.gitlab.com/ci/resource_groups/)
