# GitHub integration

One Plywo run projects into several GitHub surfaces.

## PR comment

The PR comment is the primary human surface. It is a concise behavioral review, not a CI log.

Plywo owns one durable comment identified by a hidden marker and updates it on every run instead of adding a new comment on every push.

```html
<!-- plywo:behavioral-diff:v1 -->
```

Ownership is scoped by both the marker and the publishing GitHub actor. GitHub Actions currently uses `github-actions[bot]`. A future GitHub App can supply its own actor identity without changing the result or rendering contracts. This prevents Plywo automation from attempting to edit a matching comment owned by a human or another integration.

The comment contains:

- merge recommendation and regression count;
- baseline vs candidate runtime signal table;
- severity-ranked findings;
- execution/correlation context;
- run/scenario identity and a link to the Actions run;
- a bootstrap note when the baseline is not a real executable git subject.

GitHub is normally a one-baseline/one-candidate projection because one PR has one head. The underlying comparison contract is one baseline to N candidates so CLI and Plywo UI can compare multiple agent implementations.

## Check Run

Stable merge/agent state. Initial stable name:

```text
Plywo / Behavioral Diff
```

Expose the Plywo run as `external_id` and link `details_url` to the full investigation.

## Annotations

Use source-localized annotations only when a finding can be mapped confidently to changed code.

## Agent contract

Agents should never be required to parse the PR comment. Publish versioned execution/result/comparison JSON and later expose the same model through API/MCP.

```text
PR comment -> What changed?
Check      -> Can this merge?
Annotation -> Where is the likely source?
Plywo UI   -> Why did it happen?
API/MCP    -> What should an agent do next?
```

## Bootstrap limitation

The first Plywo PR bootstraps the runnable Rails application from a `main` branch that contains only a README. It therefore cannot honestly execute the PR base as a Rails process. The first dogfood comment labels its deterministic baseline explicitly as synthetic.

After this PR is merged, the base branch becomes runnable and the next slice can execute the same scenario against two actual git subjects: base SHA and PR head SHA.
