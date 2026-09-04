# GitHub integration

One Plywo run projects into several GitHub surfaces.

## PR comment

Concise human summary. Use GitHub-flavored Markdown and update one durable bot-owned comment instead of posting a new comment on every push.

## Check Run

Stable merge and agent state. The initial check name is:

```text
Plywo / Behavioral Diff
```

Decision mapping:

```text
allow  -> success
review -> neutral
block  -> failure
```

The check uses the Plywo `run_id` as `external_id`. GitHub Actions may assign its own Check Run page as `details_url`, so the output summary also carries an explicit link to the Actions execution. GitHub presents the latest `Plywo / Behavioral Diff` context for the current head; internal Check Run IDs may differ across workflow attempts.

## Annotations

Use source-localized annotations only when a finding can be mapped confidently to changed code.

## Agent contract

Agents should never be required to parse the PR comment or Check Run prose. Publish a versioned result JSON and later expose the same model through API/MCP.

```text
PR comment -> What changed?
Check      -> Can this merge?
Annotation -> Where is the likely source?
Plywo UI   -> Why did it happen?
API/MCP    -> What should an agent do next?
```
