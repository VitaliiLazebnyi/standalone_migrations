# typed: strict
# frozen_string_literal: true

# The three core functions the task asks for, plus a couple of helpers used by
# the CLI. Everything is built on ActiveRecord's real migration engine.
#
#   1. Migrator.scan      -> read the live database and write a full db/schema.rb
#   2. Migrator.migrate   -> run pending ActiveRecord::Migration files (up)
#   3. Migrator.rollback  -> revert the last N applied migrations (down)

require "fileutils"
require "stringio"
require_relative "boot"
require_relative "migrator/baseline"
require_relative "migrator/input"
require_relative "migrator/status"

# Schema scanning, migrating, rolling back and the adoption helpers behind `bin/db`.
module Migrator
  extend T::Sig

  # Raised for a malformed argument (a migration version or a migration name)
  # before anything touches the database.
  class InvalidInput < ArgumentError; end
  public_constant :InvalidInput

  class << self
    extend T::Sig

    # The migration context. It knows about db/migrate (set in boot.rb) and the
    # schema_migrations / ar_internal_metadata bookkeeping tables. This single
    # object backs migrate / rollback / status.
    #
    # In Rails 8.x the schema-migration and internal-metadata bookkeeping lives on
    # the connection pool, so we build the context from there.
    #
    # @return [ActiveRecord::MigrationContext]
    sig { returns(ActiveRecord::MigrationContext) }
    def context
      pool.migration_context
    end

    # ---------------------------------------------------------------------------
    # FUNCTION 1: scan an existing database and produce the full schema.
    #
    # This is exactly what `rails db:schema:dump` does: introspect every table,
    # column, index, and foreign key on the live connection and serialise it into
    # a runnable db/schema.rb. Works on ANY database the connection can see, even
    # one created outside this tool.
    # ---------------------------------------------------------------------------
    #
    # @param output [String] the schema file to write
    # @return [String] the path written
    sig { params(output: String).returns(String) }
    def scan(output = Boot::SCHEMA_FILE)
      FileUtils.mkdir_p(File.dirname(output))
      File.write(output, dump_schema)
      puts "Scanned #{table_count} tables -> #{output}"
      output
    end

    # ---------------------------------------------------------------------------
    # FUNCTION 2: conduct migrations.
    #
    # Runs every pending migration in db/migrate in version order (the `up`
    # direction). Pass a target version to migrate up to a specific point only.
    # ---------------------------------------------------------------------------
    #
    # @param target_version [Integer, nil] the version to migrate to; nil for all pending
    # @return [void]
    sig { params(target_version: T.nilable(Integer)).void }
    def migrate(target_version = nil)
      migration_context = context
      migration_context.migrate(target_version)
      puts "Migrated. Current schema version: #{migration_context.current_version}"
    end

    # ---------------------------------------------------------------------------
    # FUNCTION 3: revert conducted migration(s).
    #
    # Rolls back the last `steps` applied migrations (the `down` direction),
    # mirroring `rails db:rollback STEP=n`.
    # ---------------------------------------------------------------------------
    #
    # @param steps [Integer] how many applied migrations to revert
    # @return [void]
    sig { params(steps: Integer).void }
    def rollback(steps = 1)
      migration_context = context
      migration_context.rollback(steps)
      puts "Rolled back #{steps} migration(s). Current schema version: #{migration_context.current_version}"
    end

    # ---------------------------------------------------------------------------
    # STAMP: record a migration version as applied WITHOUT running it.
    #
    # This is the key primitive for adopting an existing database: the schema
    # already exists, so we only need to tell the bookkeeping table "this version
    # is done" rather than re-create tables that are already there.
    # ---------------------------------------------------------------------------
    #
    # @param version [String, Integer] the migration version to record
    # @return [void]
    # @raise [InvalidInput] when the version is not a migration version
    sig { params(version: T.any(String, Integer)).void }
    def stamp(version)
      version = Input.migration_version(version)
      schema_migration = pool.schema_migration
      schema_migration.create_table # ensure schema_migrations exists (no-op if it already does)
      record(schema_migration, version)
    end

    # ---------------------------------------------------------------------------
    # BASELINE: one-command adoption of an existing/production database.
    #
    #   1. scan the live database into db/schema.rb
    #   2. generate a self-contained baseline migration from that snapshot, so a
    #      FRESH database can rebuild the whole schema from zero with `db migrate`
    #   3. stamp that baseline version, so the EXISTING database treats it as
    #      already applied and `db migrate` never tries to re-create its tables
    #
    # After this, just write new migrations with later timestamps as usual.
    # ---------------------------------------------------------------------------
    #
    # @param name [String] the migration name (lower case, e.g. baseline_schema)
    # @return [String] the version of the baseline migration
    # @raise [InvalidInput] when the name is not a loadable migration name
    sig { params(name: String).returns(String) }
    def baseline(name = "baseline_schema")
      Input.migration_name(name)
      # 1. Snapshot the current schema.
      scan
      # 2. Generate the baseline migration from the snapshot.
      version = Baseline.write(name)
      # 3. Stamp it so the existing database considers it already applied.
      stamp(version)
      Baseline.announce(version)
    end

    # ---------------------------------------------------------------------------
    # SEED: load db/seeds.rb to populate the database with example data, mirroring
    # `rails db:seed`.
    # ---------------------------------------------------------------------------
    #
    # @param file [String] the seed file to load
    # @return [void]
    sig { params(file: String).void }
    def seed(file = Boot::SEEDS_FILE)
      raise "Seed file not found: #{file}" unless File.exist?(file)

      load file
      puts "Seeded from #{file}"
    end

    # ---------------------------------------------------------------------------
    # SETUP: one-shot first-run convenience — apply all migrations, then seed.
    # ---------------------------------------------------------------------------
    #
    # @return [void]
    sig { void }
    def setup
      puts "==> migrating..."
      migrate
      puts "==> seeding..."
      seed
      puts "Ready: #{table_count} tables, example data loaded."
    end

    # ---------------------------------------------------------------------------
    # CONSOLE: drop into an interactive psql session against the database, using
    # the same connection settings as everything else. Replaces the current
    # process with psql (so Ctrl-D returns to the shell normally).
    # ---------------------------------------------------------------------------
    #
    # @return [void] never returns: the process becomes psql
    sig { returns(T.noreturn) }
    def console
      settings = Boot.config.transform_values(&:to_s)
      exec({ "PGPASSWORD" => settings.fetch("password", "") },
           "psql",
           "-h", settings.fetch("host", ""),
           "-p", settings.fetch("port", ""),
           "-U", settings.fetch("username", ""),
           settings.fetch("database", ""))
    end

    # Human-readable list of every migration and whether it is applied — the
    # equivalent of `rails db:migrate:status`. An applied version whose
    # migration file is missing is listed as NO FILE.
    #
    # @return [void]
    sig { void }
    def status
      Status.print(context)
    end

    # Print the current schema version.
    #
    # @return [void]
    sig { void }
    def version
      puts "Current schema version: #{context.current_version}"
    end

    private

    sig { returns(ActiveRecord::ConnectionAdapters::ConnectionPool) }
    def pool
      ActiveRecord::Base.connection_pool
    end

    sig { params(schema_migration: ActiveRecord::SchemaMigration, version: String).void }
    def record(schema_migration, version)
      if schema_migration.versions.include?(version)
        puts "Version #{version} is already recorded — nothing to do."
      else
        schema_migration.create_version(version)
        puts "Stamped version #{version} as applied (without running it)."
      end
    end

    # In Rails 8.x SchemaDumper.dump takes the connection *pool* and leases a
    # connection internally (pool.with_connection).
    sig { returns(String) }
    def dump_schema
      StringIO.new.tap { |schema| ActiveRecord::SchemaDumper.dump(pool, schema) }.string
    end

    sig { returns(Integer) }
    def table_count
      pool.with_connection { |connection| connection.tables.size }
    end
  end
end
