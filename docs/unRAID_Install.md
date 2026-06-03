# unRAID Docker Install Guide

This app runs as one Docker container:

- Flutter web frontend served by Nginx
- FastAPI backend served internally by Uvicorn
- SQLite database persisted at `/data/budget.db`

## Requirements

- unRAID with Docker enabled
- A copy of this project on your server
- One available host port, such as `8080`

## Option 1: Docker Compose

Copy or clone this project to your unRAID server, then open a terminal.

```bash
cd /mnt/user/appdata
git clone <your-repo-url> ChunkyCatBudg
cd ChunkyCatBudg
docker compose up -d --build
```

Open the app:

```text
http://<unraid-ip>:8080
```

The database is stored in the Docker volume named:

```text
chunky-cat-budget-data
```

## Option 2: unRAID Docker Template

If you prefer creating the container from the unRAID Docker UI, use these values.

Repository/image:

```text
chunky-cat-budget
```

If you are building locally from this project, build the image first:

```bash
cd /mnt/user/appdata/ChunkyCatBudg
docker build -t chunky-cat-budget .
```

Container port:

```text
80
```

Host port:

```text
8080
```

Volume mapping:

```text
/mnt/user/appdata/chunky-cat-budget:/data
```

Environment variable:

```text
DATABASE_URL=sqlite:////data/budget.db
```

Optional environment variable:

```text
CORS_ORIGINS=*
```

Restart policy:

```text
unless-stopped
```

Open the app:

```text
http://<unraid-ip>:8080
```

## Updating

From the project directory:

```bash
git pull
docker compose up -d --build
```

## Backup

Back up this directory or Docker volume data regularly:

```text
/mnt/user/appdata/chunky-cat-budget
```

The important file is:

```text
/data/budget.db
```

## Troubleshooting

Check container logs:

```bash
docker logs chunky-cat-budget
```

Check that the API is healthy:

```bash
curl http://<unraid-ip>:8080/api/health
```

Expected response:

```json
{"status":"ok"}
```

If port `8080` is already used, choose another host port, such as `8090`, and open:

```text
http://<unraid-ip>:8090
```
