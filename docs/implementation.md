# DeployDock implementation plan

The acceptance contract is the DeployDock project brief. Use the current empty checkout and commit each verified milestone to main.

1. Establish Git hygiene and define the application contract.
2. Test and implement the notes API, reverse proxy and PostgreSQL stack. Validate input, health semantics, version and persistence. Keep the published port on loopback and isolate the database.
3. Test and implement a Bash release transaction. Store immutable Compose bundles and image references, keep current, previous and pending release IDs in one atomic journal, and serialize changes with flock. Validate the same endpoint through the reverse proxy before promotion. Test a failing release and manual recovery against real containers.
4. Provision Ubuntu 24.04 LTS with Ansible. Configure Docker, a key-only deployment account, persistent configuration and host operations. Run provisioning twice on a clean VM where available.
5. Configure GitLab quality, test, build, publish, staging and manual production jobs. Synchronize GitHub main with a normal fast-forward Git push. Test pipeline execution wherever credentials and runners permit.
6. Document reproduction, operational limits and observed results. Verify clean history and publish the canonical GitHub repository.
