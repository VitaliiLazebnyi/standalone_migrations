# typed: false
# frozen_string_literal: true

RSpec.describe Boot do
  describe "the file locations" do
    it "defaults to the example project" do
      expect(boot_constants({})).to eq(
        [File.join(Boot::ROOT, "db", "migrate"), File.join(Boot::ROOT, "db", "schema.rb"),
         File.join(Boot::ROOT, "db", "seeds.rb"), "development"]
      )
    end

    it "honours the AR_* overrides" do
      environment = { "AR_MIGRATIONS_DIR" => "/m", "AR_SCHEMA_FILE" => "/s.rb", "AR_SEEDS_FILE" => "/seeds.rb",
                      "AR_ENV" => "production" }
      expect(boot_constants(environment)).to eq(["/m", "/s.rb", "/seeds.rb", "production"])
    end

    it "is the project directory" do
      expect(Boot::ROOT).to eq(File.expand_path("..", __dir__))
    end
  end

  describe ".config" do
    it "reads the section of the current environment, rendered with ERB" do
      write_database_yml(<<~YAML)
        development:
          adapter: postgresql
          port: <%= 1 + 1 %>
        test:
          adapter: other
      YAML
      expect(described_class.config).to eq("adapter" => "postgresql", "port" => 2)
    end

    it "reads the section named by Boot::ENVIRONMENT" do
      write_database_yml("development:\n  adapter: a\ntest:\n  adapter: b\n")
      stub_const("Boot::ENVIRONMENT", "test")
      expect(described_class.config).to eq("adapter" => "b")
    end

    it "supports YAML aliases" do
      write_database_yml(<<~YAML)
        default: &default
          adapter: postgresql
        development:
          <<: *default
          database: app
      YAML
      expect(described_class.config).to eq("adapter" => "postgresql", "database" => "app")
    end

    it "fails when the environment has no section" do
      write_database_yml("production:\n  adapter: a\n")
      expect { described_class.config }.to raise_error(KeyError, /development/)
    end

    it "refuses YAML that would instantiate arbitrary objects" do
      write_database_yml("development: !ruby/object:Object {}\n")
      expect { described_class.config }.to raise_error(Psych::DisallowedClass)
    end

    it "takes the connection settings of the example project from the environment" do
      expect(described_class.config).to include(
        "adapter" => "postgresql", "encoding" => "unicode", "pool" => 5,
        "host" => ENV.fetch("DATABASE_HOST", "localhost"), "database" => ENV.fetch("DATABASE_NAME")
      )
    end
  end

  describe ".setup!" do
    before { ActiveRecord::Migrator.migrations_paths = ["db/migrate"] }

    it "connects with .config" do
      allow(ActiveRecord::Base).to receive(:establish_connection).and_call_original
      described_class.setup!
      expect(ActiveRecord::Base).to have_received(:establish_connection).with(described_class.config)
    end

    it "points the migrator at the migrations directory" do
      described_class.setup!
      expect(ActiveRecord::Migrator.migrations_paths).to eq([Boot::MIGRATIONS_DIR])
    end

    it "shows the migration progress" do
      ActiveRecord::Migration.verbose = false
      described_class.setup!
      expect(ActiveRecord::Migration.verbose).to be(true)
    end

    it "does not log SQL by default" do
      ActiveRecord::Base.logger = Logger.new(File::NULL)
      described_class.setup!
      expect(ActiveRecord::Base.logger).to be_nil
    end

    context "with VERBOSE=1" do
      before { stub_const("ENV", ENV.to_h.merge("VERBOSE" => "1")) }

      it "logs SQL to stdout" do
        log = stdout_of do
          described_class.setup!
          ActiveRecord::Base.logger.info("the SQL log")
        end
        expect(log).to include("the SQL log")
      end
    end

    it "does not log SQL for another VERBOSE value" do
      stub_const("ENV", ENV.to_h.merge("VERBOSE" => "true"))
      described_class.setup!
      expect(ActiveRecord::Base.logger).to be_nil
    end

    it "does nothing once the migrator points at the migrations directory" do
      described_class.setup!
      allow(ActiveRecord::Base).to receive(:establish_connection)
      described_class.setup!
      expect(ActiveRecord::Base).not_to have_received(:establish_connection)
    end
  end
end
