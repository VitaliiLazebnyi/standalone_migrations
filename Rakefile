# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 Vitalii Lazebnyi

require "rspec/core/rake_task"
require "sorbet-runtime"

# The Ruby gates of the verification suite. `bundle exec rake` runs every one that needs neither the network
# nor another Ruby; script/check runs all of them and the repository linters, exactly as CI does (see
# CONTRIBUTING.md). The tasks are defined in this module, which extends Rake's DSL, so that Sorbet checks
# them like any other code.
module Tasks
  extend Rake::DSL
  extend T::Sig

  # The Ruby code that the smell, duplication and complexity checks cover. db/ holds ActiveRecord's
  # declarative migration and seed DSL, and spec/ the RSpec DSL; RuboCop and Sorbet cover both.
  CODE = %w[lib bin script].freeze
  # Output of `yard stats` when every API object, private ones included, is documented.
  FULLY_DOCUMENTED = "100.00% documented"
  # The flog score above which a method counts as too complex and must be split up (flog's "good" band
  # ends at 20).
  FLOG_LIMIT = 20.0
  # The Ruby the mutation-testing bundle runs on (see mutant.gemfile).
  MUTANT_RUBY = T.let(File.read(File.join(__dir__, "mutant.gemfile"))[/^ruby "([\d.]+)"/, 1].to_s, String)
  public_constant :CODE, :FULLY_DOCUMENTED, :FLOG_LIMIT, :MUTANT_RUBY

  class << self
    extend T::Sig

    # Run +command+, print its output and fail unless it succeeds and its report contains +clean+.
    #
    # @param command [Array<String>] the tool's command line
    # @param clean [String] the text the report holds when there is nothing to fix
    # @param failure [String] the message to fail with otherwise
    # @return [String] the report
    sig { params(command: T::Array[String], clean: String, failure: String).returns(String) }
    def require_clean(command, clean, failure)
      output = IO.popen(command, err: %i[child out], &:read).to_s
      puts(output)
      abort(failure) unless Process.last_status&.success? && output.include?(clean)
      output
    end

    # The methods of a flog report that score above FLOG_LIMIT.
    #
    # @param report [String] the output of `flog --all --methods-only`
    # @return [Array<String>] each method with its score
    sig { params(report: String).returns(T::Array[String]) }
    def too_complex(report)
      scores = report.scan(/^\s*(\d+\.\d+): (\S+)\s+\S+:\d+/)
      scores.filter_map { |score, name| "#{name} (#{score})" if Float(score.to_s) > FLOG_LIMIT }
    end
  end

  # `-w` turns on Ruby's verbose warnings, as in CI; spec/support/warning_guard.rb fails the suite on any
  # warning raised by the project's own files.
  RSpec::Core::RakeTask.new(:spec) { |task| task.ruby_opts = "-w" }

  desc("Run RuboCop with every cop and plugin (no todo file, no inline directives)")
  task(:rubocop) { sh("bundle", "exec", "rubocop") }

  desc("Fail on inline suppressions of any linter, scanner, type checker, warning or test")
  task(:suppressions) { sh("script/forbidden_suppressions.sh") }

  desc("Generate the gem RBIs with Tapioca, then run the Sorbet type checker")
  task(:typecheck) do
    # Tapioca runs from its own bundle. Under `bundle exec rake` the environment (RUBYOPT=-rbundler/setup,
    # BUNDLE_GEMFILE) belongs to the main bundle, so the nested commands run in an unbundled environment.
    Bundler.with_unbundled_env do
      # typecheck.gemfile.lock is generated here, so the bundle may not be frozen (setup-ruby's cache
      # turns on deployment mode for the main bundle).
      sh(
        { "BUNDLE_GEMFILE" => "typecheck.gemfile", "BUNDLE_DEPLOYMENT" => "false", "BUNDLE_FROZEN" => "false" },
        "bundle",
        "install",
        "--quiet"
      )
      sh({ "BUNDLE_GEMFILE" => "typecheck.gemfile" }, "bundle", "exec", "tapioca", "gem", "--all")
    end
    # Tapioca already merges the RBIs that gems ship themselves into the generated ones; srb must not load
    # them a second time.
    sh({ "SRB_SKIP_GEM_RBIS" => "1" }, "bundle", "exec", "srb", "tc")
  end

  desc(
    "Build the YARD documentation (warnings are fatal) and require every object, private ones included, " \
    "to be documented"
  )
  task(:yard) do
    sh("bundle", "exec", "yardoc", "--fail-on-warning", "--no-output")
    report = Tasks.require_clean(
      %w[bundle exec yard stats --list-undoc --private --protected],
      FULLY_DOCUMENTED,
      "YARD: undocumented API objects found"
    )
    abort("YARD: warnings") if report.include?("[warn]")
  end

  desc("Fail on any code smell (default Reek configuration, no exclusions)")
  task(:reek) { sh("bundle", "exec", "reek", *CODE) }

  desc("Fail on any structural duplication (Flay's default mass)")
  task(:flay) do
    Tasks.require_clean(
      ["bundle", "exec", "flay", *CODE],
      "Total score (lower is better) = 0",
      "Flay: duplicated code found"
    )
  end

  desc("Fail on any method with a flog score above #{FLOG_LIMIT}")
  task(:flog) do
    report = Tasks.require_clean(
      ["bundle", "exec", "flog", "--all", "--methods-only", *CODE],
      "flog total",
      "flog failed"
    )
    complex = Tasks.too_complex(report)
    abort("flog: methods scoring above #{FLOG_LIMIT}: #{complex.join(", ")}") unless complex.empty?
  end

  desc("Audit gem dependencies for known vulnerabilities")
  task(:audit) { sh("bundle", "exec", "bundler-audit", "check", "--update") }

  desc("Fail on outdated dependencies that are not on the documented hold list")
  task(:outdated) { ruby("script/outdated.rb") }

  desc("Fail on dependencies below the OpenSSF Scorecard threshold that are not on the allowlist")
  task(:scorecard) { ruby("script/scorecard.rb") }

  desc("Run mutation testing on Ruby #{MUTANT_RUBY} (script/check mutant); every mutation must be killed")
  task(:mutant) { Bundler.with_unbundled_env { sh("script/check", "mutant") } }

  task(default: %i[spec rubocop suppressions typecheck yard reek flay flog audit])
end
