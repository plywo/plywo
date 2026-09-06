# Subject environments

Plywo's own control plane is intentionally Rails + PostgreSQL. Customer subject portability lives at a different boundary.

A subject environment prepares the software being measured and returns the runtime environment needed to capture baseline/candidate evidence. The local GitHub runner delegates these responsibilities instead of owning database-product setup directly.

The lifecycle interface is intentionally small:

```text
prepare(root:, execution:, role:)
env_for(root:, execution:, role:)
cleanup(root:, execution:, role:)
```

`prepare` establishes isolated comparable state and returns the environment used for capture. `env_for` exposes the same environment without mutating subject state. `cleanup` releases adapter-owned resources after the run.

## Capability contract

Subject environments also declare the execution capabilities they actually provide. The declarations are namespaced strings, for example:

```text
framework.rails
persistence.postgresql
persistence.sqlite
queue.solid_queue
queue.active_job_test_adapter
telemetry.subject_owned_rails
runtime.local_process
state.isolated_comparable
evidence.sql_queries
evidence.background_jobs
```

The namespaces represent composition dimensions rather than a monolithic adapter taxonomy:

```text
Subject environment
  framework.*
  persistence.*
  queue.*
  telemetry.*
  runtime.*
  state.*
  evidence.*
```

`Environment#capability?` checks an exact capability and `Environment#capabilities_for` queries one namespace.

These declarations are execution-planning and discovery metadata inside the subject boundary. They are **not** fields in `Plywo::Executor::Request` or `Plywo::Executor::Result`, and they are not a promise that today's capability identifiers are a stable public wire protocol.

The important semantic guarantee is `state.isolated_comparable`: baseline and candidate receive state that can be compared safely. How that property is achieved belongs to the environment implementation, not the executor contract.

Capabilities describe what an adapter can actually prove. Unsupported signals must stay absent or unavailable; adapters must never advertise or synthesize evidence merely to make two engines look alike.

## Rails + PostgreSQL subjects

`Plywo::Subject::RailsPostgresEnvironment` preserves Plywo's existing dogfood behavior and declares:

```text
framework.rails
persistence.postgresql
queue.solid_queue
telemetry.subject_owned_rails
runtime.local_process
state.isolated_comparable
evidence.sql_queries
evidence.background_jobs
```

Its state isolation is:

```text
baseline  -> isolated PostgreSQL primary + queue databases
candidate -> isolated PostgreSQL primary + queue databases
```

`PLYWO_LOCAL_POSTGRES_URL` is therefore an implementation detail of that subject environment. It is not part of `Plywo::Executor::Request`, `Plywo::Executor::Result`, or the generic customer execution contract.

## Rails + SQLite subjects

`Plywo::Subject::RailsSqliteEnvironment` proves that customer persistence does not inherit the control plane's PostgreSQL requirement and declares:

```text
framework.rails
persistence.sqlite
queue.active_job_test_adapter
telemetry.subject_owned_rails
runtime.local_process
state.isolated_comparable
evidence.sql_queries
evidence.background_jobs
```

It prepares one SQLite file per execution role:

```text
baseline  -> ..._base.sqlite3
candidate -> ..._candidate.sqlite3
```

The adapter removes stale database/WAL/SHM files before preparation and cleans them after execution. The built-in proof uses Active Job's test adapter, so it does not synthesize a second queue database just to imitate the PostgreSQL dogfood environment.

The SQLite database path is passed through the adapter-private `PLYWO_SQLITE_DATABASE` environment variable. No `PLYWO_LOCAL_POSTGRES_URL`, PostgreSQL URL, or database-product field is added to the portable executor request/result schemas.

`script/prove_rails_sqlite_subject.rb` builds a disposable Rails + SQLite Git subject, injects the same Plywo Rails instrumentation, creates baseline and candidate commits, and executes them through:

```text
Plywo::Executor::Request v1
  -> LocalAdapter
  -> LocalPullRequestRunner
  -> RailsSqliteEnvironment
  -> script/plywo_capture_subject.rb
  -> ExecutionReducer / ExecutionPair
  -> Plywo::Executor::Result v1
```

The candidate deliberately increases database query behavior so the proof returns real SQLite query evidence and a `DATABASE_QUERY_REGRESSION` through the same Behavioral Diff contract used for PostgreSQL dogfood.

This is customer-subject adapter coverage. It does not make the Plywo service itself SQLite-compatible; Plywo's durable control plane remains PostgreSQL-only by design.

## Portable and native evidence

The current portable database semantic is the existing `sql_queries` signal used by Behavioral Diff. Both PostgreSQL and SQLite proofs can produce it without requiring the diff layer to know the database engine.

Future adapters may add richer portable semantics and native evidence side by side, for example query duration or transaction counts as portable evidence and engine-specific explain/scan/lock evidence where supported. Native evidence should be preserved rather than flattened into invented cross-engine equivalence.

Do not build framework/database/queue adapter matrices speculatively. Add capability implementations when a real customer stack requires them. Rails + SQLite is the first portability proof; subsequent adapters can compose the same namespaces without changing the portable executor wire contract.

See #43, #44, and #54.
