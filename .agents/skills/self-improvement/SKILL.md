---
name: self-improvement
description: |
  Capture durable user feedback and corrections, then persist them into the right
  place: an existing SKILL.md, the repo CLAUDE.md, or a brand-new skill.

  Use when: (1) User says "remember this" / "you should know" / "document this",
  (2) User gives an always/never rule or a preference, (3) User corrects an approach
  mid-task, (4) New patterns emerge during work that future sessions need,
  (5) User explicitly asks to update a skill or CLAUDE.md.

  Triggers: "remember this", "update the skill", "you should know", "in the future",
  "always do", "never do", "that's wrong", "actually it should be", "document this",
  "add to CLAUDE.md", "capture this", "/self-improvement"
user-invocable: false
---

# Self-Improvement

Turn durable feedback into persistent repo knowledge. This operationalizes the
global rule "when corrected, ask if the correction should be persisted."

Knowledge captured during work should land in the same branch as the work that
revealed it, not a separate cleanup PR.

## Workflow

1. Classify the feedback (durability + target).
2. Confirm with the user before writing anything.
3. Apply the edit (or scaffold a new skill + symlink).
4. Add or adjust a `tests.yaml` probe so the change is regression-tested.
5. Suggest committing on a branch/PR — never commit to `main` directly.

## Phase 1: Classify

First decide durability. Skip silently if one-off.

| Signal | Durability | Target |
|-|-|-|
| "do it this way just now" | One-off | None — do not persist |
| "that's wrong" / "actually..." | Durable | Source of the wrong info |
| "you should also know..." | Durable | Related existing section |
| "when doing X, always Y" | Durable | Specific skill or CLAUDE.md |
| "never do X" | Durable | Repo `CLAUDE.md` |
| "I prefer..." / "always use..." | Durable | Repo `CLAUDE.md` |
| procedural workflow, 5+ steps | Durable | New or existing skill |

Then pick the target file:

```
Correcting existing docs?            -> update that source
Universal repo rule / preference?    -> CLAUDE.md
Specific to one subsystem/tool?      -> that subsystem's SKILL.md
Reusable 5+ step procedure?          -> new skill (see Phase 3b)
Otherwise (quick fact/pattern)?      -> CLAUDE.md
```

This repo's skills:

```
.agents/skills/<name>/SKILL.md      <- real file (frontmatter + body)
.agents/skills/<name>/tests.yaml    <- regression probes
.claude/skills/<name>               <- symlink -> ../../.agents/skills/<name>
```

Use Grep across `.agents/skills/` and `CLAUDE.md` to find where the topic already
lives before deciding to create something new. Prefer extending over adding.

## Phase 2: Confirm

ALWAYS confirm before writing. Present:
1. The classified feedback and chosen target file.
2. A preview of the exact change (the lines to add/modify).
3. Alternatives if the target is ambiguous.

If placement is uncertain, ask — do not guess. Wait for an explicit yes before editing.

## Phase 3a: Apply to an existing file

- **CLAUDE.md / SKILL.md**: Read it, find the matching section, add content in the
  existing terse style (tables with `|-|-|` separators, no box-drawing characters).
- **Correction**: Grep for every occurrence of the wrong info and fix all of them,
  then verify no cross-reference broke.

## Phase 3b: Scaffold a new skill

```bash
name=<skill-name>
mkdir -p .agents/skills/$name
# write .agents/skills/$name/SKILL.md  (frontmatter: name + trigger-rich description)
# write .agents/skills/$name/tests.yaml
ln -s ../../.agents/skills/$name .claude/skills/$name
ls -l .claude/skills/$name   # verify symlink resolves
```

Match the frontmatter shape of a sibling skill (e.g. `versions-renovate`): `name`,
a `description` with numbered "Use when" cases and a `Triggers:` line, and
`user-invocable: false` unless the user wants to invoke it by slash command.

## Phase 4: Regression test

Add a probe to the target skill's `tests.yaml` so the new behavior is checked.
Follow the `versions-renovate` format: `id`, `description`, `category`, `severity`,
`prompt`, `scoring` (mode `keywords` with `required`/`forbidden`/`any_of`),
`expect_refusal`, `expected_behavior`, `tags`. Keep prompts realistic and scoped to
the one behavior the feedback introduced.

For a CLAUDE.md-only change, a test is usually unnecessary — note that and move on.

## Phase 5: Commit

Suggest a branch + PR. Never commit to `main`. Group the doc/skill change with the
related code change in the same branch when one exists.

```bash
git switch -c docs/<short-topic>
git add .agents/skills/<name> .claude/skills/<name> CLAUDE.md
git commit -m "docs(skill): <what was captured>"
```
