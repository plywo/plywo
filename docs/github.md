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

The check uses the Plywo `run_id` as `external_id` and links `details_url` to the full execution. A rerun on the same head updates the existing Plywo check instead of creating a duplicate.

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
