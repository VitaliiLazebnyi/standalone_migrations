# typed: false
# frozen_string_literal: true

RSpec.describe CLI do
  describe ".run" do
    it "boots ActiveRecord first", :aggregate_failures do
      allow(Boot).to receive(:setup!)
      expect { described_class.run(["help"]) }.to output.to_stdout
      expect(Boot).to have_received(:setup!)
    end

    it "runs the command with the parsed options and returns its exit status", :aggregate_failures do
      allow(CLI::Commands).to receive(:rollback).and_return(0)
      expect(described_class.run(%w[rollback STEP=2 dry])).to eq(0)
      expect(CLI::Commands).to have_received(:rollback).with("STEP" => "2", "DRY" => nil)
    end

    it "shows the usage without a command", :aggregate_failures do
      expect { expect(described_class.run([])).to eq(0) }.to output(CLI::USAGE).to_stdout
    end

    {
      "migrate" => :migrate, "rollback" => :rollback, "scan" => :scan, "seed" => :seed, "setup" => :setup,
      "console" => :console, "psql" => :console, "baseline" => :baseline, "stamp" => :stamp,
      "status" => :status, "version" => :version, "help" => :help, "-h" => :help, "--help" => :help
    }.each do |command, method|
      it "runs `#{command}` with Commands.#{method}" do
        allow(CLI::Commands).to receive(method).and_return(0)
        described_class.run([command])
        expect(CLI::Commands).to have_received(method).with({})
      end
    end

    it "rejects an unknown command", :aggregate_failures do
      expect { expect(described_class.run(%w[migrat VERSION=1])).to eq(1) }
        .to output("Unknown command: migrat\nRun `db help` for usage.\n").to_stderr
    end

    it "reports invalid input without a backtrace", :aggregate_failures do
      expect { expect(described_class.run(%w[rollback STEP=0])).to eq(1) }
        .to output("STEP must be a positive integer, got \"0\"\n").to_stderr
    end

    it "lets other errors through" do
      allow(CLI::Commands).to receive(:scan).and_raise(ArgumentError, "a bug")
      expect { described_class.run(["scan"]) }.to raise_error(ArgumentError, "a bug")
    end
  end

  describe ".parse_options" do
    it "upcases the keys" do
      expect(described_class.parse_options(%w[step=2 Version=3])).to eq("STEP" => "2", "VERSION" => "3")
    end

    it "splits at the first equals sign" do
      expect(described_class.parse_options(["NAME=a=b"])).to eq("NAME" => "a=b")
    end

    it "keeps an empty value" do
      expect(described_class.parse_options(["VERSION="])).to eq("VERSION" => "")
    end

    it "makes a bare word a key without a value" do
      expect(described_class.parse_options(["dry"])).to eq("DRY" => nil)
    end

    # Regression: an empty argument (`db migrate ""`) crashed with NoMethodError (upcase on nil).
    it "accepts an empty argument" do
      expect(described_class.parse_options([""])).to eq("" => nil)
    end

    it "lets a later value win" do
      expect(described_class.parse_options(%w[STEP=1 STEP=2])).to eq("STEP" => "2")
    end
  end

  describe "USAGE" do
    # The text `db help` printed before the CLI moved into lib/: the leading comment block of bin/db.
    it "is unchanged" do
      expect(CLI::USAGE).to start_with("\n`db` — a tiny Rails-like migration CLI built on standalone ActiveRecord.\n")
        .and end_with("  db stamp VERSION=20260625000000\n\n")
        .and include("  db stamp              Mark a migration version as applied without running it\n")
        .and include("\n                        (VERSION=... required)\n")
    end
  end
end
