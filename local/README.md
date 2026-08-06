# Local development

Everything needed to run Finance Tracker on this machine. Nothing here is used
by production; see `../oci/` for that.

```
local/
  scripts/   start, stop, hot-reload (PowerShell + bash) and the flutter runner
  env/       backend.env (real values, ignored) and backend.env.example
  logs/      backend/frontend logs, pid files (ignored)
  build/     local Go binary (ignored)
```

## First run

Copy `env/backend.env.example` to `env/backend.env` and fill in the values you
need. Everything has a working local default except `TURNSTILE_SECRET`, which
registration requires.

```powershell
.\local\scripts\start.ps1
```

This stops any running instance, copies `env/backend.env` to `backend/.env`,
builds `build/financetracker.exe`, starts it on port 8080, and launches
`flutter run` in Chrome on port 3000.

## Day to day

```powershell
.\local\scripts\start.ps1 -Debug     # debug build, hot reload available
.\local\scripts\hot-reload.ps1       # reload after a Dart change
.\local\scripts\hot-reload.ps1 -Restart
.\local\scripts\stop.ps1
.\local\scripts\stop.ps1 -Restart    # rebuild and restart
```

Logs are in `logs/`: `backend.out.log`, `backend.err.log`, `frontend.out.log`,
`frontend.err.log`.

## Notes

- `backend/.env` is generated on every start from `env/backend.env`. Edits to it
  are lost; change `env/backend.env` instead.
- The Flutter dev server serves `frontend/build/web`, which `flutter run` owns.
  If a production build ever lands there, `localhost:3000` will serve the
  production app against `www.dhanshanti.com`. Delete the folder and restart to
  recover.
