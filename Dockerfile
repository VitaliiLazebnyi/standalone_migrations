# Ruby image that carries the migration code and the `db` CLI.
FROM ruby:4.0-slim

# libpq is required by the `pg` gem at runtime; build-essential + libpq-dev to
# compile its native extension.
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
         build-essential \
         libpq-dev \
         postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems first so the layer is cached when only app code changes.
COPY Gemfile Gemfile.lock* ./
RUN bundle install

# Copy the rest of the project.
COPY . .

# Put the CLI on PATH so `db <command>` works from anywhere in the container.
ENV PATH="/app/bin:${PATH}"

ENTRYPOINT ["bin/entrypoint.sh"]
CMD ["db", "help"]
