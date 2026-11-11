# DeployDock operations

## Release state

The provisioner installs `deploydock` under `/usr/local/bin`. Host settings are in `/opt/deploydock/host.env`. Each release directory contains the original Compose file and the two application manifest references. The PostgreSQL image is digest-pinned in the Compose file. Use only trusted release bundles because the controller applies them with root Docker access.

1. The controller validates the inputs, acquires a host lock, stores the immutable release bundle and fetches missing digest-qualified images.
2. It atomically records the candidate as pending, starts Compose and waits for service health. The smoke test checks Nginx, API liveness, dependency readiness, the expected release ID and a PostgreSQL-backed create/read/delete cycle.
3. On success, it records the candidate as current and shifts the former current release to previous. On failure, it collects Compose status and bounded logs, then activates and verifies the last known-good release. If there was no earlier release, it stops the failed stack and keeps its volume.
4. An interrupted or unsuccessful recovery leaves the pending marker. Use `sudo deploydock recover` after resolving the host issue. This restores the last verified release, or stops a failed first activation, before clearing the marker.

| Result | Exit |
| --- | --- |
| Verification, deployment or recovery succeeded | 0 |
| Activation failed and recovery succeeded, or the requested check failed | 1 |
| Recovery failed or a journal update could not be confirmed | 2 |
| Invalid usage or immutable bundle conflict | 64 or 65 |
| Required tool or Linux engine unavailable | 69 |
| Host lock busy or pending release blocks operation | 75 |
| Host configuration or journal invalid | 78 |

An already verified release ID may be submitted again with byte-identical Compose content and the same digests. The controller verifies it without switching the journal. Manual rollback switches current and previous only after verification succeeds. A failure before activation, such as a missing image or invalid Compose file, leaves the current application running.

## Diagnose

| Symptom | Checks |
| --- | --- |
| Image pull fails | Confirm VM DNS, HTTPS access, root Docker registry login and manifest retention. |
| Candidate or recovery times out | Run `sudo deploydock status`, `sudo deploydock logs` and `sudo journalctl -u docker --since '15 minutes ago'`. Check disk, memory and the loopback port. |
| `/health/live` succeeds and `/health/ready` fails | Inspect API and PostgreSQL logs. Check that the expected volume is attached and that its original password file exists. |
| Smoke fails after services are healthy | Run `sudo deploydock verify` after recovery and inspect the release log for the HTTP or version failure. |
| SSH deployment fails | Verify host key, target user, key permissions, authorized key and allowed source network. Provision with the bootstrap administrator if the deploy account is absent. |

The smoke test retries readiness at the Compose startup layer. Its individual HTTP requests have deadlines and functional writes use unique data. A process killed after creating a smoke note may leave a note with the `DeployDock smoke` prefix.

## Data and rollback

Deployment and rollback preserve the named PostgreSQL volume. The database bootstrap only adds a table and index if absent. Keep schema changes compatible with both the active release and its rollback target. Use an expand/contract rollout across releases before removing a column, and back up before migrations or PostgreSQL upgrades. Rollback reactivates application images and Compose configuration. Database recovery requires its own verified restore procedure.

Take a logical backup with the Compose project and service labels. The example assumes the default project name:

```bash
umask 077
db=$(sudo docker ps -q --filter label=com.docker.compose.project=deploydock \
  --filter label=com.docker.compose.service=db)
test -n "$db"
sudo docker exec "$db" pg_dump --format=custom --username=deploydock --dbname=deploydock > deploydock.dump
pg_restore --list deploydock.dump
```

Protect the dump and the password file separately. Test restoration to a new disposable database before relying on the backup. On a populated volume, replacing the password file alone does not change the PostgreSQL password. Coordinate a SQL password change and file update during a maintenance window.

Use one stack per VM and retain current and previous release images in the registry. Keep the loopback bind unless an authenticated, TLS-terminating ingress controls access. PostgreSQL is isolated on an internal network and its only database is the notes application. The sample uses the PostgreSQL bootstrap role for schema setup and notes access. For a shared or sensitive database, provision distinct migration and runtime roles before using this application.
