---
description: Start the postgres-app stack (compose up + build).
agent: build
---

# Up

Run `make up` from the repo root and confirm both containers are healthy
(`make validate`; DB healthy on `127.0.0.1:${POSTGRES_PORT}`).
