# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Migrator
  # Validates the migration versions and names given on the command line (or to
  # Migrator) before they reach the database or the file system.
  module Input
    extend T::Sig

    # A migration version: digits, optionally grouped with underscores
    # (ActiveRecord's own format, e.g. 20240101000003 or 2024_01_01_000003).
    VERSION_FORMAT = /\A\d(_?\d)*\z/
    # A migration name ActiveRecord can load: the file name part after the
    # version, which must be lower case (e.g. baseline_schema).
    NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/
    public_constant :VERSION_FORMAT, :NAME_FORMAT

    class << self
      extend T::Sig

      # The version as schema_migrations stores it: stripped, without underscores.
      #
      # @param version [String, Integer] a migration version, e.g. 2024_01_01_000003
      # @return [String] its digits, e.g. "20240101000003"
      # @raise [InvalidInput] when it is not a migration version
      sig { params(version: T.any(String, Integer)).returns(String) }
      def migration_version(version)
        text = version.to_s.strip
        unless VERSION_FORMAT.match?(text)
          raise InvalidInput, "VERSION must be a migration version (digits only), got #{text.inspect}"
        end

        text.delete("_")
      end

      # A migration name that ActiveRecord can load from a file name.
      #
      # @param name [String] e.g. baseline_schema
      # @return [String] the name
      # @raise [InvalidInput] when it is not lower case letters, digits and underscores
      sig { params(name: String).returns(String) }
      def migration_name(name)
        unless NAME_FORMAT.match?(name)
          raise InvalidInput, "NAME must be lower case letters, digits and underscores, got #{name.inspect}"
        end

        name
      end
    end
  end
end
