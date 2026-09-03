# RFC 0001: Agent-readable result contract

Status: Draft

Goal: let a coding agent decide what happened and what to do next without scraping logs or Markdown.

Initial reason codes:

- `TEST_FAILURE`
- `BEHAVIORAL_REGRESSION`
- `PERFORMANCE_REGRESSION`
- `DATABASE_QUERY_REGRESSION`
- `MEMORY_REGRESSION`
- `SIDE_EFFECT_CHANGED`
- `NETWORK_BEHAVIOR_CHANGED`
- `NEW_RUNTIME_ERROR`
- `FLAKY_EXECUTION`
- `INFRA_FAILURE`
- `BASELINE_MISSING`
- `EXECUTION_TIMEOUT`
- `MANUAL_REVIEW_REQUIRED`

Reason codes are API.

Agent policy:

```text
INFRA_FAILURE -> rerun
TEST_FAILURE -> inspect test
PERFORMANCE_REGRESSION -> inspect traces/profiles
MANUAL_REVIEW_REQUIRED -> stop and ask human
high/critical regression -> do not merge
```
