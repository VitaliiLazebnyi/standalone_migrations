# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "stringio"

# What a block prints, for assertions that need to normalise it first (migration timings vary).
module OutputCapture
  extend T::Sig

  # @yield the code whose output is captured
  # @return [String] everything the block wrote to $stdout, with migration timings replaced by 0.0000s
  sig { params(block: T.proc.void).returns(String) }
  def stdout_of(&block)
    original = $stdout
    capture = StringIO.new
    $stdout = capture
    yield
    capture.string.gsub(/\d+\.\d{4}s/, "0.0000s")
  ensure
    $stdout = original
  end
end
