# The three core functions the task asks for, plus a couple of helpers used by
# the CLI. Everything is built on ActiveRecord's real migration engine.
#
#   1. Migrator.scan      -> read the live database and write a full db/schema.rb
#   2. Migrator.migrate   -> run pending ActiveRecord::Migration files (up)
#   3. Migrator.rollback  -> revert the last N applied migrations (down)

require_relative "boot"

module Migrator
  module_function

  # The migration context. It knows about db/migrate (set in boot.rb) and the
  # schema_migrations / ar_internal_metadata bookkeeping tables. This single
  # object backs migrate / rollback / status.
  #
  # In Rails 8.x the schema-migration and internal-metadata bookkeeping lives on
  # the connection pool, so we build the context from there. We fall back to the
  # pool's own helper if present, keeping this resilient across point releases.
  def context
    pool = ActiveRecord::Base.connection_pool

    if pool.respond_to?(:migration_context)
      pool.migration_context
    else
      ActiveRecord::MigrationContext.new(
        Boot::MIGRATIONS_DIR,
        pool.schema_migration,
        pool.internal_metadata
      )
    end
  end

  # ---------------------------------------------------------------------------
  # FUNCTION 1: scan an existing database and produce the full schema.
  #
  # This is exactly what `rails db:schema:dump` does: introspect every table,
  # column, index, and foreign key on the live connection and serialise it into
  # a runnable db/schema.rb. Works on ANY database the connection can see, even
  # one created outside this tool.
  # ---------------------------------------------------------------------------
  def scan(output = Boot::SCHEMA_FILE)
    require "fileutils"
    FileUtils.mkdir_p(File.dirname(output))

    # In Rails 8.x SchemaDumper.dump takes the connection *pool* and leases a
    # connection internally (pool.with_connection).
    pool = ActiveRecord::Base.connection_pool

    File.open(output, "w:utf-8") do |file|
      ActiveRecord::SchemaDumper.dump(pool, file)
    end

    table_count = pool.with_connection { |c| c.tables.size }
    puts "Scanned #{table_count} tables -> #{output}"
    output
  end

  # ---------------------------------------------------------------------------
  # FUNCTION 2: conduct migrations.
  #
  # Runs every pending migration in db/migrate in version order (the `up`
  # direction). Pass a target version to migrate up to a specific point only.
  # ---------------------------------------------------------------------------
  def migrate(target_version = nil)
    context.migrate(target_version)
    puts "Migrated. Current schema version: #{context.current_version}"
  end

  # ---------------------------------------------------------------------------
  # FUNCTION 3: revert conducted migration(s).
  #
  # Rolls back the last `steps` applied migrations (the `down` direction),
  # mirroring `rails db:rollback STEP=n`.
  # ---------------------------------------------------------------------------
  def rollback(steps = 1)
    context.rollback(steps)
    puts "Rolled back #{steps} migration(s). Current schema version: #{context.current_version}"
  end

  # ---------------------------------------------------------------------------
  # STAMP: record a migration version as applied WITHOUT running it.
  #
  # This is the key primitive for adopting an existing database: the schema
  # already exists, so we only need to tell the bookkeeping table "this version
  # is done" rather than re-create tables that are already there.
  # ---------------------------------------------------------------------------
  def stamp(version)
    version = version.to_s.strip
    raise ArgumentError, "stamp requires a VERSION" if version.empty?

    sm = ActiveRecord::Base.connection_pool.schema_migration
    sm.create_table # ensure schema_migrations exists (no-op if it already does)

    if sm.versions.include?(version)
      puts "Version #{version} is already recorded — nothing to do."
    else
      sm.create_version(version)
      puts "Stamped version #{version} as applied (without running it)."
    end
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
  def baseline(name = "baseline_schema")
    require "fileutils"

    # 1. Snapshot the current schema.
    scan

    # 2. Generate the baseline migration from the snapshot.
    version    = Time.now.utc.strftime("%Y%m%d%H%M%S")
    class_name = name.split(/[_\s]/).map(&:capitalize).join
    filename   = File.join(Boot::MIGRATIONS_DIR, "#{version}_#{name}.rb")

    body = schema_body(Boot::SCHEMA_FILE)
    File.write(filename, baseline_migration_source(class_name, body))
    puts "Wrote baseline migration -> #{filename}"

    # 3. Stamp it so the existing database considers it already applied.
    stamp(version)

    puts
    puts "Done. This database is now under migration control at version #{version}."
    puts "Fresh databases will rebuild the full schema from this migration; from"
    puts "here on, add new migrations with later timestamps and run `db migrate`."
    version
  end

  # ---------------------------------------------------------------------------
  # SEED: load db/seeds.rb to populate the database with example data, mirroring
  # `rails db:seed`.
  # ---------------------------------------------------------------------------
  def seed(file = Boot::SEEDS_FILE)
    raise "Seed file not found: #{file}" unless File.exist?(file)
    load file
    puts "Seeded from #{file}"
  end

  # ---------------------------------------------------------------------------
  # SETUP: one-shot first-run convenience — apply all migrations, then seed.
  # ---------------------------------------------------------------------------
  def setup
    puts "==> migrating..."
    migrate
    puts "==> seeding..."
    seed
    table_count = ActiveRecord::Base.connection_pool.with_connection { |c| c.tables.size }
    puts "Ready: #{table_count} tables, example data loaded."
  end

  # ---------------------------------------------------------------------------
  # CONSOLE: drop into an interactive psql session against the database, using
  # the same connection settings as everything else. Replaces the current
  # process with psql (so Ctrl-D returns to the shell normally).
  # ---------------------------------------------------------------------------
  def console
    cfg = Boot.config
    ENV["PGPASSWORD"] = cfg["password"].to_s
    exec("psql",
         "-h", cfg["host"].to_s, "-p", cfg["port"].to_s,
         "-U", cfg["username"].to_s, cfg["database"].to_s)
  end

  # --- Helpers ---------------------------------------------------------------

  # Extract the contents of the `ActiveRecord::Schema[...].define(...) do ... end`
  # block from a dumped schema.rb, re-indented for a migration body.
  def schema_body(schema_file)
    lines = File.readlines(schema_file)
    start = lines.index { |l| l =~ /ActiveRecord::Schema\[.*\]\.define\(.*\)\s+do/ }
    raise "Could not find a schema definition in #{schema_file}. Run `db scan` first." unless start

    # Everything between the `define do` line and the file's final `end`.
    inner = lines[(start + 1)...lines.rindex { |l| l.rstrip == "end" }]
    # The dumped body is indented 2 spaces under `define`; add 2 more so it sits
    # neatly inside `def change`.
    inner.map { |l| l.strip.empty? ? "\n" : "  #{l}" }.join
  end

  # Render the baseline migration file. `change` is reversible (create_table /
  # add_foreign_key both reverse cleanly), so the baseline can also be rolled
  # back on a throwaway database.
  def baseline_migration_source(class_name, body)
    <<~RUBY
      # AUTO-GENERATED baseline migration (`db baseline`).
      #
      # It captures the schema as it existed when this database was adopted into
      # migration control. On a FRESH database `db migrate` runs this to build the
      # whole schema from zero. On the ORIGINAL database it was *stamped* as already
      # applied, so it is never executed there.
      class #{class_name} < ActiveRecord::Migration[8.1]
        def change
      #{body.chomp}
        end
      end
    RUBY
  end

  # Human-readable list of every migration and whether it is applied — the
  # equivalent of `rails db:migrate:status`.
  def status
    applied = context.get_all_versions
    puts "%-8s %-16s %s" % %w[Status Version Name]
    puts "-" * 60
    context.migrations.each do |m|
      mark = applied.include?(m.version) ? "  up  " : " down "
      puts "%-8s %-16s %s" % [mark, m.version, m.name]
    end
    pending = context.open.pending_migrations
    puts "-" * 60
    puts "#{pending.size} pending migration(s)."
  end

  def version
    puts "Current schema version: #{context.current_version}"
  end
end
