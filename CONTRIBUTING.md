# Contributing

Bug reports and pull requests are welcome on GitHub at
<https://github.com/VitaliiLazebnyi/standalone_migrations>.

## Getting started

The project develops on the Ruby in `.ruby-version` (the Docker image uses the
same release). The test suite needs a PostgreSQL server whose user may create
databases; the one from `docker-compose.yml` works:

```bash
bundle install
git config core.hooksPath .githooks   # optional: run the fast gates before every commit
docker compose up -d db               # PostgreSQL on 127.0.0.1:5433
export DATABASE_HOST=127.0.0.1 DATABASE_PORT=5433
```

`make test` does the last two steps and runs `bundle exec rake`. Every test
process creates (and drops) a database of its own, `standalone_migrations_test_<pid>`,
next to the maintenance database `postgres`.

## Before opening a pull request

Run the checks. Every one is enforced in CI and fails the build;
`script/check` runs all of them locally, and `script/check <check>...` the
named ones (`script/check --list` lists them). The CI jobs call the same
script, so a check passes locally exactly when it passes in CI:

```bash
script/check                  # everything
script/check ruby shellcheck  # the Ruby gates and ShellCheck only
```

The `ruby` check is `bundle exec rake`, which runs, in order:

| Task | Gate |
| --- | --- |
| `rake spec` | RSpec against PostgreSQL under `ruby -w`; 100% line **and** branch coverage of `lib/`, no pending, skipped or focused examples, no Ruby warning from `bin/`, `db/`, `lib/` or `spec/` (and no third-party warning in the CI log) |
| `rake rubocop` | RuboCop with every cop enabled (`EnabledByDefault`), and the rubocop-md, -performance, -rails, -rake, -rspec, -sorbet and -thread_safety plugins (`.rubocop.yml` lists each cop that stays off, with the reason); no todo file |
| `rake suppressions` | no inline suppression anywhere (`script/forbidden_suppressions.sh`, see below) |
| `rake typecheck` | Tapioca generates the gem RBIs (from `typecheck.gemfile`), then `srb tc` must report no errors; every file but the RSpec examples and `spec_helper.rb` is `typed: strict` (the Rakefile and `bin/db` included) |
| `rake yard` | `yardoc --fail-on-warning`, and YARD must report 100% documented, private and protected objects included, for `lib/` and `script/` |
| `rake reek` / `rake flay` / `rake flog` | no code smell (default Reek configuration), no structural duplication (Flay's default mass) and no method scoring above 20 with Flog, in `lib/`, `bin/` and `script/` |
| `rake audit` | bundler-audit: no dependency with a known vulnerability |

The other checks:

| Check | Gate |
| --- | --- |
| `mutant` | mutation testing on Ruby 3.3.13 (see the hold below); every mutation must be killed. Set `MUTANT_RUBY_BIN` to the directory of that Ruby when it is not first on `PATH` |
| `outdated` | every dependency at its newest release, except the documented holds |
| `scorecard` | every dependency at OpenSSF Scorecard 3 or above, except the allowlist |
| `actionlint` | the workflows (actionlint also runs ShellCheck on every `run:` script) |
| `zizmor` | workflow security, pedantic persona |
| `shellcheck` | the shell scripts, every optional check (`.shellcheckrc`) at `--severity=style` |
| `shfmt` | the shell scripts are formatted (`-s -i 2 -ci -bn`) |
| `yamllint` | every YAML file, `--strict`, every rule but key-ordering (`.yamllint.yml`) |
| `editorconfig` | every file follows `.editorconfig` |
| `hadolint` | the Dockerfile, failing on any finding down to `style` |
| `checkmake` | the Makefile |
| `markdownlint` | every Markdown file, every rule (`.markdownlint-cli2.yaml`) |
| `typos` | spelling |
| `gitleaks` | no secret in the full history |
| `trivy` | no HIGH or CRITICAL vulnerability in the built image, no misconfiguration |
| `end-to-end` | the Docker image and docker compose, as a user runs them (`script/end_to_end.sh`) |

The tools are the versions CI pins (see `.github/workflows`). Three checks run
only in CI: the dependency review of a pull request's changes (any severity,
any scope), CodeQL, and the warning gates, which read the CI logs.

