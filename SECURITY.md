# Security policy

How to report a vulnerability of the `db` CLI or of its Docker setup, and how
the repository guards its supply chain.

## Supported versions

Security fixes are made on the `main` branch. There are no releases and no
maintained release branches.

## Reporting a vulnerability

Please report suspected vulnerabilities privately rather than opening a public
issue.

- Preferred: GitHub's **Report a vulnerability** flow under the repository's
  [Security tab](https://github.com/VitaliiLazebnyi/standalone_migrations/security)
  (private vulnerability reporting).
- Alternatively, email <vitalii.lazebnyi.github@gmail.com> with the details.

Include a description of the issue, the affected commit and a minimal
reproduction if possible. You can expect an acknowledgement within a few
business days. Once a fix is merged, the advisory is disclosed.

## Scope

The `db` CLI runs the migrations of `db/migrate` against the PostgreSQL
database it is configured for, and can scan and baseline an existing database
(see [README.md](README.md)). The credentials in `docker-compose.yml` and the
defaults of `config/database.yml` are for local development; set your own
(`DATABASE_USER`, `DATABASE_PASSWORD`) before pointing the CLI at a real
database.

## Supply-chain safeguards

Every pull request runs the checks of [CONTRIBUTING.md](CONTRIBUTING.md): among
them bundler-audit, dependency review (any severity), gitleaks over the whole
history, Trivy on the image, CodeQL and zizmor; the OpenSSF Scorecard runs on
the default branch. Every job runs behind a network egress allow list
(`step-security/harden-runner`). Every GitHub Action is pinned to a full commit
SHA and every Docker image to its digest; Dependabot proposes updates after a
one-week cooldown.
