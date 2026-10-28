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

Run the verification suite. Every gate is enforced in CI and fails the build:

```bash
bundle exec rake
```

That runs, in order:

| Task | Gate |
| --- | --- |
| `rake spec` | RSpec against PostgreSQL; 100% line **and** branch coverage of `lib/`, no pending, skipped or focused examples, no Ruby warning from `bin/`, `db/`, `lib/` or `spec/` (and no third-party warning in the CI log) |
| `rake rubocop` | RuboCop with rubocop-md, -performance, -rails, -rake, -rspec, -sorbet and -thread_safety (`.rubocop.yml`); no todo file |
| `rake suppressions` | no inline suppression anywhere (`script/forbidden_suppressions.sh`, see below) |
| `rake typecheck` | Tapioca generates the gem RBIs (from `typecheck.gemfile`), then `srb tc` must report no errors; `lib/` and `bin/` are `typed: strict`, `db/` is `typed: true` |
| `rake yard` | YARD must report 100% documented, without warnings |
| `rake reek` / `rake flay` | no code smell (default Reek configuration) and no structural duplication (Flay's default mass) in `lib/` and `bin/` |
| `rake audit` | bundler-audit: no dependency with a known vulnerability |

Not part of the default task, but also enforced in CI:

```bash
bundle exec rake outdated   # every dependency at its newest release, except the documented holds
bundle exec rake mutant     # mutation testing on Ruby 3.3.13; every mutation must be killed
```

`rake outdated` (`script/outdated.rb`) checks the gems, Bundler, RubyGems
(the CI jobs install the newest with `rubygems: latest`), Ruby
(`.ruby-version` and the mutation-testing Ruby), the Docker images of
`Dockerfile`, `docker-compose.yml` and the workflows, every GitHub Action
(newest tag, and its pinned SHA must be that tag's commit) and every tool a
workflow installs. A dependency that cannot be updated goes on the hold list,
`script/outdated_holds.yml`, with the upstream constraint that blocks it; the
check also fails for a hold that is no longer needed.

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
release. Mutation
runs are slow; while iterating, run one subject at a time, e.g.
`BUNDLE_GEMFILE=mutant.gemfile bundle exec mutant run 'Migrator::Status*'`.

The other linters run in the "Repository lint" workflow; locally:

```bash
actionlint                                                  # the workflows
zizmor --persona pedantic .github/workflows                 # workflow security
shellcheck script/*.sh .githooks/pre-commit bin/entrypoint.sh
hadolint Dockerfile
checkmake Makefile
markdownlint-cli2 "**/*.md"                                 # .markdownlint-cli2.yaml
typos
gitleaks git --redact .                                     # secret scanning, full history
docker build -t standalone-migrations . && trivy image --severity HIGH,CRITICAL --exit-code 1 standalone-migrations
```

## Rules

- **No inline suppressions.** Nothing may silence a linter, scanner, type
  checker, warning or test in place: no `rubocop:disable`, `:nocov:`, `:reek:`,
  `mutant:disable`, `gitleaks:allow`, `nosec`, `hadolint ignore`,
  `shellcheck disable`, `markdownlint-disable`, `trivy:ignore`,
  `T.unsafe`/`T.cast`/`T.bind`/`T.untyped` in `lib/` or `bin/`,
  `$VERBOSE = nil`, `skip`/`pending`/`focus`, and so on, and no file that only
  holds exceptions (`.rubocop_todo.yml`, `.trivyignore`, `.gitleaksignore`,
  ...). Fix the cause. A rule that cannot apply to a file is configured
  narrowly in the tool's configuration file, with the reason written next to
  it (see `.rubocop.yml` and `.markdownlint-cli2.yaml`).
- **No warnings.** Every workflow ends with a "Warning gate" job
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
