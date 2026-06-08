#!/usr/bin/env python3
"""
Instruction evaluation script — regression-tests Claude's operational posture
after skill / CLAUDE.md changes in this homelab repo.

Discovers test cases automatically from:
  .agents/skills/*/tests.yaml   — per-skill behavioral probes (canonical location)
  .claude/tests.yaml            — optional CLAUDE.md behavioral probes (if present)

Usage:
    ./run-eval.py                            # Run all probes
    ./run-eval.py --skill versions-renovate  # Only probes for one skill
    ./run-eval.py --category constraint      # One category across all skills
    ./run-eval.py --probe VER-01             # Single probe by ID
    ./run-eval.py --list                     # List discovered probes, don't run
    ./run-eval.py --json                     # JSON report for CI
    ./run-eval.py --model claude-sonnet-4-6  # Override target/judge model

Environment:
    ANTHROPIC_API_KEY  Required.
    ANTHROPIC_MODEL    Optional. Default model id (overridden by --model).
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

# Cheap, current default. Override with --model or ANTHROPIC_MODEL.
DEFAULT_MODEL = "claude-haiku-4-5"

try:
    import anthropic
except ImportError:
    print("ERROR: anthropic package not installed. Run: pip install anthropic")
    sys.exit(1)

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml package not installed. Run: pip install pyyaml")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Test discovery and loading
# ---------------------------------------------------------------------------

def find_repo_root() -> Path:
    """Walk up from this script's location to find the repo root (.git)."""
    for parent in Path(__file__).resolve().parents:
        if (parent / ".git").exists():
            return parent
    raise RuntimeError("Could not find repo root (no .git directory found)")


def discover_test_files(repo_root: Path) -> list[Path]:
    """
    Discover all tests.yaml files in order:
      1. .claude/tests.yaml         (optional CLAUDE.md behavioral tests)
      2. .agents/skills/*/tests.yaml (per-skill tests, sorted by skill name)
    """
    files = []

    top_level = repo_root / ".claude" / "tests.yaml"
    if top_level.exists():
        files.append(top_level)

    skills_dir = repo_root / ".agents" / "skills"
    if skills_dir.exists():
        for skill_dir in sorted(skills_dir.iterdir()):
            if skill_dir.is_dir():
                skill_tests = skill_dir / "tests.yaml"
                if skill_tests.exists():
                    files.append(skill_tests)

    return files


def load_tests(files: list[Path]) -> list[dict]:
    """Load and normalize all test cases from discovered files."""
    tests = []
    for path in files:
        with open(path) as f:
            data = yaml.safe_load(f)

        skill_name = data.get("skill", path.parent.name)
        for test in data.get("tests", []):
            test["_skill"] = skill_name
            test["_source"] = str(path)
            tests.append(test)

    return tests


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

def score_response(response_text: str, test: dict) -> tuple[str, dict]:
    """
    Score a response against test criteria (keywords mode).

      - FAIL immediately if any forbidden keyword is present
      - PASS if all required keywords match AND (any_of empty OR >=1 any_of matches)
      - PARTIAL if some (not all) required keywords match and no forbidden triggered
      - FAIL if no required keywords match

    Returns (PASS|PARTIAL|FAIL, details_dict).
    """
    scoring = test.get("scoring", {})
    keywords = scoring.get("keywords", {})
    text_lower = response_text.lower()

    if isinstance(keywords, dict):
        required = keywords.get("required", [])
        any_of = keywords.get("any_of", [])
        forbidden = keywords.get("forbidden", [])
    else:
        # Legacy flat list: 2+ matches = PASS, 1 = PARTIAL, 0 = FAIL
        required = []
        any_of = list(keywords)
        forbidden = []

    required_matched = [kw for kw in required if kw.lower() in text_lower]
    required_missing = [kw for kw in required if kw.lower() not in text_lower]
    any_matched = [kw for kw in any_of if kw.lower() in text_lower]
    forbidden_matched = [kw for kw in forbidden if kw.lower() in text_lower]

    details = {
        "required_matched": required_matched,
        "required_missing": required_missing,
        "any_matched": any_matched,
        "forbidden_matched": forbidden_matched,
    }

    if forbidden_matched:
        return "FAIL", details

    if required:
        if not required_missing:
            if not any_of or any_matched:
                return "PASS", details
            return "PARTIAL", details  # required met but any_of unsatisfied
        return ("PARTIAL" if required_matched else "FAIL"), details

    # No required keywords — legacy any_of threshold (2+ = PASS)
    if len(any_matched) >= 2:
        return "PASS", details
    if len(any_matched) == 1:
        return "PARTIAL", details
    return "FAIL", details


# ---------------------------------------------------------------------------
# Probe execution
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = (
    "You are Claude Code operating in a GitOps-driven Kubernetes homelab repository. "
    "The cluster runs Talos Linux, Flux, Cilium, and SOPS-encrypted secrets. "
    "Platform versions live in kubernetes/platform/versions.env and are tracked by "
    "Renovate via custom regex annotations. You have access to the project's CLAUDE.md "
    "files and skills. Answer based on the homelab's established patterns and constraints."
)


