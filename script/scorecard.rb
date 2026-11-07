#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Fails when a dependency's OpenSSF Scorecard is below THRESHOLD, unless script/scorecard_allowlist.yml
# allows that dependency with a reason, and when an allowance is stale. It scores every gem of Gemfile.lock
# and every GitHub Action the workflows use, through the source repository each one names.
#
# actions/dependency-review-action can only warn on a single, global level for the dependencies a pull
# request adds; this check covers the whole bundle and allows exceptions one package at a time.

require "date"
require "json"
require "net/http"
require "sorbet-runtime"
require "yaml"

# The dependency Scorecard check behind `rake scorecard`.
module Scorecard
  # The level below which a dependency needs an allowance (the default of actions/dependency-review-action).
  THRESHOLD = 3.0
  # The project directory.
  ROOT = T.let(File.expand_path("..", __dir__), String)
  # The allowances: kind => name => { "reviewed_score", "reviewed_on", "reason" }.
  ALLOWLIST = T.let(
    YAML.safe_load_file(File.join(ROOT, "script", "scorecard_allowlist.yml"), permitted_classes: [Date]),
    T::Hash[String, T::Hash[String, T::Hash[String, Object]]]
  )
  public_constant :THRESHOLD, :ROOT, :ALLOWLIST

  # A request to rubygems.org or the Scorecard API did not succeed.
  class RequestFailed < StandardError; end

  # One dependency: its kind (gems or actions), its name and its GitHub repository (when it names one).
  class Dependency
    extend T::Sig

    # @param key [Array(String, String)] the kind (gems or actions) and the name
    # @param repository [String, nil] owner/name on GitHub
    sig { params(key: T::Array[String], repository: T.nilable(String)).void }
    def initialize(key, repository)
      @key = key
      @repository = repository
      @score = T.let(repository&.then { |name| Index.score(name) }, T.nilable(Float))
    end

    # @return [Array(String, String)] the kind (gems or actions) and the name
    sig { returns(T::Array[String]) }
    attr_reader :key

    # @return [String, nil] owner/name on GitHub
    sig { returns(T.nilable(String)) }
    attr_reader :repository

    # @return [String] the kind and the name
    sig { returns(String) }
    def label
      key.join(" ")
    end

    # @return [String] the kind, the name, the repository and the score
    sig { returns(String) }
    def describe
      "#{label} (#{repository || "no GitHub repository"}): #{score || "not scored"}"
    end

    # @return [Hash{String => Object}, nil] the allowance of this dependency
    sig { returns(T.nilable(T::Hash[String, Object])) }
    def allowance
      ALLOWLIST.fetch(key.first.to_s, {})[key.last.to_s]
    end

    # @return [Float, nil] the Scorecard score of its repository, or nil when it has none
    sig { returns(T.nilable(Float)) }
    attr_reader :score
  end

  # rubygems.org and the Scorecard API.
  module Index
    # The owner/name part of a GitHub repository URL.
    GITHUB_REPOSITORY = %r{\Ahttps?://github\.com/([\w.-]+/[\w.-]+?)(?:\.git)?(?:/.*)?\z}
    public_constant :GITHUB_REPOSITORY

    class << self
      extend T::Sig

      # The parsed JSON of a GET request, or nil when there is nothing at +url+.
      #
      # @param url [String]
      # @return [Hash{String => Object}, nil]
      sig { params(url: String).returns(T.nilable(T::Hash[String, Object])) }
      def get_json(url)
        body(Net::HTTP.get_response(URI(url)), url)&.then { |text| JSON.parse(text) }
      end

      # The GitHub repository a gem names as its source, or nil.
      #
      # @param name [String]
      # @return [String, nil]
      sig { params(name: String).returns(T.nilable(String)) }
      def gem_repository(name)
        metadata = get_json("https://rubygems.org/api/v1/gems/#{name}.json") || {}
        urls = metadata.values_at("source_code_uri", "homepage_uri")
        urls.filter_map { |url| url.to_s[GITHUB_REPOSITORY, 1] }
            .first
      end

      # The Scorecard score of a GitHub repository, or nil when Scorecard has not scored it.
      #
      # @param repository [String] owner/name
      # @return [Float, nil]
      sig { params(repository: String).returns(T.nilable(Float)) }
      def score(repository)
        result = get_json("https://api.securityscorecards.dev/projects/github.com/#{repository}")
        Float(result.fetch("score").to_s) if result
      end

      private

      # The body of +response+; nil when it is a 404.
      sig { params(response: Net::HTTPResponse, url: String).returns(T.nilable(String)) }
      def body(response, url)
        return if response.is_a?(Net::HTTPNotFound)
        raise(RequestFailed, "GET #{url}: #{response.code}") unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s
      end
    end
  end

  # The dependencies of the project.
  module Dependencies
    class << self
      extend T::Sig

      # Every gem of Gemfile.lock and every GitHub Action of the workflows.
      #
      # @return [Array<Dependency>]
      sig { returns(T::Array[Dependency]) }
      def all
        gems + actions
      end

      private

      sig { returns(T::Array[Dependency]) }
      def gems
        names = matches(File.read(File.join(ROOT, "Gemfile.lock"))[/^GEM\n.*?\n\n/m].to_s, /^    ([\w.-]+) \(/)
        names.map { |name| Dependency.new(["gems", name], Index.gem_repository(name)) }
      end

      sig { returns(T::Array[Dependency]) }
      def actions
        workflows = Dir.glob(File.join(ROOT, ".github", "workflows", "*.yml")).map { |path| File.read(path) }
        repositories = matches(workflows.join("\n"), %r{uses: ([\w.-]+/[\w.-]+)(?:/[\w./-]+)?@})
        repositories.map { |name| Dependency.new(["actions", name], name) }
      end

      # The first group of every match of +pattern+ in +text+, without repetitions.
      sig { params(text: String, pattern: Regexp).returns(T::Array[String]) }
      def matches(text, pattern)
        found = text.scan(pattern).map { |(group)| group.to_s }
        found.uniq!
        found
      end
    end
  end

  class << self
    extend T::Sig

    # Score every dependency and print the result.
    #
    # @return [Integer] the exit status: 0 when every dependency passes
    sig { returns(Integer) }
    def run
      problems = self.problems
      problems.each { |problem| warn(problem) }
      problems.size.clamp(0, 1)
    end

    # Every dependency below the threshold, and every stale allowance.
    #
    # @return [Array<String>]
    sig { returns(T::Array[String]) }
    def problems
      dependencies = Dependencies.all
      dependencies.filter_map { |dependency| problem(dependency) } + stale(dependencies)
    end

    # The problem with +dependency+, or nil; prints its score.
    #
    # @param dependency [Dependency]
    # @return [String, nil]
    sig { params(dependency: Dependency).returns(T.nilable(String)) }
    def problem(dependency)
      value = dependency.score
      label = dependency.describe
      return low(dependency, label) if value && value < THRESHOLD

      puts(label)
      stale_allowance(dependency)
    end

    # An allowance for a package that is no longer a dependency.
    #
    # @param dependencies [Array<Dependency>]
    # @return [Array<String>]
    sig { params(dependencies: T::Array[Dependency]).returns(T::Array[String]) }
    def stale(dependencies)
      listed = ALLOWLIST.flat_map { |kind, entries| [kind].product(entries.keys) }
      (listed - dependencies.map(&:key)).map { |key| "STALE ALLOWANCE (no longer a dependency): #{key.join(" ")}" }
    end

    private

    # The allowance of a dependency that is not below the threshold (any more).
    sig { params(dependency: Dependency).returns(T.nilable(String)) }
    def stale_allowance(dependency)
      "STALE ALLOWANCE (scores #{dependency.score || "nothing"} now): #{dependency.label}" if dependency.allowance
    end

    # A dependency below the threshold: allowed (printed with its reason) or a problem.
    sig { params(dependency: Dependency, label: String).returns(T.nilable(String)) }
    def low(dependency, label)
      allowance = dependency.allowance
      return "BELOW #{THRESHOLD}: #{label}" unless allowance

      puts("allowed: #{label} - #{allowance.fetch("reason")}")
    end
  end
end

exit(Scorecard.run)
