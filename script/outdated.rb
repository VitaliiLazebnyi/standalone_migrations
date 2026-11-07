#!/usr/bin/env ruby
# typed: strict
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
# * CI tools:        every `<TOOL>_VERSION:` that a workflow installs from a GitHub release, the hadolint
#                    image, and the Python packages of .github/requirements/*.txt

require "json"
require "net/http"
require "open3"
require "sorbet-runtime"
require "yaml"

# The dependency freshness check behind `rake outdated`.
module Outdated
  # The project directory.
  ROOT = T.let(File.expand_path("..", __dir__), String)
  # The text of every workflow, by path.
  WORKFLOWS = T.let(
    Dir.glob(File.join(ROOT, ".github", "workflows", "*.yml")).to_h { |path| [path, File.read(path)] },
    T::Hash[String, String]
  )
  # The GitHub repository of each tool a workflow installs from its release page.
  TOOL_REPOSITORIES = T.let(
    {
      "ACTIONLINT" => "rhysd/actionlint",
      "CHECKMAKE" => "checkmake/checkmake",
      "EDITORCONFIG_CHECKER" => "editorconfig-checker/editorconfig-checker",
      "GITLEAKS" => "gitleaks/gitleaks",
      "SHELLCHECK" => "koalaman/shellcheck",
      "SHFMT" => "mvdan/sh",
      "TRIVY" => "aquasecurity/trivy"
    }.freeze,
    T::Hash[String, String]
  )
  # The hold list: kind => name => { "newest" => version, "blocked_by" => [...] }.
  HOLDS = T.let(
    YAML.safe_load_file(File.join(ROOT, "script", "outdated_holds.yml")),
    T::Hash[String, T::Hash[String, T::Hash[String, Object]]]
  )
  public_constant :ROOT, :WORKFLOWS, :TOOL_REPOSITORIES, :HOLDS

  # A request to an index (rubygems.org, PyPI, Docker Hub, GitHub) or a command did not succeed.
  class RequestFailed < StandardError; end

  # One dependency: the version in use and the newest release.
  class Release
    extend T::Sig

    # @param dependency [Array(String, String)] its kind (gems, docker, ...) and name
    # @param current [String] the version in use
    # @param newest [String] the newest release
    sig { params(dependency: T::Array[String], current: String, newest: String).void }
    def initialize(dependency, current, newest)
      @kind = T.let(dependency.first.to_s, String)
      @name = T.let(dependency.last.to_s, String)
      @current = current
      @newest = newest
    end

    # @return [String] the kind of dependency: gems, bundler, ruby, rubygems, docker, actions, tools, python
    sig { returns(String) }
    attr_reader :kind

    # @return [String] the dependency's name
    sig { returns(String) }
    attr_reader :name

    # @return [String] the version in use
    sig { returns(String) }
    attr_reader :current

    # @return [String] the newest release
    sig { returns(String) }
    attr_reader :newest

    # @return [String] the kind and the name
    sig { returns(String) }
    def label
      "#{kind} #{name}"
    end

    # @return [Boolean] whether the version in use is the newest release
    sig { returns(T::Boolean) }
    def up_to_date?
      current == newest
    end

    # @return [String] the dependency and its update, e.g. "gems rake 13.3.0 -> 13.4.0"
    sig { returns(String) }
    def change
      "#{label} #{current} -> #{newest}"
    end
  end

  # The package indexes, release pages and tag lists that know the newest releases.
  module Index
    # A stable release tag: x.y or x.y.z, optionally prefixed with v.
    STABLE_TAG = /\Av?\d+\.\d+(\.\d+)?\z/
    public_constant :STABLE_TAG

    class << self
      extend T::Sig

      # The body of a successful GET request.
      #
      # @param url [String]
      # @return [String]
      sig { params(url: String).returns(String) }
      def get(url)
        response = Net::HTTP.get_response(URI(url))
        raise(RequestFailed, "GET #{url}: #{response.code}") unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s
      end

      # The newest version of a gem on rubygems.org.
      #
      # @param name [String]
      # @return [String]
      sig { params(name: String).returns(String) }
      def newest_gem(name)
        JSON.parse(get("https://rubygems.org/api/v1/versions/#{name}/latest.json")).fetch("version")
      end

      # The newest version of a Python package on PyPI.
      #
      # @param name [String]
      # @return [String]
      sig { params(name: String).returns(String) }
      def newest_python_package(name)
        JSON.parse(get("https://pypi.org/pypi/#{name}/json")).fetch("info").fetch("version")
      end

      # The newest release of a GitHub repository, as its tag spells it.
      #
      # @param tags [Hash{String => String}] see .tags
      # @return [String]
      sig { params(tags: T::Hash[String, String]).returns(String) }
      def newest_tag(tags)
        tags.keys.max_by { |tag| version(tag) }
            .to_s
      end

      # Stable (x.y.z or x.y) tags of a GitHub repository, mapped to the commit each one points at.
      #
      # @param repository [String] owner/name
      # @return [Hash{String => String}]
      sig { params(repository: String).returns(T::Hash[String, String]) }
      def tags(repository)
        output, status = Open3.capture2("git", "ls-remote", "--tags", "https://github.com/#{repository}")
        raise(RequestFailed, "git ls-remote #{repository} failed") unless status.success?

        output.lines.each_with_object({}) { |line, tags| add_tag(tags, line) }
      end

      # The newest Docker Hub tag of an official image matching +pattern+.
      #
      # @param image [String]
      # @param pattern [Regexp]
      # @return [String]
      sig { params(image: String, pattern: Regexp).returns(String) }
      def newest_image_tag(image, pattern)
        names = image_tags(image)
        # Compare the image version first, then the version of the base it is built on (e.g. alpine3.24).
        names.grep(pattern).max_by { |name| versions(name) }
             .to_s
      end

      # The newest Ruby release whose version starts with +prefix+.
      #
      # @param prefix [String] e.g. "3.3." or "" for the newest of all
      # @return [String]
      sig { params(prefix: String).returns(String) }
      def newest_ruby(prefix)
        releases = get("https://cache.ruby-lang.org/pub/ruby/index.txt").scan(/^ruby-(\d+\.\d+\.\d+)\t/).flatten
        releases.grep(/\A#{Regexp.escape(prefix)}/).max_by { |release| version(release.to_s) }
                .to_s
      end

      # A release tag as a comparable version.
      #
      # @param text [String] e.g. v1.2.3
      # @return [Gem::Version]
      sig { params(text: String).returns(Gem::Version) }
      def version(text)
        Gem::Version.new(text.delete_prefix("v"))
      end

      private

      # Record one line of `git ls-remote --tags`. `git ls-remote` sorts by name, so the peeled line of an
      # annotated tag (`v1.0^{}`, the commit it points at) follows the tag's own line and replaces it.
      sig { params(tags: T::Hash[String, String], line: String).void }
      def add_tag(tags, line)
        sha, ref = line.split
        tag = ref.to_s.delete_prefix("refs/tags/").delete_suffix("^{}")
        tags[tag] = sha.to_s if STABLE_TAG.match?(tag)
      end

      # The 100 most recently updated tags of an official Docker Hub image.
      sig { params(image: String).returns(T::Array[String]) }
      def image_tags(image)
        url = "https://hub.docker.com/v2/repositories/library/#{image}/tags?page_size=100&ordering=last_updated"
        JSON.parse(get(url)).fetch("results").map { |tag| tag.fetch("name").to_s }
      end

      # Every version number in a Docker tag, in order.
      sig { params(name: String).returns(T::Array[Gem::Version]) }
      def versions(name)
        name.scan(/\d+(?:\.\d+)*/).map { |number| version(number.to_s) }
      end
    end
  end

  # The versions this project pins, read from its files.
  module Pins
    class << self
      extend T::Sig

      # The Ruby of .ruby-version.
      #
      # @return [String]
      sig { returns(String) }
      def ruby
        File.read(File.join(ROOT, ".ruby-version")).strip
      end

      # The Ruby that mutation testing runs on.
      #
      # @return [String]
      sig { returns(String) }
      def mutant_ruby
        File.read(File.join(ROOT, "mutant.gemfile"))[/^ruby "([\d.]+)"/, 1].to_s
      end

      # Every match of +pattern+ in +files+, each as an array of its groups, without repetitions.
      #
      # @param pattern [Regexp]
      # @param files [Array<String>] paths
      # @return [Array<Array<String>>]
      sig { params(pattern: Regexp, files: T::Array[String]).returns(T::Array[T::Array[String]]) }
      def scan(pattern, files)
        matches = files.flat_map { |path| File.read(path).scan(pattern) }
        matches.uniq!
        matches.map { |match| Array(match).map(&:to_s) }
      end

      # Every match of +pattern+ in the workflows.
      #
      # @param pattern [Regexp]
      # @return [Array<Array<String>>]
      sig { params(pattern: Regexp).returns(T::Array[T::Array[String]]) }
      def in_workflows(pattern)
        scan(pattern, WORKFLOWS.keys)
      end

      # The ruby and postgres images of the Dockerfile, docker-compose.yml and the workflows.
      #
      # @return [Array<Array(String, String)>] image and tag
      sig { returns(T::Array[T::Array[String]]) }
      def images
        files = [File.join(ROOT, "Dockerfile"), File.join(ROOT, "docker-compose.yml"), *WORKFLOWS.keys]
        scan(/\b(ruby|postgres):([\w.-]+)@sha256:[0-9a-f]{64}/, files)
      end

      # The pinned Python packages of .github/requirements/*.txt.
      #
      # @return [Array<Array(String, String)>] package and version
      sig { returns(T::Array[T::Array[String]]) }
      def python_packages
        scan(/^([\w.-]+)==([\w.]+)/, Dir.glob(File.join(ROOT, ".github", "requirements", "*.txt")))
      end
    end
  end

  # The releases of every kind of dependency.
  module Releases
    # The tags that count as releases of each Docker image. The app image is Alpine-based. The database server
    # uses the Debian-based image: the Alpine one has no system locales, and PostgreSQL warns about that on every
    # start.
    IMAGE_TAGS = T.let(
      { "ruby" => /\A\d+\.\d+\.\d+-alpine\d+\.\d+\z/, "postgres" => /\A\d+\.\d+\z/ }.freeze,
      T::Hash[String, Regexp]
    )
    public_constant :IMAGE_TAGS

    class << self
      extend T::Sig

      # The outdated gems of the main bundle, as `bundle outdated` reports them.
      #
      # @return [Array<Release>]
      sig { returns(T::Array[Release]) }
      def gems
        bundle_outdated.scan(/^(\S+) \(newest ([^,\s]+), installed ([^,)\s]+)/).map do |name, newest, installed|
          Release.new(["gems", name.to_s], installed.to_s, newest.to_s)
        end
      end

      # Bundler, RubyGems and Ruby.
      #
      # @return [Array<Release>]
      sig { returns(T::Array[Release]) }
      def platform
        [
          bundler,
          Release.new(%w[ruby .ruby-version], Pins.ruby, Index.newest_ruby("")),
          Release.new(["ruby", "mutant.gemfile (newest 3.3)"], Pins.mutant_ruby, Index.newest_ruby("3.3.")),
          *rubygems
        ]
      end

      # The RubyGems the Dockerfile installs, and the one running this check.
      #
      # @return [Array<Release>]
      sig { returns(T::Array[Release]) }
      def rubygems
        newest = Index.newest_gem("rubygems-update")
        pinned = Pins.scan(/gem update --system ([\d.]+)/, [File.join(ROOT, "Dockerfile")]).flatten
        [
          *pinned.map { |version| Release.new(%w[rubygems Dockerfile], version, newest) },
          Release.new(%w[rubygems running], Gem::VERSION, newest)
        ]
      end

      # The ruby and postgres images.
      #
      # @return [Array<Release>]
      sig { returns(T::Array[Release]) }
      def images
        Pins.images.map do |image, tag|
          name = image.to_s
          Release.new(["docker", name], tag.to_s, Index.newest_image_tag(name, IMAGE_TAGS.fetch(name)))
        end
      end

      # Every `uses: owner/repo@<sha> # <tag>`.
      #
      # @param newest [Hash{String => String}] the newest tag of each action's repository
      # @return [Array<Release>]
      sig { params(newest: T::Hash[String, String]).returns(T::Array[Release]) }
      def actions(newest)
        newest.map { |repository, tag| Release.new(["actions", repository], Actions.tag(repository), tag) }
      end

      # The tools the workflows install from GitHub releases, the hadolint image and the Python packages.
      #
      # @return [Array<Release>]
      sig { returns(T::Array[Release]) }
      def tools
        hadolint = Pins.in_workflows(%r{hadolint/hadolint:v([\d.]+)@sha256:[0-9a-f]{64}}).flatten
        [
          *Tools.releases,
          *hadolint.map { |pinned| tool("hadolint", pinned, "hadolint/hadolint") },
          *Pins.python_packages.map { |name, pinned| python_package(name.to_s, pinned.to_s) }
        ]
      end

      # A release of the GitHub repository +repository+.
      #
      # @param name [String]
      # @param pinned [String]
      # @param repository [String]
      # @return [Release]
      sig { params(name: String, pinned: String, repository: String).returns(Release) }
      def tool(name, pinned, repository)
        Release.new(["tools", name], pinned, Index.newest_tag(Index.tags(repository)).delete_prefix("v"))
      end

      private

      # The parseable output of `bundle outdated` for the main bundle.
      sig { returns(String) }
      def bundle_outdated
        # `bundle outdated` refuses to run in deployment mode, which setup-ruby's bundler-cache turns on.
        environment = { "BUNDLE_DEPLOYMENT" => "false", "BUNDLE_FROZEN" => "false" }
        output, status = Open3.capture2e(environment, "bundle", "outdated", "--parseable", chdir: ROOT)
        # It exits 1 when it finds outdated gems; anything else means it did not run.
        raise(RequestFailed, "bundle outdated failed:\n#{output}") unless status.success? || status.exitstatus == 1

        output
      end

      # The Bundler that locked Gemfile.lock.
      sig { returns(Release) }
      def bundler
        locked = File.read(File.join(ROOT, "Gemfile.lock"))[/^BUNDLED WITH\n\s+(\S+)/, 1].to_s
        Release.new(%w[bundler bundler], locked, Index.newest_gem("bundler"))
      end

      sig { params(name: String, pinned: String).returns(Release) }
      def python_package(name, pinned)
        Release.new(["python", name], pinned, Index.newest_python_package(name))
      end
    end
  end

  # The GitHub Actions of the workflows.
  module Actions
    # `uses: owner/repo[/path]@<sha> # <tag>`
    USES = %r{uses: ([\w.-]+/[\w.-]+)(?:/[\w./-]+)?@([0-9a-f]{40}) +# (\S+)}
    public_constant :USES

    class << self
      extend T::Sig

      # The pinned actions: repository => [sha, tag].
      #
      # @return [Hash{String => Array(String, String)}]
      sig { returns(T::Hash[String, T::Array[String]]) }
      def pins
        Pins.in_workflows(USES).to_h { |repository, sha, tag| [repository.to_s, [sha.to_s, tag.to_s]] }
      end

      # The tag an action is pinned to.
      #
      # @param repository [String]
      # @return [String]
      sig { params(repository: String).returns(String) }
      def tag(repository)
        pins.fetch(repository).last.to_s
      end

      # An action whose SHA is not the commit of the tag its comment names.
      #
      # @param tags [Hash{String => Hash{String => String}}] the tags of each action's repository
      # @return [Array<String>]
      sig { params(tags: T::Hash[String, T::Hash[String, String]]).returns(T::Array[String]) }
      def mismatches(tags)
        pins.filter_map do |repository, (sha, tag)|
          commit = tags.fetch(repository)[tag.to_s]
          "MISMATCH: #{repository}@#{sha} is not #{tag} (#{commit})" unless commit == sha
        end
      end
    end
  end

  # The CI tools that the workflows install from GitHub releases (`<TOOL>_VERSION:`).
  module Tools
    class << self
      extend T::Sig

      # The pinned tools: name => version.
      #
      # @return [Hash{String => String}]
      sig { returns(T::Hash[String, String]) }
      def pins
        Pins.in_workflows(/^\s+([A-Z0-9_]+)_VERSION: "?([\w.]+)"?/).to_h { |tool, pinned| [tool.to_s, pinned.to_s] }
      end

      # A release for each known tool.
      #
      # @return [Array<Release>]
      sig { returns(T::Array[Release]) }
      def releases
        known = pins.select { |tool, _| TOOL_REPOSITORIES.key?(tool) }
        known.map { |tool, pinned| Releases.tool(tool.downcase, pinned, TOOL_REPOSITORIES.fetch(tool)) }
      end

      # A tool whose repository this script does not know.
      #
      # @return [Array<String>]
      sig { returns(T::Array[String]) }
      def unknown
        (pins.keys - TOOL_REPOSITORIES.keys).map { |tool| "UNKNOWN TOOL: #{tool}_VERSION" }
      end
    end
  end

  # The versions that must agree with each other.
  module Consistency
    # `ruby-version: x.y.z` in a workflow.
    RUBY_PIN = /ruby-version: "?(\d[\d.]*)"?/
    public_constant :RUBY_PIN

    class << self
      extend T::Sig

      # A workflow that pins a Ruby other than .ruby-version's or mutant.gemfile's.
      #
      # @return [Array<String>]
      sig { returns(T::Array[String]) }
      def workflow_rubies
        allowed = [Pins.ruby, Pins.mutant_ruby]
        WORKFLOWS.flat_map { |path, text| foreign_rubies(path, text, allowed) }
      end

      # Every inconsistency.
      #
      # @return [Array<String>]
      sig { returns(T::Array[String]) }
      def all
        workflow_rubies + images
      end

      # The Dockerfile's Ruby is .ruby-version's, and every postgres image is the same.
      #
      # @return [Array<String>]
      sig { returns(T::Array[String]) }
      def images
        [docker_ruby(tags("ruby").first.to_s), postgres(tags("postgres"))].compact
      end

      private

      sig { params(path: String, text: String, allowed: T::Array[String]).returns(T::Array[String]) }
      def foreign_rubies(path, text, allowed)
        rubies = text.scan(RUBY_PIN).map { |(ruby)| ruby.to_s } - allowed
        rubies.uniq!
        rubies.map { |ruby| "INCONSISTENT: #{File.basename(path)} uses Ruby #{ruby}" }
      end

      # The tags of +image+ in the Dockerfile, docker-compose.yml and the workflows.
      sig { params(image: String).returns(T::Array[String]) }
      def tags(image)
        Pins.images.group_by(&:first).fetch(image, []).map { |(_, tag)| tag.to_s }
      end

      sig { params(tag: String).returns(T.nilable(String)) }
      def docker_ruby(tag)
        ruby = Pins.ruby
        "INCONSISTENT: Dockerfile uses ruby:#{tag}, .ruby-version is #{ruby}" unless tag.start_with?("#{ruby}-")
      end

      sig { params(tags: T::Array[String]).returns(T.nilable(String)) }
      def postgres(tags)
        "INCONSISTENT: postgres images #{tags.join(", ")}" if tags.size > 1
      end
    end
  end

  # Compares each release with the hold list.
  module Verdict
    class << self
      extend T::Sig

      # The problem with +release+, or nil; prints the releases that are on hold.
      #
      # @param release [Release]
      # @return [String, nil]
      sig { params(release: Release).returns(T.nilable(String)) }
      def problem(release)
        return stale(release) if release.up_to_date?

        change = release.change
        return "OUTDATED: #{change}" unless held?(release)

        puts("on hold: #{change}")
      end

      # A gem on the hold list that `bundle outdated` no longer reports.
      #
      # @param gems [Array<Release>] the outdated gems
      # @return [Array<String>]
      sig { params(gems: T::Array[Release]).returns(T::Array[String]) }
      def stale_gem_holds(gems)
        (HOLDS.fetch("gems", {}).keys - gems.map(&:name)).map { |name| "STALE HOLD (no longer outdated): gems #{name}" }
      end

      private

      sig { params(release: Release).returns(T.nilable(String)) }
      def stale(release)
        "STALE HOLD (no longer outdated): #{release.label}" if hold(release)
      end

      sig { params(release: Release).returns(T::Boolean) }
      def held?(release)
        hold(release)&.fetch("newest") == release.newest
      end

      sig { params(release: Release).returns(T.nilable(T::Hash[String, Object])) }
      def hold(release)
        HOLDS.fetch(release.kind, {})[release.name]
      end
    end
  end

  class << self
    extend T::Sig

    # Run every check and print the result.
    #
    # @return [Integer] the exit status: 0 when nothing is outdated
    sig { returns(Integer) }
    def run
      problems = self.problems
      problems.each { |problem| warn(problem) }
      puts("Everything is at its newest release (or on the documented hold list).") if problems.empty?
      problems.size.clamp(0, 1)
    end

    # Everything that is outdated, inconsistent or stale.
    #
    # @return [Array<String>]
    sig { returns(T::Array[String]) }
    def problems
      tags = Actions.pins.keys.to_h { |repository| [repository, Index.tags(repository)] }
      gems = Releases.gems
      verdicts(gems, tags) + other_problems(gems, Actions.mismatches(tags))
    end

    private

    # The problem of each release, if any.
    sig { params(gems: T::Array[Release], tags: T::Hash[String, T::Hash[String, String]]).returns(T::Array[String]) }
    def verdicts(gems, tags)
      newest = tags.transform_values { |tag_list| Index.newest_tag(tag_list) }
      releases(gems, newest).filter_map { |release| Verdict.problem(release) }
    end

    # Every release: the outdated gems, and the newest tag of each action.
    sig { params(gems: T::Array[Release], newest: T::Hash[String, String]).returns(T::Array[Release]) }
    def releases(gems, newest)
      gems + Releases.platform + Releases.images + Releases.actions(newest) + Releases.tools
    end

    # The stale gem holds, the action mismatches, the unknown tools and the inconsistencies.
    sig { params(gems: T::Array[Release], mismatches: T::Array[String]).returns(T::Array[String]) }
    def other_problems(gems, mismatches)
      Verdict.stale_gem_holds(gems) + mismatches + Tools.unknown + Consistency.all
    end
  end
end

exit(Outdated.run)
