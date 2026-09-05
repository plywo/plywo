# Clock authority

Plywo uses different clocks for different kinds of time.

## Plywo-owned durable lifecycle

Plywo is intentionally a PostgreSQL-backed control plane. Durable lifecycle transitions that participate in distributed correctness use PostgreSQL as their shared wall-clock authority.

The canonical database wall clock is:

```sql
clock_timestamp()
```

`clock_timestamp()` is deliberate. `CURRENT_TIMESTAMP` and `transaction_timestamp()` are transaction-stable, while leases, heartbeats, cancellation, and finalization need actual wall-clock progress even inside a long transaction.

Examples include:

```text
execution claim
heartbeat / lease renewal
lease expiry
finalization fence
cancellation
executor-service request claim / reclaim
executor-service request completion
GitHub webhook delivery claim / completion
```

Production lifecycle code should use `Plywo::ClockAuthority.database_now` rather than sampling `Time.current` on whichever host happens to run the transition.

Generic Rails audit timestamps such as `created_at` and `updated_at` are not distributed timing evidence unless a lifecycle explicitly assigns them from the authoritative clock. For example, webhook claim assigns `updated_at` from the same database clock as `started_at` so that one transition has one clock domain.

## Process-local elapsed duration

Elapsed work inside one process uses a monotonic clock:

```ruby
Process.clock_gettime(Process::CLOCK_MONOTONIC)
```

Monotonic timestamps are process-local measurement values. Never compare a monotonic timestamp produced on one host with a monotonic timestamp produced on another host.

## Customer runtime evidence

The PostgreSQL rule above applies only to Plywo-owned lifecycle state. It does not make PostgreSQL a requirement for customer software.

Customer timing is capability based:

```text
same-process elapsed work -> local monotonic duration
queue/backend timing      -> backend-owned timestamps when both boundaries share that authority
OTel timing               -> trustworthy span duration / causal timing
shared clock              -> only when an adapter can prove the clock domain
otherwise                 -> unavailable
```

A customer subject may use SQLite, MySQL, PostgreSQL, MongoDB, DynamoDB, an external service, multiple stores, or no database. Its persistence engine is not automatically a distributed clock authority.

## Testing

Lifecycle methods retain an explicit `now:` seam for deterministic unit tests. Production callers omit it and therefore use PostgreSQL-authoritative time.

Clock-skew tests should prove that changing a host's wall clock cannot change claim, lease, reclaim, cancellation, or expiry correctness when the database clock is unchanged.
