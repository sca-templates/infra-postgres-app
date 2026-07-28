SHELL := /bin/bash
-include .env

.PHONY: snapshot restore

snapshot:
	@mkdir -p backups
	docker exec postgres-app-db pg_dump -U $(POSTGRES_USER) $(POSTGRES_DB) > backups/$(POSTGRES_DB)_$$(date +%Y%m%d_%H%M%S).sql
	@echo "Snapshot created: backups/$(POSTGRES_DB)_$$(date +%Y%m%d_%H%M%S).sql"

restore:
	@read -p "Snapshot file: " file; \
	docker exec -i postgres-app-db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) < backups/$$file
	@echo "Restored from backups/$$file"
