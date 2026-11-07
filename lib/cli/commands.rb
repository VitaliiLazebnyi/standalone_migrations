# typed: strict
# frozen_string_literal: true

require_relative "../migrator"

module CLI
  # One method per `db` command. Each takes the parsed KEY=value options and
  # returns the exit status.
  module Commands
    extend T::Sig

    # A STEP count: a positive integer.
    STEP_FORMAT = /\A[1-9]\d*\z/
    public_constant :STEP_FORMAT

    class << self
      extend T::Sig

      # `db migrate [VERSION=...]`
      #
      # @param options [Hash{String => String, nil}]
      # @return [Integer] the exit status
      # @raise [Migrator::InvalidInput] when VERSION is not a migration version
      sig { params(options: Options).returns(Integer) }
      def migrate(options)
        version = options["VERSION"]
        Migrator.migrate(version && Integer(Migrator::Input.migration_version(version), 10))
        0
      end

      # `db rollback [STEP=n]`
      #
      # @param options [Hash{String => String, nil}]
      # @return [Integer] the exit status
      # @raise [Migrator::InvalidInput] when STEP is not a positive integer
      sig { params(options: Options).returns(Integer) }
      def rollback(options)
        steps = options.fetch("STEP", "1").to_s
        unless STEP_FORMAT.match?(steps)
          raise Migrator::InvalidInput, "STEP must be a positive integer, got #{steps.inspect}"
        end

        Migrator.rollback(Integer(steps))
        0
      end

      # `db stamp VERSION=...`
      #
      # @param options [Hash{String => String, nil}]
      # @return [Integer] the exit status
      # @raise [Migrator::InvalidInput] when VERSION is missing or not a migration version
      sig { params(options: Options).returns(Integer) }
      def stamp(options)
        version = options["VERSION"]
        raise Migrator::InvalidInput, "Usage: db stamp VERSION=<version>" unless version

        Migrator.stamp(version)
        0
      end

      # `db baseline [NAME=...]`
      #
      # @param options [Hash{String => String, nil}]
      # @return [Integer] the exit status
      # @raise [Migrator::InvalidInput] when NAME is not a loadable migration name
      sig { params(options: Options).returns(Integer) }
      def baseline(options)
        Migrator.baseline(options["NAME"] || "baseline_schema")
        0
      end

      # `db help` (also `-h`, `--help`): print the usage.
      #
      # @param _options [Hash{String => String, nil}] ignored
      # @return [Integer] the exit status
      sig { params(_options: Options).returns(Integer) }
      def help(_options)
        $stdout.write(USAGE)
        0
      end

      # `db scan`
      #
      # @param _options [Hash{String => String, nil}] ignored
      # @return [Integer] the exit status
      sig { params(_options: Options).returns(Integer) }
      def scan(_options)
        Migrator.scan
        0
      end

      # `db seed`
      #
      # @param _options [Hash{String => String, nil}] ignored
      # @return [Integer] the exit status
      sig { params(_options: Options).returns(Integer) }
      def seed(_options)
        Migrator.seed
        0
      end

      # `db setup`
      #
      # @param _options [Hash{String => String, nil}] ignored
      # @return [Integer] the exit status
      sig { params(_options: Options).returns(Integer) }
      def setup(_options)
        Migrator.setup
        0
      end

      # `db console` (also `db psql`): replaces the process with psql.
      #
      # @param _options [Hash{String => String, nil}] ignored
      # @return [Integer] never returns
      sig { params(_options: Options).returns(T.noreturn) }
      def console(_options)
        Migrator.console
      end

      # `db status`
      #
      # @param _options [Hash{String => String, nil}] ignored
      # @return [Integer] the exit status
      sig { params(_options: Options).returns(Integer) }
      def status(_options)
        Migrator.status
        0
      end

      # `db version`
      #
      # @param _options [Hash{String => String, nil}] ignored
      # @return [Integer] the exit status
      sig { params(_options: Options).returns(Integer) }
      def version(_options)
        Migrator.version
        0
      end
    end
  end
end
