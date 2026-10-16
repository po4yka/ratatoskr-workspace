# Site hosting operations

The host is frozen in `docs/DEPLOYMENT_TARGET.md`. The provisioning preflight refuses production
until the owner lifts that freeze. The steps below describe the first deployment after that change.
Use [the provisioning runbook](ansible/README.md) for the host and its secrets.

1. Add each approved hostname to `deploy/ansible/group_vars/all/sites.json`, in
   `ratatoskr_sites_hostnames`. The list accepts explicit lower-case DNS names. The host role adds
   one rule per hostname inside `# BEGIN ratatoskr-sites` and `# END ratatoskr-sites` in
   `/etc/cloudflared/config.yml`, before the final `http_status:404` rule. It preserves all other
   rules, validates the result with `cloudflared tunnel ingress validate`, and reloads the service
   only when the block changes. The [standard cloudflared unit](https://github.com/cloudflare/cloudflared/blob/master/cmd/cloudflared/linux_service.go) has no reload action, so the handler
   uses `systemctl reload-or-restart`: a unit without reload support restarts and briefly reconnects
   the tunnel. A gateway rule outside that block is refused. The existing tunnel
   configuration and its final catch-all must exist before the playbook runs.
2. In the operator's Cloudflare account, create the DNS route for each hostname:
   `cloudflared tunnel route dns <tunnel-id-or-name> <hostname>`. This command changes DNS. The
   playbook does not run it. Confirm the hostname reaches the tunnel and that the Cloudflare zone
   uses HTTPS. In the zone's SSL/TLS settings, enable HSTS only after HTTPS works for every covered
   hostname; include subdomains or preload only if the owner has approved that scope. The gateway
   also emits HSTS on each response.
3. Register the site manifest and approve its hostname and requested capabilities in the web
   client. A hostname in tunnel ingress alone grants no site access. Before approval, a request
   with that Host to `http://127.0.0.1:8183/` must return `sites.gateway.unknown_host`.
4. In the web client, create a pairing code of kind `site_deployer` for this site. On the deploy
   machine, run `npx ratatoskr-site login --pairing-code - --site <site> --api https://<edge>`.
   Type the pairing code on standard input. The CLI stores the device secret in the operating
   system's credential store. Revoke that device in the web client when it is no longer needed.
5. Build and publish the site bundle with the pinned reusable workflow of `ratatoskr-site-sdk`.
   In the site repository, run `npx ratatoskr-site deploy --site <site> --commit <sha>`. The command
   verifies the artifact's attestation, commit, workflow and file digests before upload and then
   activates the bundle. `--no-activate` stores it without activation. To return to an earlier
   bundle, deploy its commit again. `--repository owner/name` selects a repository when `origin`
   is not on GitHub.
6. Check the gateway's operator routes on `127.0.0.1:9473`, the public hostname over HTTPS, the
   reserved `/.ratatoskr/sign-in/` callback, and the site's `/_r/v1/sites/<site>/content/release`.
   Removing a hostname from `sites.json` removes its ingress rule at the next playbook run.
   Withdraw the manifest approval to stop access independently of tunnel configuration.

The pinned SDK implements `login`, `deploy`, `--no-activate` and `--repository`. See its
[deploy instructions](../repos/clients/site-sdk/README.md#publish-and-deploy-a-site).
A site approval binds a hostname and capabilities. The current contract has no repository field;
choosing that field remains an owner decision.