`rake outdated` (`script/outdated.rb`) checks the gems, Bundler, RubyGems
(the CI jobs install the newest with `rubygems: latest`), Ruby
(`.ruby-version` and the mutation-testing Ruby), the Docker images of
`Dockerfile`, `docker-compose.yml` and the workflows, every GitHub Action
(newest tag, and its pinned SHA must be that tag's commit), every tool a
workflow installs and the Python packages of `.github/requirements`. A
dependency that cannot be updated goes on the hold list,
`script/outdated_holds.yml`, with the upstream constraint that blocks it; the
check also fails for a hold that is no longer needed.

`rake scorecard` (`script/scorecard.rb`) looks up the source repository of
every gem in `Gemfile.lock` and of every GitHub Action the workflows use, and
fails when its [OpenSSF Scorecard](https://scorecard.dev) is below 3. A
dependency that scores lower but cannot be dropped or replaced is allowed one
package at a time in `script/scorecard_allowlist.yml`, with the score it was
reviewed at and the reason it stays; the check also fails for an allowance
that is no longer needed. (The dependency review action only knows one global
warning level, so its own Scorecard warnings are turned off in favour of this
check.)

**Hold: mutation testing runs on Ruby 3.3.13, not on `.ruby-version`.** The
newest mutant (0.17.1, and its `main` branch as of 2026-10-28) requires
`parser/current` (`ruby/lib/mutant.rb`) and depends on `parser ~> 3.3.10`;
unparser 0.9.0 requires it too. The newest parser (3.3.13.0) has no grammar
past Ruby 3.3, and its `lib/parser/current.rb` prints
`warning: parser/current is loading parser/ruby33, ... but you are running 4.0.9`
for any other Ruby. Running mutant on Ruby 4.0 would therefore mean silencing a
warning, which this repository forbids. Mutation testing runs on Ruby 3.3.13
with `mutant.gemfile` (the main Gemfile with that Ruby, installed from the
versions of `Gemfile.lock`); `rake outdated` keeps that Ruby the newest 3.3
release. Mutation runs are slow; while iterating, run one subject at a time,
e.g. `BUNDLE_GEMFILE=mutant.gemfile bundle exec mutant run 'Migrator::Status*'`.

**Hold: `-w` is off for four third-party tools.** Every Ruby command in CI
runs with `RUBYOPT=-w -W:deprecated -W:performance`, except RuboCop, Tapioca,
YARD and bundler-audit, whose own code warns under `-w` (kramdown's
`parser/base.rb`, Tapioca's redefined `exit`/`abort`, YARD's `yardoc.rb` and
`hybrid_markdown.rb`, bundler-audit's redefined `say_error`): those jobs run
with `-W:deprecated -W:performance` only, and the warning gate still rejects
any warning they print. Installing gems (setup-ruby, the mutation bundle)
drops `-w` and `-W:performance` for the same reason (RubyGems'
`specification.rb`).

## Rules

- **No inline suppressions.** Nothing may silence a linter, scanner, type
  checker, warning or test in place: no `rubocop:disable`, `:nocov:`, `:reek:`,
  `mutant:disable`, `gitleaks:allow`, `nosec`, `hadolint ignore`,
  `shellcheck disable`, `yamllint disable`, `markdownlint-disable`,
  `trivy:ignore`, `T.unsafe`/`T.cast`/`T.bind`/`T.untyped` in any
  `typed: strict` file,
  `$VERBOSE = nil`, `skip`/`pending`/`focus`, and so on, and no file that only
  holds exceptions (`.rubocop_todo.yml`, `.trivyignore`, `.gitleaksignore`,
  ...). Fix the cause. A rule that cannot apply to a file is configured
  narrowly in the tool's configuration file, with the reason written next to
  it (see `.rubocop.yml`, `.yamllint.yml`, `.editorconfig` and
  `.markdownlint-cli2.yaml`).
- **No warnings.** Every workflow ends with a warning gate job
  (`script/warning_gate.sh`) that fails the run when the log of any job
  contains a warning or a deprecation notice.
- **Behavior is specified.** Every behavioral fix needs a regression spec, and
  every surviving mutant needs a test that kills it (or, when the mutation
  cannot change observable behavior, simpler code).
- **Examples never write into the project.** Each example runs in its own
  temporary working directory, with `Boot::SCHEMA_FILE` and
  `Boot::MIGRATIONS_DIR` pointed into it.
- Keep `db/schema.rb` exactly what `db scan` writes: after changing a
  migration, run `make scan` and commit the result.
- `sorbet/config` carries the `--suppress-payload-superclass-redefinition-for`
  lines that `tapioca gem` adds itself: the rdoc gem (a dependency of the
  tooling) redefines classes of Ruby's standard library that Sorbet ships its
  own definitions of.
