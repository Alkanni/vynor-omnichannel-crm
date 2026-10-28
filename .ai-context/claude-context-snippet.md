# Claude Code context snippet

Paste the block below into `AGENTS.md` (which `CLAUDE.md` symlinks to) or a local `CLAUDE.local.md`. It was **not** added automatically.

---

```markdown
## Codebase Intelligence (.ai-context/)

An architectural knowledge base lives in `.ai-context/` (analyzed at commit 9f920b54, upstream Chatwoot v4.18.0).

- Read `.ai-context/README.md` for orientation; use `.ai-context/index.yaml` to pick only the docs relevant to the task. Do not load the whole folder.
- Compare `git rev-parse HEAD` with `last_analyzed_commit` in `index.yaml`. If they differ, run `git diff --stat 9f920b54..HEAD` and treat docs whose `source_refs` changed as stale.
- Docs are navigation aids: verify cited files, symbols, and line numbers in source before relying on them. Claims are tagged VERIFIED / INFERRED / UNKNOWN.
- Before modifying code, consult `.ai-context/change-impact-guide.md` (model callbacks → event bus → listeners; EE `prepend_mod_with` overrides; jbuilder + push_event_data + webhook_data).
- After a verified change that alters architecture, flows, schema, or extension points, update the affected `.ai-context/` docs and their `index.yaml` entries.
```
