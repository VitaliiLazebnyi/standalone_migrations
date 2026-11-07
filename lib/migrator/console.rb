# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "../boot"

module Migrator
  # The interactive psql session of `db console` (see Migrator.console).
  module Console
    class << self
      extend T::Sig

      # Replace the current process with psql, connected with the settings of config/database.yml.
      #
      # @return [void] never returns: the process becomes psql
      sig { returns(T.noreturn) }
      def start
        password, host, port, user, database = connection_settings
        exec({ "PGPASSWORD" => password }, "psql", "-h", host, "-p", port, "-U", user, database)
      end

      private

      # The password, host, port, user name and database of config/database.yml, as text ("" when unset).
      sig { returns([String, String, String, String, String]) }
      def connection_settings
        settings = Boot.config.transform_values(&:to_s)
        [
          settings.fetch("password", ""),
          settings.fetch("host", ""),
          settings.fetch("port", ""),
          settings.fetch("username", ""),
          settings.fetch("database", "")
        ]
      end
    end
  end
end
