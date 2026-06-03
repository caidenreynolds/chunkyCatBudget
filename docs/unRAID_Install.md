# unRAID Install Guide

This app runs as one Docker container on unRAID.

## Docker Image

Use this image:
ghcr.io/caidenreynolds/chunkycatbudget:latest


## Install From unRAID Docker UI

Create a new container and use these values.

Name:
Chunky Cat Budget


Repository:
ghcr.io/caidenreynolds/chunkycatbudget:latest


Network type:
Bridge


## Template Fields

Add these fields in the unRAID Docker template.

Type:
Port


Name:
Web UI


Container port:
80


Host port:
8080


Connection type:
TCP


Type:
Path


Name:
App Data


Container path:
/data


Host path:
/mnt/user/appdata/chunky-cat-budget


Type:
Variable


Name:
Database URL


Key:
DATABASE_URL


Value:
sqlite:////data/budget.db


Restart policy:
unless-stopped


## Open The App

After the container starts, open:
http://<unraid-ip>:8080


Example:
http://192.168.1.10:8080


## Updating

In the unRAID Docker UI:
1. Check for updates.
2. Apply the update for Chunky Cat Budget.
3. Restart the container if unRAID does not restart it automatically.

## Backup

Back up this folder:
/mnt/user/appdata/chunky-cat-budget


The database file is:
/mnt/user/appdata/chunky-cat-budget/budget.db


## Health Check

To confirm the app is running:
http://<unraid-ip>:8080/api/health


Expected response:
json
{"status":"ok"}


## If Port 8080 Is Already Used

Use another host port, such as:
8090


Then open:
http://<unraid-ip>:8090

