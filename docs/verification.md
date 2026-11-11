# Verification results

Checks executed on 2026-11-11 using a dedicated Ubuntu 24.04 Linux environment on WSL 2 and a separate fresh QEMU Ubuntu Server 24.04.5 amd64 guest. The guest booted Ubuntu kernel `6.8.0-147-generic` and had no Docker executable before provisioning. The QEMU disk came from the official Ubuntu cloud image and its SHA-256 was checked before boot.

| Check | Observed result |
| --- | --- |
| `ci/validate` | ShellCheck, Bash and JavaScript syntax, Compose config, both Ansible syntax checks and Ansible lint passed. Ansible lint reported zero findings. |
| API and release unit checks | Four Python API tests and both invalid release-input assertions passed. |
| Container build | The web and API images built from digest-pinned bases with the hashed Python dependency lock. |
| `tests/integration/release.sh` | Started the real stack, tested a first-deployment failure and recovered from both readiness and smoke failures. Confirmed restored image identity, manual rollback, removal of candidate-only services, interrupted and failed recovery, a PostgreSQL outage and persistent notes across release switches. |
| Fresh VM provisioning over SSH | First recap `ok=25 changed=15 failed=0`. Second recap `ok=22 changed=0 failed=0`. Docker Engine 29.9.3 and Compose 5.7.1 were installed. |
| Fresh VM release and recovery | The key-only deploy account successfully ran the Ansible deploy playbook for two digest-pinned releases. An intentional bad release failed deployment. Automatic recovery restored `vm-good-b` and passed a fresh smoke check. Manual rollback restored `vm-good-a`, and a note created before the second deployment remained readable. Reapplying the same verified manifest reported `changed=0`. Docker restarted the stack after a VM restart. |
| Optional UFW setup | Enabled the default-deny inbound policy with an explicit SSH source. Re-provisioning reported `changed=0` and deploy-key SSH still worked. |
| RawBlock interface | Headless Microsoft Edge checked keyboard focus, note creation and reload, a 390 px viewport, square controls and the three bundled fonts against the staged release. |

## GitLab CI

Self-managed GitLab CE 19.5.4 and a protected Linux shell runner executed pipeline 7 for commit [c95f600](https://github.com/YoussefSelk/DeployDock/commit/c95f600bc1959978417543c27e282a6fd171f369). A fast-forward push from a clone of GitHub main triggered the pipeline. GitLab lint reported zero errors and warnings.

| Job | ID | Result |
| --- | ---: | --- |
| Quality | 43 | Passed |
| Unit | 44 | Passed |
| Build | 45 | Passed |
| Integration and rollback | 46 | Passed |
| Registry publish | 47 | Passed |
| Staging on the Ubuntu VM | 48 | Passed |
| Manual production-like promotion to the separate Ubuntu WSL environment | 49 | Passed |

Both targets passed an independent smoke check after deployment and reported release `c95f600bc1959978417543c27e282a6fd171f369-7-47`. The published and staged release manifests matched byte for byte, and both host journals stored the same image digests.

## Failures corrected during verification

- The API image now disables Gunicorn's optional control socket on its read-only filesystem. The registry startup probe retries transient connection resets.
- The rollback suite reproduced a candidate-only service surviving recovery. The controller now removes orphan containers, and the suite checks that this service is gone.
- GitLab lint caught an unquoted pip argument, and the clean runner caught a missing Python 3.12 compatibility pin. Artifact transfer required an executable runner helper, and image push diagnostics needed to use the inherited stderr descriptor. The final pipeline passed after these corrections.
- The GitLab registry rejected the BuildKit attestation index. Publishing the tested amd64 manifest succeeded, and the VM pulled both manifests by digest.

The hosted GitHub-to-GitLab bridge and external deployment targets remain unconfigured. Verification used the local GitLab instance and isolated test targets. See [CI setup](ci.md) for the hosted bridge and environment settings.
