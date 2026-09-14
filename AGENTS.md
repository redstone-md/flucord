# AGENTS.md

## Writing style

Docs, code comments, and user-facing text use simple, clear language. Short sentences, plain words, no unexplained jargon. A non-native reader should follow everything on the first pass.

No em dashes. Use a comma, colon, semicolon, parentheses, or a separate sentence instead.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (redstone-md/flucord) via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage labels are used as-is: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.
