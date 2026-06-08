---
name: instruction-eval
description: |
  Regression-test the behavior of this repo's skills and CLAUDE.md against their tests.yaml probe files.
  Run after trimming or refactoring a skill, before opening a PR that touches skills/CLAUDE.md, or as a
  periodic hygiene check to confirm hard constraints still hold and skills still route correctly.

  Use when: (1) after editing or trimming a SKILL.md, (2) verifying a skill still enforces its constraints,
  (3) checking that a CLAUDE.md change did not break behavior, (4) adding a new probe to a skill's tests.yaml,
  (5) running the automated eval against the Anthropic API.

  Triggers: "test instructions", "regression test skills", "evaluate skill", "did trimming break anything",
  "run eval", "instruction eval", "tests.yaml", "score probes", "probe", "validate claude posture",
  "skill regression", "check constraints"
user-invocable: true
---

# Instruction Evaluation

Regression-tests skill / CLAUDE.md behavior against per-skill `tests.yaml` probe files. Two modes:
**spot-check** (manual, in a fresh session) and **automated** (`scripts/run-eval.py` against the Anthropic API).

## Where probes live

- `.agents/skills/<name>/tests.yaml` — canonical per-skill probes (every skill here has one).
- `.claude/tests.yaml` — optional, top-level CLAUDE.md probes (handled gracefully if absent).
- `.claude/skills/<name>` are symlinks into `.agents/skills/`, so the canonical glob is `.agents/skills/*/tests.yaml`.

## Probe schema

Probes follow the house format already used by every skill (see `versions-renovate/tests.yaml`):

```yaml
version: 1
skill: <skill-name>
tests:
  - id: ABC-01                 # unique, domain-prefixed (VER-, EVL-, K8S-, ...)
    description: "..."          # what this probe checks
    category: constraint        # constraint | coverage | routing
    severity: critical          # critical | high | medium
    prompt: |                   # the scenario posed to Claude
      ...
    scoring:
      mode: keywords
      keywords:
        required:  ["a", "b"]   # ALL must appear in the response
        any_of:    ["x", "y"]   # at least ONE must appear (optional group)
        forbidden: ["z"]        # NONE may appear
    expect_refusal: false
    manual_review: false        # if true, a PASS is flagged for human eyes
    expected_behavior: |        # human-readable pass criteria
      ...
    tags: ["<skill>-skill"]
```

Keyword matching is case-insensitive substring matching.

## Scoring rubric

Each probe scores against the keyword groups, in this order:

- **FAIL** — any `forbidden` keyword is present (checked first, short-circuits everything).
- **PASS** — ALL `required` keywords present AND (`any_of` empty OR ≥1 `any_of` present) AND no `forbidden`.
- **PARTIAL** — some but not all `required` present (and no `forbidden`); needs human review.
- **FAIL** — no `required` keywords present at all.

If a probe has no `required` keywords, it falls back to legacy `any_of` thresholds: ≥2 matches PASS, 1 PARTIAL, 0 FAIL.

## Mode 1 — Spot-check (manual)

In a **fresh** session (no accumulated context), work through a skill's probes by hand:

1. Pose the probe's `prompt` exactly as written.
2. Capture the response.
3. Score it: all `required` present? ≥1 `any_of`? no `forbidden`?
4. Mark PASS / PARTIAL / FAIL and note the failure mode.

What to watch for:
- **Silent gaps** — confident but wrong answer because trimmed content was never replaced.
- **Broken routing** — the skill that should cover the topic doesn't trigger.
- **Constraint drift** — Claude complies with something a skill says to refuse or do differently.

## Mode 2 — Automated (`scripts/run-eval.py`)

Discovers all `tests.yaml` files, sends each probe to the Anthropic API, and scores responses.

```bash
# Deps (Python via mise): anthropic SDK + pyyaml
pip install anthropic pyyaml
export ANTHROPIC_API_KEY=...        # required

# Run everything
./.agents/skills/instruction-eval/scripts/run-eval.py

# Scope it
./.agents/skills/instruction-eval/scripts/run-eval.py --skill versions-renovate
./.agents/skills/instruction-eval/scripts/run-eval.py --category constraint
./.agents/skills/instruction-eval/scripts/run-eval.py --probe VER-01

# List probes without running (no API calls)
./.agents/skills/instruction-eval/scripts/run-eval.py --list

# JSON report for CI
./.agents/skills/instruction-eval/scripts/run-eval.py --json > eval-report.json
```

**Model:** default judge/target is `claude-haiku-4-5` (cheap). Override with `--model <id>` or the
`ANTHROPIC_MODEL` env var. The script reads `ANTHROPIC_API_KEY` from the environment and exits non-zero
if any probe FAILs or ERRORs (CI-friendly).

## Interpreting results

| Signal | Likely cause | Action |
|-|-|-|
| Constraint probe FAILs | A skill's hard rule was trimmed or weakened | Restore the rule to the SKILL.md |
| Routing probe FAILs | Skill `description:` no longer triggers on this phrasing | Update the frontmatter triggers |
| Coverage probe FAILs | Removed content had no replacement | Restore to the authoritative location |
| PARTIAL | Some required keywords missing | Read the response; tighten the skill or the probe |
| All PASS | Change was safe | Proceed |

## When to run

- Before opening a PR that touches any SKILL.md or CLAUDE.md.
- After a batch trimming/refactor of skills.
- Periodically as a hygiene check.
- When behavior regresses unexpectedly.

## Adding probes

- Skill change → add a probe to that skill's `.agents/skills/<name>/tests.yaml`.
- CLAUDE.md change → add a probe to `.claude/tests.yaml` (create it if missing) with a domain-prefixed id.

Keep probes deterministic: pick `required` keywords that a correct answer must contain verbatim, and
`forbidden` keywords that only a wrong answer would produce.
