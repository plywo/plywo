# RFC 0002: Runner adapter contract

Status: Draft

A runner adapter may:

1. start an execution;
2. inject correlation context;
3. run the customer's framework or command;
4. collect native status and artifacts;
5. publish normalized measurements;
6. finalize execution.

Examples:

```text
Playwright -> trace + browser/network evidence
Capybara   -> test result + Rails/browser evidence
Maestro    -> mobile flow + screenshots/video/device samples
CLI        -> exit/stdout/stderr/time/RSS/profile
k6         -> load metrics + traces
```

Non-goal: define a universal click/fill/assert DSL.
