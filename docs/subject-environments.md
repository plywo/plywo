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

The first implementation, `Plywo::Subject::RailsPostgresEnvironment`, preserves Plywo's existing dogfood behavior:

```text
baseline  -> isolated PostgreSQL primary + queue databases
candidate -> isolated PostgreSQL primary + queue databases
```

`PLYWO_LOCAL_POSTGRES_URL` is therefore an implementation detail of that subject environment. It is not part of `Plywo::Executor::Request`, `Plywo::Executor::Result`, or the generic customer execution contract.

The next proof should add Rails + SQLite by introducing another subject environment implementation. That adapter should isolate baseline/candidate state with separate SQLite files while returning evidence through the same portable Plywo execution contracts.

Future subject environments may compose framework, persistence, queue, telemetry, and runtime capabilities rather than becoming one large product-specific adapter. Unsupported capabilities should be absent or unavailable, never synthesized.

See #43 and #44.
