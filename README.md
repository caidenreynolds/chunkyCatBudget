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

```bash
docker compose up -d --build
```

Open:

```text
http://localhost:8080
```

The SQLite database is stored in the `chunky-cat-budget-data` Docker volume.

## unRAID

Full unRAID install instructions are in [docs/unRAID_Install.md](docs/unRAID_Install.md).

Use a single container with:

- Container port: `80`
- Host port: `8080` or another available port
- Volume mapping: `/mnt/user/appdata/chunky-cat-budget:/data`
- Database URL: `sqlite:////data/budget.db`

If using Compose on unRAID:

```bash
docker compose up -d --build
```

Then open:

```text
http://<unraid-ip>:8080
```
