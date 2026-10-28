#!/usr/bin/env bash
# Fails when a tracked file silences a linter, scanner, type checker, warning or test, or weakens typing,
# and when a file exists whose only purpose is to hold such exceptions.
# Inline suppressions are forbidden everywhere in this repository (see CONTRIBUTING.md): fix the cause.
# Markdown files are skipped because they document the rules.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# This script names the patterns, so it is not scanned for them. Generated RBIs are not ours.
files=$(git ls-files -z -- . ':(exclude)*.md' ':(exclude)script/forbidden_suppressions.sh' ':(exclude)sorbet/rbi/gems' \
  | tr '\0' '\n')

status=0
check() {
  local description=$1 pattern=$2 scope=${3:-.}
  local hits
  hits=$(printf '%s\n' "$files" | grep -E "^${scope}" | xargs -r grep -nEH -e "$pattern" -- || true)
  if [ -n "$hits" ]; then
    printf 'Forbidden (%s):\n%s\n\n' "$description" "$hits"
    status=1
  fi
}

check 'RuboCop directive' 'rubocop:(disable|enable|todo)'
check 'Reek suppression' ':reek:'
check 'SimpleCov exclusion' ':nocov:|nocov_token'
check 'mutant suppression' 'mutant:disable'
check 'gitleaks allow' 'gitleaks:allow'
check 'zizmor ignore' 'zizmor: ?ignore'
check 'shellcheck disable' 'shellcheck +disable'
check 'hadolint ignore' 'hadolint +(ignore|global)'
check 'markdownlint disable' 'markdownlint-(disable|capture|restore|configure-file)'
check 'typos ignore' 'typos: ?(ignore|off)|spellchecker: ?(disable|ignore)'
check 'trivy ignore' 'trivy:ignore'
check 'LGTM/CodeQL suppression' 'lgtm\[|codeql\[|codeql-disable|lgtm: ?ignore'
check 'nosec' 'nosec'
check 'warning silencing' '[$]VERBOSE *= *(nil|false)|Warning\.ignore|silence_warnings|[$]stderr *= *File::NULL|-W0|RUBYOPT=.*-W:no-'
check 'skipped or focused test' '^[[:space:]]*([xf](it|describe|context)|skip|pending)([[:space:]]|\()|focus: *true|, *:focus|, *(skip|pending): ' 'spec/'
check 'Sorbet escape hatch' 'T\.(unsafe|cast|bind|untyped)\b|typed: *(false|ignore)' '(lib/|bin/)'
check 'Sorbet sigil weaker than true' 'typed: *(false|ignore)' 'db/'

# Files that exist only to hold exceptions.
for exception_file in .rubocop_todo.yml .reek.yml config.reek .trivyignore .trivyignore.yaml .gitleaksignore \
  .hadolint.yaml .hadolint.yml .markdownlintignore _typos.toml typos.toml .typos.toml .simplecov; do
  if printf '%s\n' "$files" | grep -qx -- "$exception_file"; then
    printf 'Forbidden (exception file): %s\n\n' "$exception_file"
    status=1
  fi
done

exit "$status"
