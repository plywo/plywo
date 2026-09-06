# Rails repository onboarding

Plywo v0.1 aims for a first Behavioral Review in a customer Rails pull request with minimal repository setup.

The first onboarding slice keeps the configuration intentionally small. Plywo discovers the Rails runtime and supported persistence automatically, while the repository declares the HTTP scenario that should be replayed against baseline and candidate.

## Minimal configuration

Add `plywo.yml` to the repository:

```yaml
version: 1
scenario:
  path: /orders/42
subject:
  persistence: auto
```

`subject.persistence: auto` is the default and may be omitted:

```yaml
version: 1
scenario:
  path: /orders/42
```

For this first slice, explicit persistence values are limited to:

```text
auto
postgresql
sqlite
```

Unsupported or ambiguous persistence fails explicitly instead of silently falling back to PostgreSQL.

## What Plywo discovers

The local executor recognizes a Rails subject from the standard application boundary:

```text
config/application.rb
bin/rails
```

Persistence is discovered from `config/database.yml` first. If the adapter is not declared there, Plywo falls back to Gemfile/Gemfile.lock evidence for `pg` or `sqlite3`.

The result resolves to the existing subject environments:

```text
Rails + PostgreSQL -> Plywo::Subject::RailsPostgresEnvironment
Rails + SQLite     -> Plywo::Subject::RailsSqliteEnvironment
```

The environment still owns preparation, isolated baseline/candidate state, runtime variables, and cleanup.

## A/B configuration ownership

Plywo prepares exact baseline and candidate Git worktrees before resolving the run profile.

`plywo.yml` is loaded from the candidate head once. Its scenario path is then applied to both executions:

```text
candidate plywo.yml
       |
       +--> baseline scenario
       |
       +--> candidate scenario
```

This preserves one comparison contract even when the baseline commit did not contain Plywo configuration yet. It also means adding `plywo.yml` in the pull request can onboard an existing repository without a prerequisite commit on the default branch.

Persistence discovery remains per-worktree when `subject.persistence: auto` is used:

```text
baseline worktree  -> discover environment
candidate worktree -> discover environment
```

That avoids baking the candidate database implementation into the baseline execution and allows a persistence migration to be represented honestly.

## Current five-minute shape

The intended product flow is:

1. Install the Plywo GitHub App for the repository.
2. Add a minimal `plywo.yml` with one HTTP scenario path.
3. Open or update a pull request.
4. Plywo checks out exact baseline/candidate subjects.
5. Rails and PostgreSQL/SQLite are discovered automatically.
6. Plywo runs the same scenario against both subjects.
7. The Behavioral Review appears as a GitHub Check and PR feedback.

Today the executor/runtime still needs product deployment work before this is a hosted self-service flow. The repository-side contract in this document is the first step toward that v0.1 onboarding target.

## Deliberate limits

This slice does not add arbitrary setup commands, shell hooks, secrets, containers, MySQL, Sidekiq, non-Rails runtimes, or a general-purpose configuration language.

Those capabilities should be introduced from real onboarding requirements. In particular, customer-authored commands would require a separate trust and execution-policy design; `plywo.yml` currently carries declarative scenario and persistence metadata only.

See #57 and `docs/subject-environments.md`.
