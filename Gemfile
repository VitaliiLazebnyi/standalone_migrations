# frozen_string_literal: true

source "https://rubygems.org"

ruby file: ".ruby-version"

# ActiveRecord on its own, without the rest of Rails. This gives us the real
# migration engine (ActiveRecord::Migration), the schema dumper, and the
# migration context used by `bin/db`.
gem "activerecord", "~> 8.1", ">= 8.1.4"

# PostgreSQL adapter.
gem "pg", "~> 1.7"

# Runtime support for the Sorbet signatures in lib/ (`typed: strict`).
gem "sorbet-runtime", "~> 0.6"

# Everything below is tooling for the verification suite (`bundle exec rake`,
# see CONTRIBUTING.md). The Docker image skips these groups.
group :development, :test do
  gem "bundler-audit", "~> 0.9", require: false
  gem "flay", "~> 2.14", require: false
  gem "mutant-rspec", "~> 0.17", require: false
  gem "rake", "~> 13.4", require: false
  gem "reek", "~> 6.6", require: false
  gem "rspec", "~> 3.13", require: false
  gem "rubocop", "~> 1.92", require: false
  gem "rubocop-md", "~> 2.0", require: false
  gem "rubocop-performance", "~> 1.27", require: false
  gem "rubocop-rails", "~> 2.38", require: false
  gem "rubocop-rake", "~> 0.7", require: false
  gem "rubocop-rspec", "~> 3.10", require: false
  gem "rubocop-sorbet", "~> 0.17", require: false
  gem "rubocop-thread_safety", "~> 0.8", require: false
  gem "simplecov", "~> 1.3", require: false
  gem "sorbet", "~> 0.6", require: false
  gem "yard", "~> 0.9", require: false
  gem "yard-sorbet", "~> 0.9", require: false
end
