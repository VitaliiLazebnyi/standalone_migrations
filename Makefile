# Host-side shortcuts so you can type `make migrate` instead of the full
# `docker compose run --rm app db migrate`.
#
#   make setup              # migrate + seed (first run)
#   make migrate            # apply pending migrations
#   make migrate VERSION=20240101000003
#   make rollback STEP=2    # revert N migrations
#   make seed               # (re)load example data
#   make scan               # dump schema -> db/schema.rb
#   make status / make version
#   make console            # interactive psql session
#   make up / make down     # start / stop the database (keeps data)
#   make reset              # WIPE the data volume, then migrate + seed
#   make logs / make build
#
# `docker compose run` starts the db service and waits for it to be healthy,
# so most targets don't need `make up` first. Set VERBOSE=1 to log SQL.

# `make <target> VERBOSE=1` forwards the flag into the container to log SQL.
RUN = docker compose run --rm $(if $(VERBOSE),-e VERBOSE=1,) app db

.DEFAULT_GOAL := help
.PHONY: help setup migrate rollback seed scan status version console psql up down reset build logs lock

# `make` or `make help` lists the available targets (parsed from this file).
help:
	@echo "Usage: make <target> [VAR=value]"
	@echo
	@echo "  setup            migrate + seed (first run)"
	@echo "  migrate          apply pending migrations   (VERSION=... optional)"
	@echo "  rollback         revert migrations          (STEP=n, default 1)"
	@echo "  seed             (re)load example data"
	@echo "  scan             dump schema -> db/schema.rb"
	@echo "  status / version show migration state"
	@echo "  console          interactive psql session"
	@echo "  up / down        start / stop the database (keeps data)"
	@echo "  reset            WIPE the data volume, then migrate + seed"
	@echo "  build / logs     rebuild image / follow db logs"
	@echo
	@echo "Add VERBOSE=1 to log every SQL statement."

setup:    ; $(RUN) setup
migrate:  ; $(RUN) migrate $(if $(VERSION),VERSION=$(VERSION),)
rollback: ; $(RUN) rollback $(if $(STEP),STEP=$(STEP),)
seed:     ; $(RUN) seed
scan:     ; $(RUN) scan
status:   ; $(RUN) status
version:  ; $(RUN) version

# Interactive psql; needs a TTY, which `docker compose run` allocates.
console psql: ; $(RUN) console

up:    ; docker compose up -d db
down:  ; docker compose down
build: ; docker compose build
logs:  ; docker compose logs -f db

# Regenerate Gemfile.lock after changing the Gemfile (writes to the host via
# the bind mount), keeping the linux build platforms. Run `make build` after.
lock:
	docker compose run --rm app bash -lc \
	  "bundle lock && bundle lock --add-platform x86_64-linux aarch64-linux"

# Destroy the database volume and rebuild from scratch (migrate + seed).
reset:
	docker compose down -v
	docker compose up -d db
	$(RUN) setup
