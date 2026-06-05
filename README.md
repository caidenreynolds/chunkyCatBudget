# Chunky Cat Budget

Paycheck-based budgeting foundation with a Flutter frontend and FastAPI backend.

## What is included

- Flutter responsive app shell with dashboard, paycheck setup, accounts, chunks, add paycheck, transfers, transactions, and settings.
- FastAPI backend with the requested API routes.
- SQLite persistence for accounts, paycheck profiles, chunks, paychecks, allocations, movements, transactions, and future bank connections.
- Dockerfile and `docker-compose.yml` with a persistent database volume.

## Backend

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements.txt
uvicorn backend.app.main:app --reload
```

The API runs at `http://localhost:8000`.

## Frontend

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

## Docker

The Docker image is an all-in-one web app container:

- Nginx serves the Flutter web build.
- Nginx proxies `/api/*` to FastAPI inside the container.
- SQLite persists at `/data/budget.db`.
- Each Docker build writes `/version.json` with the app version, git commit, build number, and UTC build time.

Local build:

```bash
docker compose up -d --build
```

Open:

```text
http://localhost:8080
```

The local Compose database is stored in the `chunky-cat-budget-data` Docker volume.

## Build Metadata

Every deployed Docker image includes a generated `version.json` file. The login and settings screens show that build information in a small footer so users can confirm which deployed app their browser is running.

GitHub Actions generates this metadata during the container build from:

- `pubspec.yaml` app version
- Git commit SHA
- GitHub Actions run number
- UTC build timestamp

Nginx serves `/`, `/index.html`, `/version.json`, `/flutter_bootstrap.js`, `/flutter_service_worker.js`, `/main.dart.js`, `/flutter.js`, `/manifest.json`, and `/.last_build_id` with no-cache headers. Other static Flutter assets may still be cached normally, so users should not need to clear their browser cache after an update.

## unRAID

Full unRAID install instructions are in [docs/unRAID_Install.md](docs/unRAID_Install.md).
