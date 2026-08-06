# Finance Tracker — environments

This repo runs in exactly two environments. Everything that differs between them
lives under `local/` or `oci/`. The shared application code lives in `backend/`
and `frontend/` and must stay environment-agnostic.

| | Local development | OCI production |
|---|---|---|
| Folder | `local/` | `oci/` |
| Frontend | Chrome at `http://localhost:3000` via `flutter run` | Nginx at `https://www.dhanshanti.com` |
| Backend | `http://localhost:8080` | `80.225.255.191`, systemd unit `financetracker` |
| Database | local Postgres | Postgres on the OCI host |
| Env file | `local/env/backend.env` | `oci/env/backend.env` |

## Entry points

Local (Windows PowerShell; `.sh` equivalents exist for bash):

```powershell
.\local\scripts\start.ps1          # release mode
.\local\scripts\start.ps1 -Debug   # debug mode, enables hot reload
.\local\scripts\stop.ps1
.\local\scripts\hot-reload.ps1     # debug mode only
```

Production:

```powershell
.\oci\scripts\deploy-backend.ps1
.\oci\scripts\deploy-frontend.ps1
```

## Environment variables

The Go backend loads `.env` from its own working directory, which is `backend/`.
`local/scripts/start.ps1` copies `local/env/backend.env` to `backend/.env` on
every start, so `backend/.env` is a generated file — edit `local/env/backend.env`
instead, and never commit either one.

`oci/env/backend.env` mirrors `/opt/financetracker/.env` on the server, which
`financetracker.service` loads through `EnvironmentFile`. Deploy scripts do not
upload it; update the server copy deliberately when a value changes.

Only `*.env.example` files are tracked. Real env files, `oci/secrets/`,
`oci/build/`, `local/build/` and `local/logs/` are ignored by the root
`.gitignore`.

## Build outputs

| Artifact | Path |
|---|---|
| Local Go binary | `local/build/financetracker.exe` |
| Local Flutter dev bundle | `frontend/build/web` (owned by `flutter run`) |
| OCI Go binary | `oci/build/financetracker` (linux/amd64) |
| OCI Flutter bundle | `oci/build/web` and `oci/build/web.tar` |

`frontend/build/web` is hardwired into `flutter run` and cannot be relocated, so
it belongs to local development alone.

**Never run `flutter build web` without `--output` pointing outside
`frontend/build`.** A plain `flutter build web` overwrites the local dev bundle
with a production one compiled against `https://www.dhanshanti.com/api/v1`. When
that happened, `localhost:3000` served the production app: it showed production
users and portfolios and skipped the login screen, while the local backend sat
idle with no requests in its log. `oci/scripts/deploy-frontend.ps1` already
passes `--output oci\build\web`.

## Rules

- Never point a local run at the production database, and never copy
  `oci/env/backend.env` into `backend/.env`.
- The frontend defaults to `http://localhost:8080/api/v1`; production overrides
  it at compile time with `--dart-define=API_BASE_URL=...`. Do not change the
  default.
- Deploy only from `oci/scripts/`. Those scripts cross-compile and upload; they
  do not read `local/`.
- If the local app shows production data, check the DevTools Network tab. Hosts
  other than `localhost:8080` mean `frontend/build/web` is polluted: delete it,
  clear site data for `localhost:3000`, and start again.
