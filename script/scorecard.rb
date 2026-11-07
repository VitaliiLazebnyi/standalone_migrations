#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

# Fails when a dependency's OpenSSF Scorecard is below THRESHOLD, unless script/scorecard_allowlist.yml
# allows that dependency with a reason, and when an allowance is stale. It scores every gem of Gemfile.lock
# and every GitHub Action the workflows use, through the source repository each one names.
#
# actions/dependency-review-action can only warn on a single, global level for the dependencies a pull
# request adds; this check covers the whole bundle and allows exceptions one package at a time.

require "json"
require "net/http"
require "yaml"

# The level below which a dependency needs an allowance (the default of actions/dependency-review-action).
THRESHOLD = 3.0
ROOT = File.expand_path("..", __dir__)
ALLOWLIST = YAML.safe_load_file(File.join(ROOT, "script", "scorecard_allowlist.yml"), permitted_classes: [Date])
GITHUB_REPOSITORY = %r{\Ahttps?://github\.com/([\w.-]+/[\w.-]+?)(?:\.git)?(?:/.*)?\z}

def get_json(url)
  response = Net::HTTP.get_response(URI(url))
  return if response.is_a?(Net::HTTPNotFound)
  raise "GET #{url}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

# The GitHub repository a gem names as its source, or nil.
def gem_repository(name)
  metadata = get_json("https://rubygems.org/api/v1/gems/#{name}.json") || {}
  urls = metadata.values_at("source_code_uri", "homepage_uri")
  urls.filter_map { |url| url.to_s[GITHUB_REPOSITORY, 1] }.first
end

# The Scorecard score of a GitHub repository, or nil when Scorecard has not scored it.
def score(repository)
  get_json("https://api.securityscorecards.dev/projects/github.com/#{repository}")&.fetch("score")
end

lock = File.read(File.join(ROOT, "Gemfile.lock"))
gems = lock[/^GEM\n.*?\n\n/m].scan(/^    ([\w.-]+) \(/).flatten
gems.uniq!
workflows = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].map { |path| File.read(path) }
actions = workflows.flat_map { |text| text.scan(%r{uses: ([\w.-]+/[\w.-]+)(?:/[\w./-]+)?@}).flatten }
actions.uniq!

dependencies = gems.map { |name| ["gems", name, gem_repository(name)] } +
               actions.map { |repository| ["actions", repository, repository] }

problems = []
dependencies.each do |kind, name, repository|
  allowance = ALLOWLIST.dig(kind, name)
  value = repository && score(repository)
  label = "#{kind} #{name} (#{repository || "no GitHub repository"}): #{value || "not scored"}"
  if value && value < THRESHOLD
    allowance ? puts("allowed: #{label} — #{allowance.fetch("reason")}") : problems << "BELOW #{THRESHOLD}: #{label}"
  else
    puts label
    problems << "STALE ALLOWANCE (scores #{value || "nothing"} now): #{kind} #{name}" if allowance
  end
end

listed = ALLOWLIST.flat_map { |kind, entries| entries.keys.map { |name| [kind, name] } }
(listed - dependencies.map { |kind, name, _| [kind, name] }).each do |kind, name|
  problems << "STALE ALLOWANCE (no longer a dependency): #{kind} #{name}"
end

problems.each { |problem| warn problem }
exit(problems.empty? ? 0 : 1)
