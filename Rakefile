# frozen_string_literal: true

require "rspec/core/rake_task"

# Output of `yard stats` when every public API object is documented.
FULLY_DOCUMENTED = "100.00% documented"
# The Ruby the mutation-testing bundle runs on (see mutant.gemfile).
MUTANT_RUBY = File.read(File.join(__dir__, "mutant.gemfile"))[/^ruby "([\d.]+)"/, 1]

RSpec::Core::RakeTask.new(:spec)

desc "Run RuboCop"
task :rubocop do
  sh "bundle exec rubocop"
end

desc "Fail on inline suppressions of any linter, scanner, type checker, warning or test"
task :suppressions do
  sh "script/forbidden_suppressions.sh"
end

desc "Generate the gem RBIs with Tapioca, then run the Sorbet type checker"
task :typecheck do
  # Tapioca runs from its own bundle. Under `bundle exec rake` the environment (RUBYOPT=-rbundler/setup,
  # BUNDLE_GEMFILE) belongs to the main bundle, so the nested commands run in an unbundled environment.
  Bundler.with_unbundled_env do
    sh "env BUNDLE_GEMFILE=typecheck.gemfile bundle install --quiet"
    sh "env BUNDLE_GEMFILE=typecheck.gemfile bundle exec tapioca gem --all"
  end
  # Tapioca already merges the RBIs that gems ship themselves into the generated ones; srb must not load
  # them a second time.
  sh "env SRB_SKIP_GEM_RBIS=1 bundle exec srb tc"
end

desc "Fail unless every public API object is documented"
task :yard do
  output = IO.popen(%w[bundle exec yard stats --list-undoc], err: %i[child out], &:read)
  puts output
  fully_documented = output.include?(FULLY_DOCUMENTED)
  abort "YARD: undocumented API objects found" unless fully_documented
  abort "YARD: warnings" if output.include?("[warn]")
end

desc "Fail on any code smell (default Reek configuration, no exclusions)"
task :reek do
  sh "bundle exec reek lib bin"
end

desc "Fail on any structural duplication (Flay's default mass)"
task :flay do
  output = IO.popen(%w[bundle exec flay lib bin], &:read)
  puts output
  abort "Flay: duplicated code found" unless output.start_with?("Total score (lower is better) = 0")
end

desc "Audit gem dependencies for known vulnerabilities"
task :audit do
  sh "bundle exec bundler-audit check --update"
end

desc "Fail on outdated dependencies that are not on the documented hold list"
task :outdated do
  ruby "script/outdated.rb"
end

desc "Run mutation testing on Ruby #{MUTANT_RUBY}; every mutation must be killed (see .mutant.yml)"
task :mutant do
  abort "Mutation testing runs on Ruby #{MUTANT_RUBY} (see mutant.gemfile), not #{RUBY_VERSION}" \
    unless RUBY_VERSION == MUTANT_RUBY

  # Start from the versions of Gemfile.lock, so that mutation testing runs the locked gems.
  cp "Gemfile.lock", "mutant.gemfile.lock"
  Bundler.with_unbundled_env do
    sh "env BUNDLE_GEMFILE=mutant.gemfile bundle install --quiet"
    sh "env BUNDLE_GEMFILE=mutant.gemfile bundle exec mutant run"
  end
end

task default: %i[spec rubocop suppressions typecheck yard reek flay audit]
