---
description: Run the full postgres-app validation (compose config + container health).
agent: build
---

# Validate

Run `make validate` from the repo root and report the result. If a check
fails, isolate it with the individual commands in the `postgres-lifecycle`
skill and fix it, then re-run `make validate`.
