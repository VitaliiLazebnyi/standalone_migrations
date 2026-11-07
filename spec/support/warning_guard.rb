# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

# Turns every Ruby warning raised from this project's own code (bin/, db/, lib/ and spec/) into a test
# failure. Warnings that originate in third-party gems are not collected here; they still reach stderr,
# where the CI warning gate rejects them.
module WarningGuard
  extend T::Sig

  # The project directory.
  PROJECT_ROOT = T.let(File.expand_path("../..", __dir__), String)
  # The directories whose warnings fail the suite.
  OWN_DIRECTORIES = T.let(
    %w[bin db lib spec].map { |directory| File.join(PROJECT_ROOT, directory) }
    .freeze,
    T::Array[String]
  )
  # The file a warning message names.
  LOCATION = /\A(?<path>[^:\n]+):\d+/
  # The warnings collected since the last .drain.
  COLLECTED = T.let(Queue.new, Thread::Queue)
  public_constant :PROJECT_ROOT, :OWN_DIRECTORIES, :LOCATION, :COLLECTED

  class << self
    extend T::Sig

    # Returns and forgets the warnings collected so far.
    # @return [Array<String>]
    sig { returns(T::Array[String]) }
    def drain
      Array.new(COLLECTED.size) { COLLECTED.pop.to_s }
    end

    # Whether +message+ names a file inside one of this project's own directories.
    # @param message [String] a Ruby warning message
    # @return [Boolean]
    sig { params(message: String).returns(T::Boolean) }
    def own?(message)
      match = LOCATION.match(message) or return false
      path = File.expand_path(match[:path].to_s)
      OWN_DIRECTORIES.any? { |directory| path.start_with?("#{directory}/") }
    end
  end

  # Records warnings coming from this project, then defers to Ruby's default handling.
  # @param message [String]
  # @param category [Symbol, nil] the warning category (deprecated, experimental, performance)
  # @return [void]
  sig { params(message: String, category: T.nilable(Symbol)).void }
  def warn(message, category: nil)
    COLLECTED << message if WarningGuard.own?(message)
    super
  end
end

Warning[:deprecated] = true
Warning[:experimental] = true
Warning[:performance] = true
Warning.singleton_class.prepend(WarningGuard)
