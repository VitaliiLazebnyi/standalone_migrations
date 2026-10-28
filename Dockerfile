# Ruby image that carries the migration code and the `db` CLI.
#
# Alpine-based: the Debian-based ruby image carries dozens of HIGH/CRITICAL
# vulnerabilities, this one none (CI scans the built image with Trivy). Both
# stages use the same base, pinned by digest (Dependabot keeps it current).

# --- gems: compile the native extensions (bigdecimal, json) -------------------
FROM ruby:4.0.9-alpine3.24@sha256:d0c5befc0864d31c6219321c8d79de2941d1bc31c41505d9c9289c6192c36d60 AS gems

# A C toolchain for the gems with native extensions (the pg gem ships
# precompiled, with its own libpq, so no libpq-dev is needed), and the newest
# RubyGems and Bundler (the version Gemfile.lock was bundled with): the image
# ships older ones.
RUN apk add --no-cache "build-base~0.5" \
    && gem update --system 4.0.23 --no-document

WORKDIR /app

# Only the runtime gems: the development and test tooling stays out of the image.
ENV BUNDLE_WITHOUT="development:test" \
    BUNDLE_FROZEN="true"
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install --jobs 4 --retry 3 \
    && rm -rf /usr/local/bundle/cache

# --- runtime ----------------------------------------------------------------
FROM ruby:4.0.9-alpine3.24@sha256:d0c5befc0864d31c6219321c8d79de2941d1bc31c41505d9c9289c6192c36d60

# psql (`db console`) and pg_isready (bin/entrypoint.sh), matching the
# PostgreSQL 18 server of docker-compose.yml.
RUN apk add --no-cache "postgresql18-client~18" \
    && gem update --system 4.0.23 --no-document

# Run as an unprivileged user. Its uid/gid default to 1000 and can be set to
# the host user's (the Makefile does), so that files written to the bind mount
# (`db scan`, `db baseline`, `make lock`) belong to whoever runs the commands.
ARG APP_UID=1000
ARG APP_GID=1000
RUN addgroup -g "${APP_GID}" app \
    && adduser -D -u "${APP_UID}" -G app app

WORKDIR /app
ENV BUNDLE_WITHOUT="development:test"
COPY --from=gems /usr/local/bundle /usr/local/bundle

# Copy the rest of the project.
COPY --chown=app:app . .

USER ${APP_UID}:${APP_GID}

# Put the CLI on PATH so `db <command>` works from anywhere in the container.
ENV PATH="/app/bin:${PATH}"

# A one-shot command-line container (`docker compose run --rm app db ...`):
# there is no long-running service to probe.
HEALTHCHECK NONE

ENTRYPOINT ["bin/entrypoint.sh"]
CMD ["db", "help"]
