# typed: false
# frozen_string_literal: true

# Turns every Ruby warning raised from this project's own code (bin/, db/, lib/ and spec/) into a test
# failure. Warnings that originate in third-party gems are not collected here; they still reach stderr,
# where the CI warning gate rejects them.
module WarningGuard
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  OWN_DIRECTORIES = %w[bin db lib spec].map { |directory| File.join(PROJECT_ROOT, directory) }.freeze
  LOCATION = /\A(?<path>[^:\n]+):\d+/
  COLLECTED = Queue.new
  public_constant :PROJECT_ROOT, :OWN_DIRECTORIES, :LOCATION, :COLLECTED

  class << self
    # Returns and forgets the warnings collected so far.
    # @return [Array<String>]
    def drain
      Array.new(COLLECTED.size) { COLLECTED.pop }
    end

    # Whether +message+ names a file inside one of this project's own directories.
    # @param message [String] a Ruby warning message
    # @return [Boolean]
    def own?(message)
      match = LOCATION.match(message) or return false
      path = File.expand_path(match[:path])
      OWN_DIRECTORIES.any? { |directory| path.start_with?("#{directory}/") }
    end
  end

  # Records warnings coming from this project, then defers to Ruby's default handling.
  # @param message [String]
  # @return [void]
  def warn(message, ...)
    COLLECTED << message if WarningGuard.own?(message)
    super
  end
end

Warning[:deprecated] = true
Warning[:experimental] = true
Warning[:performance] = true
Warning.singleton_class.prepend(WarningGuard)
