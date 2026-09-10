# OCI production deployment

Everything needed to ship Finance Tracker to the Oracle Cloud host serving
`https://www.dhanshanti.com` (`80.225.255.191`, user `opc`).

```
oci/
  scripts/   deploy-backend.ps1, deploy-frontend.ps1
  env/       backend.env (real values, ignored) and backend.env.example
  config/    financetracker.service (systemd), financetracker.conf (nginx)
  secrets/   SSH key pair, database and JWT secrets (ignored)
  build/     cross-compiled binary and packaged web bundle (ignored)
```

## Deploy

```powershell
.\oci\scripts\deploy-backend.ps1
.\oci\scripts\deploy-frontend.ps1
```

The backend script cross-compiles for linux/amd64 into `build/financetracker`,
uploads it to `/opt/financetracker/`, and restarts the `financetracker` systemd
unit. The frontend script builds the web bundle into `build/web` with
`API_BASE_URL=https://www.dhanshanti.com/api/v1`, tars it, and extracts it into
`/var/www/financetracker`.

Both default to `secrets/ssh-key-2026-07-30.key`; pass `-KeyPath` to override.

## Server configuration

`config/financetracker.service` and `config/financetracker.conf` are reference
copies of what is installed on the host. Deploy scripts do not push them, and
they do not push `env/backend.env` either. When a service definition, an Nginx
rule, or an environment value changes, update the file here and apply it on the
server deliberately:

```bash
sudo cp financetracker.service /etc/systemd/system/ && sudo systemctl daemon-reload
sudo cp financetracker.conf /etc/nginx/conf.d/ && sudo nginx -t && sudo systemctl reload nginx
```

The backend reads `/opt/financetracker/.env`, which mirrors `env/backend.env`.

## Flex Street URLs

The same Flutter SPA opens Flex Street when the browser host is
`flexstreet.dhanshanti.com` or the path is `/flexstreet` (for example
`https://www.dhanshanti.com/flexstreet`). Nginx already falls unknown paths
back to `index.html`; do not rebuild with `--base-href=/flexstreet/`.

The path form needs no extra hosting. The subdomain is a different origin
(`localStorage` login tokens are not shared with `www`) and needs:

- Cloudflare DNS: `flexstreet` CNAME (or A) to the same origin as
  `www.dhanshanti.com`, proxied.
- TLS: add `flexstreet.dhanshanti.com` on the Cloudflare cert (and the origin
  cert if SSL mode is Full Strict). Nginx `server_name _` already serves any
  Host on this VM.
- Cloudflare Turnstile widget domains: add `flexstreet.dhanshanti.com` so
  registration CAPTCHA works on that host.
- Google Cloud OAuth client: add `https://flexstreet.dhanshanti.com` as an
  authorized JavaScript origin for the GIS button on login/register.

Keep `API_BASE_URL=https://www.dhanshanti.com/api/v1`. CORS already allows `*`.

## Notes

- The frontend build writes to `oci/build/web`, never `frontend/build/web`. That
  separation is what keeps a production bundle from being served by the local
  dev server on port 3000.
- `secrets/` and `env/backend.env` hold live credentials and are gitignored.
  Keep them out of commits, logs and screenshots.
