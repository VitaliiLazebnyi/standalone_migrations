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

# The app container runs as the host user, so files it writes through the bind
# mount (db/schema.rb, baseline migrations, Gemfile.lock) belong to you.
export APP_UID ?= $(shell id -u)
export APP_GID ?= $(shell id -g)

# `make <target> VERBOSE=1` forwards the flag into the container to log SQL.
RUN = docker compose run --rm $(if $(VERBOSE),-e VERBOSE=1,) app db

.DEFAULT_GOAL := help
.PHONY: all help setup migrate rollback seed scan status version console psql up down reset build logs lock test clean

define HELP_TEXT

  setup            migrate + seed (first run)
  migrate          apply pending migrations   (VERSION=... optional)
  rollback         revert migrations          (STEP=n, default 1)
  seed             (re)load example data
  scan             dump schema -> db/schema.rb
  status / version show migration state
  console          interactive psql session
  up / down        start / stop the database (keeps data)
  reset            WIPE the data volume, then migrate + seed
  build / logs     rebuild image / follow db logs
  test             run the verification suite on the host (see CONTRIBUTING.md)
  clean            remove generated reports (coverage, docs, mutation results)

Add VERBOSE=1 to log every SQL statement.
endef
export HELP_TEXT

# `make` or `make help` lists the available targets.
help: ; @echo "Usage: make <target> [VAR=value]"; echo "$$HELP_TEXT"

# `make all` builds the image, like `make build`.
all: build

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
	docker compose run --rm app sh -c \
	  "bundle lock && bundle lock --add-platform x86_64-linux aarch64-linux"

# Destroy the database volume and rebuild from scratch (migrate + seed).
reset:
	docker compose down -v
	docker compose up -d db
	$(RUN) setup

# The verification suite (`bundle exec rake`) on the host, against the
# database container (published on DB_HOST_PORT). Needs the Ruby of
# .ruby-version; see CONTRIBUTING.md.
test: up
	DATABASE_HOST=127.0.0.1 DATABASE_PORT=$${DB_HOST_PORT:-5433} bundle exec rake

# Generated reports and caches of the verification tools.
clean:
	rm -rf coverage doc .yardoc .mutant .rspec_status tmp
