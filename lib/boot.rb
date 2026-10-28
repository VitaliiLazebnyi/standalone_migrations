# typed: strict
# frozen_string_literal: true

# Boots a standalone ActiveRecord environment: loads config/database.yml,
# establishes the connection, and points the migrator at db/migrate.
#
# Required by bin/db before any database work happens.

require "active_record"
require "erb"
require "logger"
require "sorbet-runtime"
require "yaml"

# Connection settings and file locations shared by the migrator and the CLI.
module Boot
  extend T::Sig

  # The project directory (the parent of lib/).
  ROOT = T.let(File.expand_path("..", __dir__), String)
  # The paths can be overridden via env, which is handy when adopting a
  # separate database into its own migrations directory.
  #
  # Where migration files live (AR_MIGRATIONS_DIR overrides it).
  MIGRATIONS_DIR = T.let(ENV.fetch("AR_MIGRATIONS_DIR", File.join(ROOT, "db", "migrate")), String)
  # Where `db scan` writes the schema snapshot (AR_SCHEMA_FILE overrides it).
  SCHEMA_FILE = T.let(ENV.fetch("AR_SCHEMA_FILE", File.join(ROOT, "db", "schema.rb")), String)
  # The seed data loaded by `db seed` (AR_SEEDS_FILE overrides it).
  SEEDS_FILE = T.let(ENV.fetch("AR_SEEDS_FILE", File.join(ROOT, "db", "seeds.rb")), String)
  # The section of config/database.yml to connect with (AR_ENV overrides it).
  ENVIRONMENT = T.let(ENV.fetch("AR_ENV", "development"), String)
  public_constant :ROOT, :MIGRATIONS_DIR, :SCHEMA_FILE, :SEEDS_FILE, :ENVIRONMENT

  class << self
    extend T::Sig

    # Parse config/database.yml (with ERB) and return the hash for the current
    # environment.
    #
    # @return [Hash{String => Object}] the connection settings
    sig { returns(T::Hash[String, Object]) }
    def config
      raw = File.read(File.join(ROOT, "config", "database.yml"))
      YAML.safe_load(ERB.new(raw).result, aliases: true).fetch(ENVIRONMENT)
    end

    # Connect and configure the migration engine. Idempotent: once the migrator
    # points at {MIGRATIONS_DIR}, later calls do nothing.
    #
    # @return [void]
    sig { void }
    def setup!
      return if ActiveRecord::Migrator.migrations_paths == [MIGRATIONS_DIR]

      configure_output
      ActiveRecord::Base.establish_connection(config)

      # Tell the migrator where the migration files live. The connection-level
      # `migration_context` (used by bin/db) reads from here.
      ActiveRecord::Migrator.migrations_paths = [MIGRATIONS_DIR]
    end

    private

    # By default, keep output clean: show the high-level migration progress
    # (the `== ... migrating ==` lines) but not the raw DEBUG SQL. Set VERBOSE=1
    # to log every SQL statement — useful for demos and debugging.
    sig { void }
    def configure_output
      ActiveRecord::Base.logger = (Logger.new($stdout) if ENV["VERBOSE"] == "1")
      ActiveRecord::Migration.verbose = true
    end
  end
end
