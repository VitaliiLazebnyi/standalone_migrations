# frozen_string_literal: true

source "https://rubygems.org"

ruby file: ".ruby-version"

# ActiveRecord on its own, without the rest of Rails. This gives us the real
# migration engine (ActiveRecord::Migration), the schema dumper, and the
# migration context used by `bin/db`.
gem "activerecord", "~> 8.1", ">= 8.1.4.1"

# PostgreSQL adapter.
gem "pg", "~> 1.7"

# Runtime support for the Sorbet signatures in lib/ (`typed: strict`).
gem "sorbet-runtime", "~> 0.6"

# Everything below is tooling for the verification suite (`bundle exec rake`,
# see CONTRIBUTING.md). The Docker image skips these groups.
group :development, :test do
  # Audits Gemfile.lock against the Ruby Advisory Database (`rake audit`).
  gem "bundler-audit", "~> 0.9", require: false
  # Structural duplication (`rake flay`).
  gem "flay", "~> 2.14", require: false
  # Method complexity (`rake flog`).
  gem "flog", "~> 4.9", require: false
  # Mutation testing with the RSpec suite (`rake mutant`, .mutant.yml).
  gem "mutant-rspec", "~> 0.17", require: false
  # Runs the verification tasks (Rakefile).
  gem "rake", "~> 13.4", require: false
  # Code smells (`rake reek`).
  gem "reek", "~> 6.6", require: false
  # The test suite (spec/).
  gem "rspec", "~> 3.13", require: false
  # The linter and formatter (`rake rubocop`, .rubocop.yml), and its plugins below.
  gem "rubocop", "~> 1.92", require: false
  # Lints the Ruby code blocks of the Markdown files.
  gem "rubocop-md", "~> 3.0", require: false
  # Performance cops.
  gem "rubocop-performance", "~> 1.27", require: false
  # ActiveRecord and migration cops.
  gem "rubocop-rails", "~> 2.38", require: false
  # Rakefile cops.
  gem "rubocop-rake", "~> 0.7", require: false
  # RSpec cops.
  gem "rubocop-rspec", "~> 3.10", require: false
  # Sorbet sigil and signature cops.
  gem "rubocop-sorbet", "~> 0.17", require: false
  # Thread-safety cops.
  gem "rubocop-thread_safety", "~> 0.8", require: false
  # The 100% line and branch coverage gate (spec/spec_helper.rb).
  gem "simplecov", "~> 1.3", require: false
  # The Sorbet type checker (`rake typecheck`).
  gem "sorbet", "~> 0.6", require: false
  # The API documentation and its 100% coverage gate (`rake yard`).
  gem "yard", "~> 0.9", require: false
  # Lets YARD read the types of the Sorbet signatures.
  gem "yard-sorbet", "~> 0.9", require: false
end
