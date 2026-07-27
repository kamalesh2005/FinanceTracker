# AGENTS.md

## Cursor Cloud specific instructions

Finance Tracker is a two-service app:

- **backend/** — Go (Gin + GORM) REST API on `:8080`, backed by PostgreSQL. Entry point `backend/main.go`.
- **frontend/** — Flutter web app (served on `:8090` in dev) that calls the backend at `http://localhost:8080/api/v1` (hardcoded in `frontend/lib/services/api_service.dart`).

### Toolchain (baked into the VM snapshot)

- Go: `go.mod` requires Go `1.25.0`. `GOTOOLCHAIN=auto`, so the correct toolchain is fetched automatically on first build.
- Flutter `3.44.6` / Dart `3.12.2` is installed at `/opt/flutter`. It is on `PATH` via `~/.bashrc`; non-login shells (and the update script) should call it as `/opt/flutter/bin/flutter`. Only the `web` target is configured (no Android/Linux-desktop toolchain), which is all this app needs.
- PostgreSQL 16 is installed. A `finance` role (password `finance`) and `financetracker` database already exist, matching the DSN hardcoded in `backend/main.go`.

### Starting services (NOT done by the update script)

PostgreSQL must be started each session before running the backend — the cluster data persists in the snapshot but the server process does not:

```
sudo pg_ctlcluster 16 main start
```

Then run each service (see `scripts/start.sh` for the canonical commands):

- Backend: `cd backend && go run main.go` (needs Postgres up; auto-migrates schema on boot).
- Frontend: `cd frontend && flutter run -d web-server --web-port 8090 --web-hostname 0.0.0.0`.

### Lint / test / build

- Backend: `go build ./...`, `go vet ./...`, `gofmt -l .` (no `*_test.go` files exist).
- Frontend: `flutter analyze`, `flutter test`.

### Known pre-existing issues (not environment problems)

- `flutter analyze` reports ~25 info/warning lints in existing screens (unused import, `withOpacity` deprecation, `use_build_context_synchronously`, etc.). These pre-date setup.
- `flutter test` fails: `test/widget_test.dart` is the default Flutter counter boilerplate and does not match this app.
- The backend fetches live prices from an external API on stock create/refresh, so `current_price` values require network access.
- Flutter web debug builds can show transient rendering/scroll glitches during screen recording; the underlying data (verify via the API or a static screenshot) is correct.
