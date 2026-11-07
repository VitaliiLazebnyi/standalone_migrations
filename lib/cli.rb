# typed: strict
# frozen_string_literal: true

# The `db` command line (bin/db): parses Rails-style KEY=value arguments and
# dispatches to Migrator.

require_relative "cli/commands"
require_relative "migrator"

# `db <command> [KEY=value ...]`: a tiny Rails-like migration CLI.
module CLI
  extend T::Sig

  # The parsed KEY=value arguments, keyed by the upper-cased KEY.
  Options = T.type_alias { T::Hash[String, T.nilable(String)] }

  # Printed by `db help` (it starts with an empty line).
  USAGE = <<~TEXT

    `db` — a tiny Rails-like migration CLI built on standalone ActiveRecord.

      db setup              First run: migrate + seed in one step
      db migrate            Run all pending migrations (optionally VERSION=...)
      db rollback           Revert the last migration (optionally STEP=n)
      db scan               Dump the live database to db/schema.rb
      db seed               Load db/seeds.rb to populate example data
      db console            Open an interactive psql session (alias: db psql)
      db baseline           Adopt an existing DB: scan + generate a baseline
                            migration + stamp it as applied (optionally NAME=...)
      db stamp              Mark a migration version as applied without running it
                            (VERSION=... required)
      db status             Show applied / pending migrations
      db version            Show the current schema version
      db help               Show this message

    Tip: log every SQL statement (quiet by default) with `make migrate VERBOSE=1`,
         or `docker compose run --rm -e VERBOSE=1 app db migrate`.

    Examples:
      db setup
      db migrate
      db migrate VERSION=20240101000003
      db rollback STEP=2
      db console
      db baseline                       # one-shot adoption of an existing database
      db stamp VERSION=20260625000000

  TEXT

  # The method of {Commands} that runs each command.
  COMMANDS = T.let(
    {
      "migrate" => :migrate, "rollback" => :rollback, "scan" => :scan, "seed" => :seed, "setup" => :setup,
      "console" => :console, "psql" => :console, "baseline" => :baseline, "stamp" => :stamp,
      "status" => :status, "version" => :version, "help" => :help, "-h" => :help, "--help" => :help
    }.freeze,
    T::Hash[String, Symbol]
  )
  public_constant :Options, :USAGE, :COMMANDS

  class << self
    extend T::Sig

    # Boot ActiveRecord and run the command named by the first argument.
    #
    # @param argv [Array<String>] the command followed by KEY=value arguments
    # @return [Integer] the process exit status
    sig { params(argv: T::Array[String]).returns(Integer) }
    def run(argv)
      Boot.setup!
      command, *arguments = argv
      dispatch(command || "help", parse_options(arguments))
    rescue Migrator::InvalidInput => error
      report(error.message)
    end

    # Allow Rails-style KEY=value arguments (STEP=2, VERSION=...). A bare word
    # becomes a key without a value.
    #
    # @param arguments [Array<String>]
    # @return [Hash{String => String, nil}]
    sig { params(arguments: T::Array[String]).returns(Options) }
    def parse_options(arguments)
      arguments.to_h do |argument|
        key, value = argument.split("=", 2)
        [key.to_s.upcase, value]
      end
    end

    private

    # Run +command+, or report that there is no such command.
    sig { params(command: String, options: Options).returns(Integer) }
    def dispatch(command, options)
      name = COMMANDS[command]
      return Commands.public_send(name, options) if name

      warn "Unknown command: #{command}"
      warn "Run `db help` for usage."
      1
    end

    # Print the problem with the arguments; the command fails.
    sig { params(message: String).returns(Integer) }
    def report(message)
      warn message
      1
    end
  end
end
