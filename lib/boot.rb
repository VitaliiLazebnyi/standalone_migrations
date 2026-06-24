# Boots a standalone ActiveRecord environment: loads config/database.yml,
# establishes the connection, and points the migrator at db/migrate.
#
# Required by bin/db before any database work happens.

require "active_record"
require "erb"
require "yaml"
require "logger"

module Boot
  ROOT           = File.expand_path("..", __dir__)
  # Both paths can be overridden via env, which is handy when adopting a
  # separate database into its own migrations directory.
  MIGRATIONS_DIR = ENV.fetch("AR_MIGRATIONS_DIR", File.join(ROOT, "db", "migrate"))
  SCHEMA_FILE    = ENV.fetch("AR_SCHEMA_FILE", File.join(ROOT, "db", "schema.rb"))
  SEEDS_FILE     = ENV.fetch("AR_SEEDS_FILE", File.join(ROOT, "db", "seeds.rb"))
  ENVIRONMENT    = ENV.fetch("AR_ENV", "development")

  module_function

  # Parse config/database.yml (with ERB) and return the hash for the current
  # environment.
  def config
    raw = File.read(File.join(ROOT, "config", "database.yml"))
    yaml = ERB.new(raw).result
    YAML.safe_load(yaml, aliases: true).fetch(ENVIRONMENT)
  end

  # Connect and configure the migration engine. Idempotent.
  def setup!
    return if @setup

    # By default, keep output clean: show the high-level migration progress
    # (the `== ... migrating ==` lines) but not the raw DEBUG SQL. Set VERBOSE=1
    # to log every SQL statement — useful for demos and debugging.
    if ENV["VERBOSE"] == "1"
      ActiveRecord::Base.logger = Logger.new($stdout)
    else
      ActiveRecord::Base.logger = nil
    end
    ActiveRecord::Migration.verbose = true

    ActiveRecord::Base.establish_connection(config)

    # Tell the migrator where the migration files live. The connection-level
    # `migration_context` (used by bin/db) reads from here.
    ActiveRecord::Migrator.migrations_paths = [MIGRATIONS_DIR]

    @setup = true
  end
end
