# typed: false
# frozen_string_literal: true

RSpec.describe Migrator::Baseline do
  let(:schema) do
    <<~RUBY
      # This file is auto-generated from the current state of the database.

      ActiveRecord::Schema[8.1].define(version: 2024_01_01_000002) do
        # These are extensions that must be enabled in order to support this database
        enable_extension "pg_catalog.plpgsql"

        create_table "authors", force: :cascade, comment: "Écrivains" do |t|
          t.string "name"
        end
      end
    RUBY
  end
  let(:schema_file) { File.join(temporary_directory, "schema.rb") }
  let(:body) do
    <<~RUBY.gsub(/^/, "    ").gsub(/^ +$/, "")
      # These are extensions that must be enabled in order to support this database
      enable_extension "pg_catalog.plpgsql"

      create_table "authors", force: :cascade, comment: "Écrivains" do |t|
        t.string "name"
      end
    RUBY
  end

  before { File.write(schema_file, schema) }

  describe ".schema_body" do
    it "is the body of the define block, indented for `def change`" do
      expect(described_class.schema_body(schema_file)).to eq(body)
    end

    # Regression: the snapshot was read in the locale's encoding, so `db baseline` crashed with
    # "invalid byte sequence in US-ASCII" on a schema with non-ASCII comments under LANG=C.
    it "reads the schema as UTF-8 whatever the locale" do
      output, status = Open3.capture2e(
        { "LANG" => "C", "LC_ALL" => "C" }, RbConfig.ruby, "-I", File.join(Boot::ROOT, "lib"),
        "-r", "migrator", "-e", "print Migrator::Baseline.schema_body(ARGV.fetch(0))", schema_file
      )
      expect([output.force_encoding(Encoding::UTF_8), status.success?]).to eq([body, true])
    end

    it "returns UTF-8 text" do
      expect(described_class.schema_body(schema_file).encoding).to eq(Encoding::UTF_8)
    end

    it "fails without a define block" do
      File.write(schema_file, "# empty\nend\n")
      expect { described_class.schema_body(schema_file) }.to raise_error(
        RuntimeError, "Could not find a schema definition in #{schema_file}. Run `db scan` first."
      )
    end

    it "fails when the define block is not closed" do
      File.write(schema_file, "ActiveRecord::Schema[8.1].define(version: 1) do\n  create_table \"a\"\n")
      expect { described_class.schema_body(schema_file) }.to raise_error(RuntimeError, /Could not find a schema/)
    end

    it "ends at the last `end` of the file" do
      File.write(schema_file, "ActiveRecord::Schema[8.1].define(version: 1) do\n  x do\n  end\nend\n")
      expect(described_class.schema_body(schema_file)).to eq("    x do\n    end\n")
    end

    it "keeps blank and whitespace-only lines empty" do
      File.write(schema_file, "ActiveRecord::Schema[8.1].define(version: 1) do\n  a\n\n   \n  b\nend\n")
      expect(described_class.schema_body(schema_file)).to eq("    a\n\n\n    b\n")
    end

    it "is empty for an empty define block" do
      File.write(schema_file, "ActiveRecord::Schema[8.1].define(version: 0) do\nend\n")
      expect(described_class.schema_body(schema_file)).to eq("")
    end
  end

  describe ".migration_source" do
    it "is a reversible migration with the given body" do
      expect(described_class.migration_source("BaselineSchema", "    create_table \"a\"\n")).to eq(<<~RUBY)
        # AUTO-GENERATED baseline migration (`db baseline`).
        #
        # It captures the schema as it existed when this database was adopted into
        # migration control. On a FRESH database `db migrate` runs this to build the
        # whole schema from zero. On the ORIGINAL database it was *stamped* as already
        # applied, so it is never executed there.
        class BaselineSchema < ActiveRecord::Migration[8.1]
          def change
            create_table "a"
          end
        end
      RUBY
    end
  end

  describe ".write" do
    before do
      stub_const("Boot::SCHEMA_FILE", schema_file)
      stub_const("Boot::MIGRATIONS_DIR", File.join(temporary_directory, "new", "migrate"))
      allow(Time).to receive(:now).and_return(Time.new(2026, 1, 2, 3, 4, 5, "-08:00"))
    end

    let(:path) { File.join(Boot::MIGRATIONS_DIR, "20260102110405_adopt_shop.rb") }

    it "writes the migration, named with the UTC time, and returns its version", :aggregate_failures do
      expect { expect(described_class.write("adopt_shop")).to eq("20260102110405") }
        .to output("Wrote baseline migration -> #{path}\n").to_stdout
      expect(File.read(path)).to eq(described_class.migration_source("AdoptShop", body))
    end
  end

  describe ".announce" do
    it "explains the next steps and returns the version", :aggregate_failures do
      expect { expect(described_class.announce("123")).to eq("123") }.to output(<<~TEXT).to_stdout

        Done. This database is now under migration control at version 123.
        Fresh databases will rebuild the full schema from this migration; from
        here on, add new migrations with later timestamps and run `db migrate`.
      TEXT
    end
  end
end
