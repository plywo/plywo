# Demo 0001: Behavioral Diff

**The tests passed. Plywo found what got worse.**

Scenario:

```text
Sign up -> Create project -> Send welcome notification -> Dashboard appears
```

Run the exact same scenario against `main` and a PR. Both pass.

Candidate regressions:

- duration: 820 ms -> 1460 ms
- SQL queries: 14 -> 47
- jobs: 1 -> 3
- emails: 1 -> 2

GitHub headline:

```text
Plywo / Behavioral Diff
Tests passed on both versions, but behavior changed.
```

Do now: portable diff, Rails shell, normalized result contract, demo evidence, GitHub report contract.

Do not do yet: generic scenario DSL, rrweb recorder, mobile adapters, Temporal integration, load runner, production replay, TMS UI, or microservices.
