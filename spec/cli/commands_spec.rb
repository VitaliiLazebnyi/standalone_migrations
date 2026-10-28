# typed: false
# frozen_string_literal: true

RSpec.describe CLI::Commands do
  describe ".migrate" do
    before { allow(Migrator).to receive(:migrate) }

    it "migrates everything without VERSION", :aggregate_failures do
      expect(described_class.migrate({})).to eq(0)
      expect(Migrator).to have_received(:migrate).with(nil)
    end

    it "migrates to VERSION" do
      described_class.migrate("VERSION" => "20240101000003")
      expect(Migrator).to have_received(:migrate).with(20_240_101_000_003)
    end

    it "accepts an underscored VERSION" do
      described_class.migrate("VERSION" => "2024_01_01_000003")
      expect(Migrator).to have_received(:migrate).with(20_240_101_000_003)
    end

    it "reads VERSION as decimal" do
      described_class.migrate("VERSION" => "010")
      expect(Migrator).to have_received(:migrate).with(10)
    end

    # Regression: VERSION was converted with String#to_i, so an empty or mistyped VERSION became 0 and
    # `db migrate` rolled back every migration.
    ["", "abc", "2024-01-01", "20240101O00003"].each do |invalid|
      it "rejects VERSION=#{invalid} instead of migrating down to 0", :aggregate_failures do
        expect { described_class.migrate("VERSION" => invalid) }.to raise_error(Migrator::InvalidInput, /VERSION/)
        expect(Migrator).not_to have_received(:migrate)
      end
    end
  end

  describe ".rollback" do
    before { allow(Migrator).to receive(:rollback) }

    it "reverts one migration without STEP", :aggregate_failures do
      expect(described_class.rollback({})).to eq(0)
      expect(Migrator).to have_received(:rollback).with(1)
    end

    it "reverts STEP migrations" do
      described_class.rollback("STEP" => "12")
      expect(Migrator).to have_received(:rollback).with(12)
    end

    it "reads STEP as decimal" do
      described_class.rollback("STEP" => "10")
      expect(Migrator).to have_received(:rollback).with(10)
    end

    # Regression: STEP was converted with String#to_i, so STEP=abc (0) printed "Rolled back 0 migration(s)"
    # and STEP=-1 moved the migrator in the wrong direction.
    [nil, "", "0", "-1", "abc", "2x", "01", "1.5"].each do |invalid|
      it "rejects STEP=#{invalid.inspect}", :aggregate_failures do
        expect { described_class.rollback("STEP" => invalid) }.to raise_error(
          Migrator::InvalidInput, "STEP must be a positive integer, got #{invalid.to_s.inspect}"
        )
        expect(Migrator).not_to have_received(:rollback)
      end
    end
  end

  describe ".stamp" do
    before { allow(Migrator).to receive(:stamp) }

    it "stamps VERSION", :aggregate_failures do
      expect(described_class.stamp("VERSION" => "20260625000000")).to eq(0)
      expect(Migrator).to have_received(:stamp).with("20260625000000")
    end

    it "requires VERSION", :aggregate_failures do
      expect { described_class.stamp({}) }.to raise_error(Migrator::InvalidInput, "Usage: db stamp VERSION=<version>")
      expect(Migrator).not_to have_received(:stamp)
    end
  end

  describe ".baseline" do
    before { allow(Migrator).to receive(:baseline) }

    it "names the baseline baseline_schema by default", :aggregate_failures do
      expect(described_class.baseline({})).to eq(0)
      expect(Migrator).to have_received(:baseline).with("baseline_schema")
    end

    it "names the baseline after NAME" do
      described_class.baseline("NAME" => "adopt_shop")
      expect(Migrator).to have_received(:baseline).with("adopt_shop")
    end
  end

  describe ".help" do
    it "prints the usage", :aggregate_failures do
      expect { expect(described_class.help({})).to eq(0) }.to output(CLI::USAGE).to_stdout
    end
  end

  %i[scan seed setup status version].each do |command|
    describe ".#{command}" do
      it "runs Migrator.#{command} and succeeds", :aggregate_failures do
        allow(Migrator).to receive(command)
        expect(described_class.public_send(command, {})).to eq(0)
        expect(Migrator).to have_received(command).with(no_args)
      end
    end
  end

  describe ".console" do
    it "replaces the process with psql" do
      allow(Migrator).to receive(:console).and_throw(:exec)
      catch(:exec) { described_class.console({}) }
      expect(Migrator).to have_received(:console).with(no_args)
    end
  end
end
