# Execution leases

Plywo uses a durable lease on each claimed GitHub pull request execution so a worker that disappears cannot leave the control plane in `running` forever.

## Lifecycle

```text
queued
  -> claim!
  -> running + heartbeat_at + lease_expires_at
  -> heartbeat schedule starts before executor dispatch
  -> useful work remains live
     -> heartbeat renews the exact current attempt
  -> executor result
     -> finalizer renews the live lease
     -> completed / failed / ignored

running + expired lease
  -> production reaper
  -> lease expiry job
  -> infra_failure
  -> GitHub failed Check
  -> eligible for explicit re-run

queued/running
  -> cancellation request
  -> cancelled + outcome=cancelled
  -> lease closes immediately
  -> heartbeat stops
  -> executor cancellation is delivered cooperatively
  -> late result is ignored
```

`attempt_count` changes only when `claim!` succeeds. Lease expiry does not create a new attempt. A later GitHub re-run first requeues the same durable execution and the next successful claim increments the attempt.

## Heartbeats

`GithubPullRequestExecutionHeartbeatJob` is scheduled before executor dispatch. This covers both queue delay and a long synchronous remote HTTP request. A heartbeat renews only when all of these remain true:

- the execution still exists
- its status is `running`
- the heartbeat carries the exact current `attempt_count`
- the existing lease is still live

A successful heartbeat schedules the next heartbeat. Terminal, cancelled, expired, or superseded attempts stop without rescheduling.

The default heartbeat interval is one third of the execution lease. `PLYWO_EXECUTION_HEARTBEAT_INTERVAL_SECONDS` can override it, but the interval must remain positive and shorter than `PLYWO_EXECUTION_LEASE_SECONDS`.

## Cancellation

Cancellation is a terminal control-plane outcome, not an infrastructure failure. `Plywo::Executor::Cancellation` atomically marks the exact active attempt as `status=cancelled`, `outcome=cancelled`, records `cancelled_at` and `cancellation_reason`, closes the lease, and then schedules cooperative cancellation delivery to the executor.

For remote executors the control plane posts to the exact attempt cancellation endpoint. The executor service stores cancellation durably in `plywo_executor_requests`. A cancellation can win before the execution request arrives, while the adapter is running, or after a duplicate delivery. Once cancelled, that idempotency key cannot start work or accept a late result.

Cancellation delivery failure never rewrites the durable execution as `infra_failure`. Hard process or container termination remains a separate executor-host concern; the current contract guarantees durable cancellation and rejection of late results.

## Safety properties

- only `running` executions with an overdue lease can be expired
- renewal and expiry are conditional database updates, so a renewed lease wins over an already-enqueued stale expiry job
- heartbeats from an older attempt cannot renew a newer attempt
- late executor results cannot finalize an expired, cancelled, or terminal execution
- an expired execution is classified as `infra_failure`, never as a behavioral regression
- a cancelled execution is classified as `cancelled`, never as `infra_failure`
- publication is retriable after the durable lease failure has already been recorded
- stale base/head state suppresses publication for an obsolete pull request execution

## Production schedule

`GithubPullRequestExecutionLeaseReaperJob` runs every minute in production and schedules `GithubPullRequestExecutionLeaseExpiryJob` for overdue GitHub executions.

The default lease is 30 minutes and can be changed with `PLYWO_EXECUTION_LEASE_SECONDS`.

The current heartbeat is control-plane scheduled. A future worker-host heartbeat protocol can make liveness independent of the control-plane queue and can carry progress metadata, but it must preserve the exact-attempt fencing rules above.