def run_probe(client: anthropic.Anthropic, test: dict, model: str) -> dict:
    """Run a single probe and return result dict."""
    try:
        msg = client.messages.create(
            model=model,
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": test["prompt"]}],
        )
        response_text = msg.content[0].text
        status, details = score_response(response_text, test)
    except Exception as e:
        response_text = f"ERROR: {e}"
        status = "ERROR"
        details = {}

    return {
        "id": test["id"],
        "skill": test.get("_skill", "unknown"),
        "category": test.get("category", "unknown"),
        "severity": test.get("severity", "unknown"),
        "description": test.get("description", ""),
        "status": status,
        "manual_review": test.get("manual_review", False),
        "details": details,
        "response_snippet": response_text[:400],
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Evaluate Claude instruction posture")
    parser.add_argument("--skill", help="Run probes for one skill (e.g. versions-renovate)")
    parser.add_argument("--category", help="Run one category only (e.g. constraint, coverage)")
    parser.add_argument("--probe", help="Run a single probe by ID (e.g. VER-01)")
    parser.add_argument(
        "--model",
        default=os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL),
        help=f"Model to test against (default: {DEFAULT_MODEL}, or $ANTHROPIC_MODEL)",
    )
    parser.add_argument("--json", action="store_true", help="Output JSON report")
    parser.add_argument("--delay", type=float, default=1.0, help="Seconds between API calls")
    parser.add_argument("--list", action="store_true", help="List discovered probes without running")
    args = parser.parse_args()

    repo_root = find_repo_root()
    test_files = discover_test_files(repo_root)

    if not test_files:
        print("ERROR: No tests.yaml files found under .agents/skills/ or .claude/")
        sys.exit(1)

    all_tests = load_tests(test_files)

    if not all_tests:
        print("ERROR: No test cases loaded")
        sys.exit(1)

    # Filter
    tests = all_tests
    if args.probe:
        tests = [t for t in tests if t["id"] == args.probe]
        if not tests:
            print(f"ERROR: Probe '{args.probe}' not found")
            sys.exit(1)
    elif args.skill:
        tests = [t for t in tests if t.get("_skill") == args.skill]
        if not tests:
            available = sorted({t.get("_skill") for t in all_tests})
            print(f"ERROR: No tests for skill '{args.skill}'. Available: {available}")
            sys.exit(1)
    elif args.category:
        tests = [t for t in tests if t.get("category") == args.category]
        if not tests:
            available = sorted({t.get("category") for t in all_tests})
            print(f"ERROR: No tests for category '{args.category}'. Available: {available}")
            sys.exit(1)

    # List mode
    if args.list:
        for t in tests:
            print(f"[{t['id']}] ({t.get('_skill')}/{t.get('category')}/{t.get('severity')}) {t.get('description')}")
        print(f"\n{len(tests)} probe(s) from {len(test_files)} file(s)")
        return

    # Run
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ERROR: ANTHROPIC_API_KEY not set")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    if not args.json:
        print(f"\n{'=' * 60}")
        print(f"Instruction Evaluation — {args.model}")
        print(f"Running {len(tests)} probe(s) from {len(test_files)} file(s)")
        print(f"{'=' * 60}\n")

    results = []
    for i, test in enumerate(tests):
        if not args.json:
            print(f"[{test['id']}] {test.get('description', '')}...", end=" ", flush=True)

        result = run_probe(client, test, args.model)
        results.append(result)

        if not args.json:
            icon = {"PASS": "PASS", "PARTIAL": "PARTIAL", "FAIL": "FAIL", "ERROR": "ERROR"}.get(result["status"], "?")
            suffix = " (manual review)" if result.get("manual_review") and result["status"] == "PASS" else ""
            print(f"{icon}{suffix}")
            if result["status"] in ("PARTIAL", "FAIL"):
                d = result.get("details", {})
                if d.get("required_missing"):
                    print(f"    Missing required: {d['required_missing']}")
                if d.get("forbidden_matched"):
                    print(f"    Forbidden found:  {d['forbidden_matched']}")
                print(f"    Response: {result['response_snippet'][:200]}...")

        if i < len(tests) - 1:
            time.sleep(args.delay)

    counts = {s: sum(1 for r in results if r["status"] == s) for s in ("PASS", "PARTIAL", "FAIL", "ERROR")}
    manual_needed = sum(1 for r in results if r.get("manual_review") and r["status"] == "PASS")

    if args.json:
        print(json.dumps({
            "model": args.model,
            "total": len(results),
            "counts": counts,
            "manual_review_needed": manual_needed,
            "results": results,
        }, indent=2))
    else:
        print(f"\n{'=' * 60}")
        print(f"SUMMARY: {counts['PASS']} PASS  {counts['PARTIAL']} PARTIAL  {counts['FAIL']} FAIL  {counts['ERROR']} ERROR")
        if manual_needed:
            print(f"  {manual_needed} PASS probe(s) flagged manual_review")
        print(f"Total: {len(results)} probes")

        if counts["FAIL"] > 0 or counts["ERROR"] > 0:
            print("\nFailed probes:")
            for r in results:
                if r["status"] in ("FAIL", "ERROR"):
                    print(f"  [{r['id']}] {r['description']}")
            sys.exit(1)

        if counts["PARTIAL"] == 0:
            print("\nAll probes passed.")
        else:
            print("\nPartial matches need manual review.")


if __name__ == "__main__":
    main()
