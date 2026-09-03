# Plywo

**Tests passed. Behavior changed.**

Plywo is a behavioral change validation platform. It runs the same scenario against two software subjects, captures execution evidence, and explains what changed.

The product starts as a Rails 8.1 monolith on purpose. Portable contracts and comparison logic stay outside Rails-specific code so the CLI, protocol, recorders, drivers, and ingestion components can be extracted later without redesigning the model.

## First vertical slice

```text
main + scenario ─┐
                 ├─> evidence ─> behavioral diff ─> GitHub
PR   + scenario ─┘
```

Both functional executions may pass. Plywo can still detect changes in latency, SQL queries, background jobs, external side effects, memory, network behavior, or other runtime evidence.

Try the current portable prototype:

```bash
bin/plywo diff \
  --baseline examples/behavioral-diff/main.json \
  --candidate examples/behavioral-diff/candidate.json
```

Machine-readable output:

```bash
bin/plywo diff \
  --baseline examples/behavioral-diff/main.json \
  --candidate examples/behavioral-diff/candidate.json \
  --format json
```

## Repository map

- `docs/` - product thesis, architecture, decisions, RFCs, demo, roadmap
- `schemas/` - machine-readable execution/result contracts
- `lib/plywo/` - portable core without Rails dependencies
- `app/` - Rails product shell and orchestration
- `examples/` - deterministic demo evidence

## Runtime

- Ruby 3.4.10
- Rails 8.1.3.1
- PostgreSQL

## Current status

Bootstrap slice. The diff core is real and runnable. Runtime capture, GitHub App integration, Playwright orchestration, OpenTelemetry ingestion, CLI/mobile adapters, and object-storage artifacts come next.
