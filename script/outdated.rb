#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

# Fails when a dependency is not at its newest release and is not on the documented hold list
# (script/outdated_holds.yml), or when a listed hold is no longer outdated. It checks:
#
# * gems:            `bundle outdated` of the main bundle
# * Bundler:         BUNDLED WITH in Gemfile.lock
# * RubyGems:        `gem update --system` in the Dockerfile, and the RubyGems running the check
# * Ruby:            .ruby-version (newest stable release) and mutant.gemfile (newest 3.3 release)
# * Docker images:   the ruby and postgres tags in Dockerfile, docker-compose.yml and the workflows
# * GitHub Actions:  every `uses: owner/repo@<sha> # <tag>` (newest tag, and the SHA is that tag's commit)
# * CI tools:        every `<TOOL>_VERSION:` that a workflow installs from a GitHub release

require "json"
require "net/http"
require "open3"
require "yaml"

ROOT = File.expand_path("..", __dir__)
HOLDS = YAML.safe_load_file(File.join(ROOT, "script", "outdated_holds.yml"))
WORKFLOWS = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].to_h { |path| [path, File.read(path)] }
# The GitHub repository of each tool a workflow installs from its release page.
TOOL_REPOSITORIES = {
  "ACTIONLINT" => "rhysd/actionlint", "CHECKMAKE" => "checkmake/checkmake", "GITLEAKS" => "gitleaks/gitleaks",
  "MARKDOWNLINT_CLI2" => "DavidAnson/markdownlint-cli2",
  "SHELLCHECK" => "koalaman/shellcheck", "TRIVY" => "aquasecurity/trivy", "TYPOS" => "crate-ci/typos"
}.freeze

problems = []
report = lambda do |kind, name, current, newest|
  hold = HOLDS.dig(kind, name)
  if current == newest
    problems << "STALE HOLD (no longer outdated): #{kind} #{name}" if hold
  elsif hold && hold["newest"] == newest
    puts "on hold: #{kind} #{name} #{current} -> #{newest}"
  else
    problems << "OUTDATED: #{kind} #{name} #{current} -> #{newest}"
  end
end

def get(url)
  response = Net::HTTP.get_response(URI(url))
  raise "GET #{url}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  response.body
end

def version(text) = Gem::Version.new(text.delete_prefix("v"))

# Stable (x.y.z or x.y) tags of a GitHub repository, mapped to the commit each one points at.
def github_tags(repository)
  output, status = Open3.capture2("git", "ls-remote", "--tags", "https://github.com/#{repository}")
  raise "git ls-remote #{repository} failed" unless status.success?

  output.lines.each_with_object({}) do |line, tags|
    sha, ref = line.split
    tag = ref.delete_prefix("refs/tags/")
    peeled = tag.delete_suffix("^{}")
    next unless /\Av?\d+\.\d+(\.\d+)?\z/.match?(peeled)

    tags[peeled] = sha if peeled != tag || !tags.key?(peeled)
  end
end

def newest_tag(tags) = tags.keys.max_by { |tag| version(tag) }

# Docker Hub tags of an official image matching +pattern+ (newest first by version).
def docker_tags(image, pattern)
  url = "https://hub.docker.com/v2/repositories/library/#{image}/tags?page_size=100&ordering=last_updated"
  names = JSON.parse(get(url)).fetch("results").map { |tag| tag.fetch("name") }
  names.grep(pattern).max_by { |name| version(name[/\A[\d.]+/]) }
end

# --- gems -------------------------------------------------------------------------------------------------
output, = Open3.capture2e("bundle", "outdated", "--parseable", chdir: ROOT)
outdated = output.scan(/^(\S+) \(newest ([^,\s]+), installed ([^,)\s]+)/)
outdated.each { |name, newest, installed| report.call("gems", name, installed, newest) }
(HOLDS.fetch("gems", {}).keys - outdated.map(&:first)).each do |name|
  problems << "STALE HOLD (no longer outdated): gems #{name}"
end

# --- Bundler ----------------------------------------------------------------------------------------------
bundled = File.read(File.join(ROOT, "Gemfile.lock"))[/^BUNDLED WITH\n\s+(\S+)/, 1]
report.call("bundler", "bundler", bundled, JSON.parse(get("https://rubygems.org/api/v1/versions/bundler/latest.json"))
  .fetch("version"))

