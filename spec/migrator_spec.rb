# typed: false
# frozen_string_literal: true

RSpec.describe Migrator do
  let(:connection) { ActiveRecord::Base.connection }

  describe ".context" do
    it "reads the migrations of the configured directory" do
      use_temporary_migrations
      write_migration(1, "alphas")
      expect(described_class.context.migrations.map(&:name)).to eq(["CreateAlphas"])
    end

    it "reads the applied versions of the connected database" do
      ActiveRecord::Base.connection_pool.schema_migration.create_table
      ActiveRecord::Base.connection_pool.schema_migration.create_version("42")
      expect(described_class.context.get_all_versions).to eq([42])
    end
  end

  describe ".scan" do
    before { connection.create_table(:widgets) { |t| t.string :name, comment: "naïve — UTF-8" } }

    it "writes the schema of the live database", :aggregate_failures do
      path = File.join(temporary_directory, "schema.rb")
      expect { described_class.scan(path) }.to output("Scanned 1 tables -> #{path}\n").to_stdout
      expect(File.read(path, encoding: "UTF-8")).to include('create_table "widgets"', "naïve — UTF-8")
    end

    it "returns the path it wrote", :aggregate_failures do
      path = File.join(temporary_directory, "schema.rb")
      expect { expect(described_class.scan(path)).to eq(path) }.to output.to_stdout
    end

    it "creates the directory of the schema file", :aggregate_failures do
      path = File.join(temporary_directory, "a", "b", "schema.rb")
      expect { described_class.scan(path) }.to output.to_stdout
      expect(File).to exist(path)
    end

    it "writes Boot::SCHEMA_FILE by default", :aggregate_failures do
      stub_const("Boot::SCHEMA_FILE", File.join(temporary_directory, "default.rb"))
      expect { described_class.scan }.to output(/default\.rb/).to_stdout
      expect(File).to exist(Boot::SCHEMA_FILE)
    end
  end

  describe ".migrate" do
    before do
      use_temporary_migrations
      write_migration(1, "alphas")
      write_migration(2, "betas")
    end

    it "runs every pending migration", :aggregate_failures do
      expect { described_class.migrate }.to output(/Migrated\. Current schema version: 2\n\z/).to_stdout
      expect(connection.tables).to include("alphas", "betas")
    end

    it "shows the progress of each migration" do
      expect { described_class.migrate }.to output(/== 1 CreateAlphas: migrating.*== 2 CreateBetas: migrated/m)
        .to_stdout
    end

    it "stops at the target version", :aggregate_failures do
      expect { described_class.migrate(1) }.to output(/Current schema version: 1\n\z/).to_stdout
      expect(applied_versions).to eq([1])
    end

    it "migrates down to a lower target version", :aggregate_failures do
      expect { described_class.migrate }.to output.to_stdout
      expect { described_class.migrate(1) }.to output(/Current schema version: 1\n\z/).to_stdout
      expect(connection.tables).not_to include("betas")
    end
  end

  describe ".rollback" do
    before do
      use_temporary_migrations
      [1, 2, 3].each { |version| write_migration(version, "table#{version}") }
      stdout_of { described_class.migrate }
    end

    it "reverts the last migration", :aggregate_failures do
      expect { described_class.rollback }.to output(/Rolled back 1 migration\(s\)\. Current schema version: 2\n\z/)
        .to_stdout
      expect(applied_versions).to eq([1, 2])
    end

    it "reverts the given number of migrations", :aggregate_failures do
      expect { described_class.rollback(2) }.to output(/Rolled back 2 migration\(s\)\. Current schema version: 1\n\z/)
        .to_stdout
      expect(connection.tables).not_to include("table2", "table3")
    end
  end

  describe ".stamp" do
    it "records the version without running anything", :aggregate_failures do
      use_temporary_migrations
      write_migration(5, "alphas")
      expect { described_class.stamp("5") }.to output("Stamped version 5 as applied (without running it).\n")
        .to_stdout
      expect(applied_versions).to eq([5])
      expect(connection.tables).not_to include("alphas")
    end

    it "creates the schema_migrations table when it does not exist", :aggregate_failures do
      expect { described_class.stamp(7) }.to output.to_stdout
      expect(connection.select_values("SELECT version FROM schema_migrations")).to eq(["7"])
    end

    it "does nothing for a version that is already recorded", :aggregate_failures do
      expect { described_class.stamp("7") }.to output.to_stdout
      expect { described_class.stamp(" 7 ") }.to output("Version 7 is already recorded — nothing to do.\n").to_stdout
      expect(connection.select_values("SELECT version FROM schema_migrations")).to eq(["7"])
    end

    it "records the digits of an underscored version", :aggregate_failures do
      expect { described_class.stamp("2024_01_01_000003") }.to output(/Stamped version 20240101000003 /).to_stdout
      expect(connection.select_values("SELECT version FROM schema_migrations")).to eq(["20240101000003"])
    end

    # Regression: any string used to be written to schema_migrations (a typo such as VERSION=2024O101 stamped
    # a version that no migration has, and `db stamp VERSION=` crashed with an ArgumentError backtrace).
    it "rejects a version that is not a migration version, before touching the database", :aggregate_failures do
      expect { described_class.stamp("2024O101") }.to raise_error(Migrator::InvalidInput, /got "2024O101"/)
      expect(connection.tables).not_to include("schema_migrations")
    end
  end

  describe ".baseline" do
    let(:now) { Time.new(2026, 6, 25, 12, 34, 56, "+05:00") }
    let(:version) { "20260625073456" }

    before do
      connection.create_table(:authors) { |t| t.string :name }
      stub_const("Boot::SCHEMA_FILE", File.join(temporary_directory, "schema.rb"))
      stub_const("Boot::MIGRATIONS_DIR", migrations_directory)
      use_temporary_migrations
      allow(Time).to receive(:now).and_return(now)
    end

    it "snapshots the schema, writes a baseline migration and stamps it", :aggregate_failures do
      expect { expect(described_class.baseline).to eq(version) }.to output(<<~TEXT).to_stdout
        Scanned 1 tables -> #{Boot::SCHEMA_FILE}
        Wrote baseline migration -> #{File.join(migrations_directory, "#{version}_baseline_schema.rb")}
        Stamped version #{version} as applied (without running it).

        Done. This database is now under migration control at version #{version}.
        Fresh databases will rebuild the full schema from this migration; from
        here on, add new migrations with later timestamps and run `db migrate`.
      TEXT
      expect(applied_versions).to eq([Integer(version)])
      expect(described_class.context.migrations.map(&:name)).to eq(["BaselineSchema"])
    end

    it "names the migration after NAME", :aggregate_failures do
      expect { described_class.baseline("adopt_legacy_v2") }.to output.to_stdout
      expect(described_class.context.migrations.map(&:name)).to eq(["AdoptLegacyV2"])
    end

    it "writes a migration that rebuilds the schema on a fresh database", :aggregate_failures do
      expect { described_class.baseline }.to output.to_stdout
      connection.drop_table(:authors)
      connection.drop_table(:schema_migrations)
      expect { described_class.migrate }.to output(/BaselineSchema: migrated/).to_stdout
      expect(connection.columns(:authors).map(&:name)).to eq(%w[id name])
    end

    # Regression: the documented AR_MIGRATIONS_DIR=/app/your_db/migrate flow failed with Errno::ENOENT when
    # that directory did not exist yet.
    it "creates the migrations directory", :aggregate_failures do
      stub_const("Boot::MIGRATIONS_DIR", File.join(temporary_directory, "your_db", "migrate"))
      expect { described_class.baseline }.to output.to_stdout
      expect(Dir.children(Boot::MIGRATIONS_DIR)).to eq(["#{version}_baseline_schema.rb"])
    end

    # Regression: a NAME such as BaselineSchema or baseline-schema produced a file ActiveRecord ignores (or
    # cannot load), while the database was already stamped with its version.
    it "rejects a name ActiveRecord cannot load, before doing anything", :aggregate_failures do
      expect { described_class.baseline("Baseline-Schema") }.to raise_error(Migrator::InvalidInput, /NAME/)
      expect(File).not_to exist(Boot::SCHEMA_FILE)
      expect(connection.tables).not_to include("schema_migrations")
    end
  end

  describe ".seed" do
    it "loads the seed file", :aggregate_failures do
      file = File.join(temporary_directory, "seeds.rb")
      File.write(file, 'ActiveRecord::Base.connection.create_table(:seeded); puts "seeding"')
      expect { described_class.seed(file) }.to output("seeding\nSeeded from #{file}\n").to_stdout
      expect(connection.tables).to include("seeded")
    end

    it "loads Boot::SEEDS_FILE by default" do
      stub_const("Boot::SEEDS_FILE", File.join(temporary_directory, "default_seeds.rb"))
      File.write(Boot::SEEDS_FILE, "")
      expect { described_class.seed }.to output("Seeded from #{Boot::SEEDS_FILE}\n").to_stdout
    end

    it "fails when the seed file does not exist" do
      file = File.join(temporary_directory, "missing.rb")
      expect { described_class.seed(file) }.to raise_error(RuntimeError, "Seed file not found: #{file}")
    end
  end

  describe ".setup" do
    it "migrates, then seeds" do
      use_temporary_migrations
      write_migration(1, "alphas")
      stub_const("Boot::SEEDS_FILE", File.join(temporary_directory, "seeds.rb"))
      File.write(Boot::SEEDS_FILE, <<~'RUBY')
        puts "seeds see #{ActiveRecord::Base.connection.tables.sort.join(",")}"
      RUBY
      expect(stdout_of { described_class.setup }).to eq(<<~TEXT)
        ==> migrating...
        == 1 CreateAlphas: migrating ==================================================
        -- create_table(:alphas)
           -> 0.0000s
        == 1 CreateAlphas: migrated (0.0000s) =========================================

        Migrated. Current schema version: 1
        ==> seeding...
        seeds see alphas,ar_internal_metadata,schema_migrations
        Seeded from #{Boot::SEEDS_FILE}
        Ready: 3 tables, example data loaded.
      TEXT
    end
  end

  describe ".console" do
    it "replaces the process with psql, using the connection settings" do
      allow(Boot).to receive(:config).and_return(
        "host" => "db.example", "port" => 6543, "username" => "admin", "database" => "shop", "password" => "pw"
      )
      allow(described_class).to receive(:exec).and_throw(:exec)
      catch(:exec) { described_class.console }
      expect(described_class).to have_received(:exec)
        .with({ "PGPASSWORD" => "pw" }, "psql", "-h", "db.example", "-p", "6543", "-U", "admin", "shop")
    end

    it "passes empty values for empty settings" do
      allow(Boot).to receive(:config).and_return(
        "host" => nil, "port" => nil, "username" => nil, "database" => nil, "password" => nil
      )
      allow(described_class).to receive(:exec).and_throw(:exec)
      catch(:exec) { described_class.console }
      expect(described_class).to have_received(:exec).with({ "PGPASSWORD" => "" }, "psql", "-h", "", "-p", "", "-U",
                                                           "", "")
    end

    it "passes empty values for missing settings" do
      allow(Boot).to receive(:config).and_return({})
      allow(described_class).to receive(:exec).and_throw(:exec)
      catch(:exec) { described_class.console }
      expect(described_class).to have_received(:exec).with({ "PGPASSWORD" => "" }, "psql", "-h", "", "-p", "", "-U",
                                                           "", "")
    end
  end

  describe ".status" do
    it "lists every migration with its state, and the number pending", :aggregate_failures do
      use_temporary_migrations
      write_migration(1, "alphas")
      write_migration(2, "betas")
      expect { described_class.migrate(1) }.to output.to_stdout
      expect { described_class.status }.to output(<<~TEXT).to_stdout
        Status   Version          Name
        ------------------------------------------------------------
          up     1                CreateAlphas
         down    2                CreateBetas
        ------------------------------------------------------------
        1 pending migration(s).
      TEXT
    end
  end

  describe ".version" do
    it "prints the current schema version", :aggregate_failures do
      use_temporary_migrations
      write_migration(3, "alphas")
      expect { described_class.migrate }.to output.to_stdout
      expect { described_class.version }.to output("Current schema version: 3\n").to_stdout
    end
  end
end
