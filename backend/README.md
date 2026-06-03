# Chunky Cat Budget API

FastAPI service for the paycheck-based budgeting foundation.

## Run locally

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements.txt
uvicorn backend.app.main:app --reload
```

The SQLite database defaults to `backend/data/budget.db`.