# --- RubyGems: the version the Dockerfile installs, and the one running this check ---------------------------
newest_rubygems = JSON.parse(get("https://rubygems.org/api/v1/versions/rubygems-update/latest.json")).fetch("version")
pinned_rubygems = File.read(File.join(ROOT, "Dockerfile")).scan(/gem update --system ([\d.]+)/).flatten
pinned_rubygems.uniq!
pinned_rubygems.each do |pinned|
  report.call("rubygems", "Dockerfile", pinned, newest_rubygems)
end
report.call("rubygems", "running", Gem::VERSION, newest_rubygems)

# --- Ruby -------------------------------------------------------------------------------------------------
releases = get("https://cache.ruby-lang.org/pub/ruby/index.txt").scan(/^ruby-(\d+\.\d+\.\d+)\t/).flatten
releases.uniq!
newest_ruby = ->(prefix) { releases.grep(/\A#{Regexp.escape(prefix)}/).max_by { |release| version(release) } }
ruby_version = File.read(File.join(ROOT, ".ruby-version")).strip
report.call("ruby", ".ruby-version", ruby_version, newest_ruby.call(""))
mutant_ruby = File.read(File.join(ROOT, "mutant.gemfile"))[/^ruby "([\d.]+)"/, 1]
report.call("ruby", "mutant.gemfile (newest 3.3)", mutant_ruby, newest_ruby.call("3.3."))
WORKFLOWS.each do |path, text|
  pins = text.scan(/ruby-version: "?(\d[\d.]*)"?/).flatten
  pins.uniq!
  pins.each do |pinned|
    next if [ruby_version, mutant_ruby].include?(pinned)

    problems << "INCONSISTENT: #{File.basename(path)} uses Ruby #{pinned}"
  end
end

# --- Docker images ----------------------------------------------------------------------------------------
image_files = [File.join(ROOT, "Dockerfile"), File.join(ROOT, "docker-compose.yml"), *WORKFLOWS.keys]
images = image_files.flat_map { |path| File.read(path).scan(/\b(ruby|postgres):([\w.-]+)@sha256:[0-9a-f]{64}/) }
images.uniq!
images.each do |image, tag|
  pattern = image == "ruby" ? /\A\d+\.\d+\.\d+-alpine\d+\.\d+\z/ : /\A\d+\.\d+-alpine\d+\.\d+\z/
  report.call("docker", image, tag, docker_tags(image, pattern))
end
ruby_tag = images.find { |image, _| image == "ruby" }&.last.to_s
problems << "INCONSISTENT: Dockerfile uses ruby:#{ruby_tag}, .ruby-version is #{ruby_version}" \
  unless ruby_tag.start_with?("#{ruby_version}-")
postgres_tags = images.filter_map { |image, tag| tag if image == "postgres" }
problems << "INCONSISTENT: postgres images #{postgres_tags.join(", ")}" if postgres_tags.size > 1

# --- GitHub Actions and CI tools --------------------------------------------------------------------------
actions = WORKFLOWS.values.flat_map do |text|
  text.scan(%r{uses: ([\w.-]+/[\w.-]+)(?:/[\w./-]+)?@([0-9a-f]{40}) # (\S+)})
end
actions.uniq!
actions.each do |repository, sha, tag|
  tags = github_tags(repository)
  report.call("actions", repository, tag, newest_tag(tags))
  problems << "MISMATCH: #{repository}@#{sha} is not #{tag} (#{tags[tag]})" unless tags[tag] == sha
end
tools = WORKFLOWS.values.flat_map { |text| text.scan(/^\s+([A-Z0-9_]+)_VERSION: "?([\w.]+)"?/) }
tools.uniq!
tools.each do |tool, pinned|
  repository = TOOL_REPOSITORIES.fetch(tool) { problems << "UNKNOWN TOOL: #{tool}_VERSION" and next }
  report.call("tools", tool.downcase, pinned, newest_tag(github_tags(repository)).delete_prefix("v"))
end

# Tools that a workflow runs from their official image (pinned by digest) rather than a release download.
hadolint = WORKFLOWS.values.join.scan(%r{hadolint/hadolint:v([\d.]+)@sha256:[0-9a-f]{64}}).flatten
hadolint.uniq!
hadolint.each do |pinned|
  report.call("tools", "hadolint", pinned, newest_tag(github_tags("hadolint/hadolint")).delete_prefix("v"))
end

problems.each { |problem| warn problem }
puts "Everything is at its newest release (or on the documented hold list)." if problems.empty?
exit(problems.empty? ? 0 : 1)
