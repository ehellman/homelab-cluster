---
name: sync-claude
description: |
  Validate that CLAUDE.md and every SKILL.md still match the codebase — referenced
  paths exist, `task` commands are real, code/skill references resolve.
  Two modes: full (all docs) or changed (only docs touched on the current branch vs main).

  Use when: (1) Before opening a PR, (2) After moving/renaming files that docs reference,
  (3) Auditing skills for staleness, (4) A SKILL.md mentions a path or task that may be gone.

  Triggers: "sync claude", "validate claude docs", "check documentation", "are the skills stale",
  "docs out of sync", "before commit", "/sync-claude", "validate SKILL.md", "stale references"
user-invocable: false
---

# Claude Documentation Sync

Validate Claude docs against the working tree before commits. Docs = repo-root
`CLAUDE.md` plus every `.agents/skills/<name>/SKILL.md` (the `.claude/skills/`
entries are symlinks to these — validate the source, not the link).

Default mode is `full`. Use `changed` to scope to docs touched on the current branch.

## Quick Start

```sh
S=.agents/skills/sync-claude/scripts

# 1. discover docs (full or changed)
"$S/discover-claude-docs.sh" full      # all docs
"$S/discover-claude-docs.sh" changed   # branch-scoped

# 2. extract references from one doc
"$S/extract-references.sh" .agents/skills/sops-age/SKILL.md

# 3. drive both: extract refs for every discovered doc
for doc in $("$S/discover-claude-docs.sh" full | jq -r '.[]'); do
  "$S/extract-references.sh" "$doc"
done
```

## Workflow

1. **Discover** docs via `scripts/discover-claude-docs.sh [full|changed]` → JSON array of paths.
2. **Extract** references from each doc via `scripts/extract-references.sh <doc>` → JSON
   (`markdown_links`, `code_paths`, `task_commands`, `skill_references`, `config_references`).
3. **Validate** every reference against the working tree (see checks below).
4. **Report** stale references grouped by doc, with a suggested fix per finding.

The scripts run standalone (no agent needed). For large doc sets you may fan out one
validator subagent per doc — but only after discovery + extraction, and keep each
subagent's output to a flat valid/invalid list with suggestions.

## Validation Checks

| Reference kind | Check | Pass condition |
|-|-|
| File / dir path | `test -e <path>` from repo root | path exists in working tree |
| Markdown link target | resolve relative to repo root | file or dir exists |
| `task <name>` | grep the name in `Taskfile.yaml` + `.taskfiles/**` | task is defined |
| Skill reference | `.agents/skills/<name>/` exists | skill dir present |
| Config reference | path exists | e.g. `.mcp.json`, `versions.env` resolve |

Stack paths that should resolve: `kubernetes/apps/<ns>/<app>/`, `.agents/skills/`,
`.taskfiles/`, `.github/`, `.mcp.json`.

### Confirming a task is real

Tasks are namespaced through `includes:` in `Taskfile.yaml`. A reference like
`task template:validate-schemas` maps to target `validate-schemas` in
`.taskfiles/template/Taskfile.yaml`; a bare `task reconcile` is a root target.
Known-good examples: `task template:validate-kubernetes-config`,
`task template:validate-schemas`, `task reconcile`. To verify, grep the unqualified
target name (after the last `:`) under the included Taskfile, e.g.

```sh
grep -rn '^  validate-schemas:' .taskfiles/template/Taskfile.yaml
```

## Worked Example

`extract-references.sh` on a skill emits, e.g.:

```json
{ "file": ".agents/skills/versions-renovate/SKILL.md",
  "task_commands": ["renovate:validate"],
  "config_references": ["renovate.json5", "versions.env"],
  "code_paths": ["kubernetes/platform/versions.env", ".github/renovate.json5"] }
```

Validate each:

- `task renovate:validate` → grep `validate:` under `.taskfiles/renovate/` → pass/fail.
- `versions.env`, `renovate.json5` → `test -e kubernetes/platform/versions.env` etc.
- Any `code_paths` entry that fails `test -e` is a stale reference → suggest the
  nearest existing path (`git ls-files | grep <basename>`) or removal.

## Mode Selection

```
IF user names a mode      -> use it
ELSE IF on main branch    -> full
ELSE IF branch ahead of main -> changed
ELSE                      -> full
```

`changed` mode is git-branch-scoped: it diffs `origin/main...HEAD` (falling back to
`main...HEAD`), collects directly-modified docs, then adds any doc that textually
references a changed file or its directory. With no branch changes it returns `[]`.

## Exclusions

Discovery never scans: `.git/`, `node_modules/`, `/tmp/`, and any `*-cache/` directory.
(This repo has no terragrunt — there is no `.terragrunt-cache` exclude.)

## Reporting

Group findings by doc. For each stale reference emit:

- the doc path and the offending reference,
- why it failed (missing path / undefined task / missing skill),
- a suggested fix (nearest existing path, correct task name, or "remove reference").

Order docs by severity: broken `task`/path references users will hit first, then
cosmetic drift. Present the findings list before proposing any edits, and wait for
approval before editing a doc.

## Error Handling

If a validator (or subagent) fails, log it, continue with the rest, mark the affected
references `INCOMPLETE`, and surface them in the report for manual review.
