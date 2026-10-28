# typed: false
# frozen_string_literal: true

require "stringio"

# What a block prints, for assertions that need to normalise it first (migration timings vary).
module OutputCapture
  # @return [String] everything the block wrote to $stdout, with migration timings replaced by 0.0000s
  def stdout_of
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string.gsub(/\d+\.\d{4}s/, "0.0000s")
  ensure
    $stdout = original
  end
end
