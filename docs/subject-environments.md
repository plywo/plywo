# Subject environments

Plywo's own control plane is intentionally Rails + PostgreSQL. Customer subject portability lives at a different boundary.

A subject environment prepares the software being measured and returns the runtime environment needed to capture baseline/candidate evidence. The local GitHub runner delegates these responsibilities instead of owning database-product setup directly.

The current interface is intentionally small:

```text
prepare(root:, execution:, role:)
env_for(root:, execution:, role:)
cleanup(root:, execution:, role:)
```

`prepare` establishes isolated comparable state and returns the environment used for capture. `env_for` exposes the same environment without mutating subject state. `cleanup` releases adapter-owned resources after the run.

## Rails + PostgreSQL subjects

`Plywo::Subject::RailsPostgresEnvironment` preserves Plywo's existing dogfood behavior:

```text
baseline  -> isolated PostgreSQL primary + queue databases
candidate -> isolated PostgreSQL primary + queue databases
```

`PLYWO_LOCAL_POSTGRES_URL` is therefore an implementation detail of that subject environment. It is not part of `Plywo::Executor::Request`, `Plywo::Executor::Result`, or the generic customer execution contract.

## Rails + SQLite subjects

`Plywo::Subject::RailsSqliteEnvironment` proves that customer persistence does not inherit the control plane's PostgreSQL requirement.

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

The candidate deliberately increases database query behavior so the proof must return real SQLite query evidence and a `DATABASE_QUERY_REGRESSION` through the same Behavioral Diff contract used for PostgreSQL dogfood.

This is customer-subject adapter coverage. It does not make the Plywo service itself SQLite-compatible; Plywo's durable control plane remains PostgreSQL-only by design.

Future subject environments may compose framework, persistence, queue, telemetry, and runtime capabilities rather than becoming one large product-specific adapter. Unsupported capabilities should be absent or unavailable, never synthesized.

See #43, #44, and #54.
