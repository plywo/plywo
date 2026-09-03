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

## Dogfood Plywo with Plywo

The Rails app now has a real local-only execution probe. It runs two HTTP executions through the Rails middleware stack, propagates Plywo correlation headers, observes Rails notifications, and feeds captured evidence into the same portable behavioral diff engine.

```bash
bin/rails db:prepare
bin/rails plywo:dogfood
```

The demo intentionally keeps both executions functionally green while the candidate performs more SQL, enqueues more jobs, emits a duplicate email side effect, and takes longer.

The capture path is real:

```text
Rack request
  -> X-Plywo-Run-Id / X-Plywo-Execution-Id / X-Plywo-Subject
  -> Rails middleware + controller
  -> ActiveSupport::Notifications
       SQL / ActiveJob / request / side effects
  -> Plywo::Rails::EvidenceCollector
  -> Plywo::BehavioralDiff
```

## Portable diff

The core comparison command remains Rails-independent:

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
- `lib/plywo/` - portable core plus Rails adapters/probes behind explicit namespaces
- `app/` - Rails product shell and dogfood target
- `examples/` - deterministic demo evidence

## Runtime

- Ruby 3.4.10
- Rails 8.1.3.1
- PostgreSQL

## Current status

The diff core and first Rails runtime capture are real and green in CI. The next product-facing slice is to run baseline/candidate subjects from Git worktrees or preview environments and publish the resulting report back to GitHub.
