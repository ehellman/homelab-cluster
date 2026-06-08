#!/usr/bin/env bash
# Discover Claude documentation files in the homelab repo.
# Docs = repo-root CLAUDE.md + every .agents/skills/<name>/SKILL.md.
# Outputs a JSON array of repo-relative paths.
# Usage: discover-claude-docs.sh [full|changed]   (default: full)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Directories never scanned (no terragrunt here; homelab excludes instead).
EXCLUDE_PATTERNS=(
    -not -path "*/.git/*"
    -not -path "*/node_modules/*"
    -not -path "*/tmp/*"
    -not -path "*-cache/*"
)

is_excluded() {
    case "$1" in
        */.git/* | */node_modules/* | */tmp/* | *-cache/*) return 0 ;;
        *) return 1 ;;
    esac
}

discover_all_docs() {
    local docs=()

    # Repo-root CLAUDE.md (only the root one is a Claude doc here).
    [[ -f CLAUDE.md ]] && docs+=("CLAUDE.md")

    # Every skill SKILL.md (source of truth lives in .agents/skills/).
    while IFS= read -r -d '' file; do
        docs+=("${file#./}")
    done < <(find ./.agents/skills -name "SKILL.md" "${EXCLUDE_PATTERNS[@]}" -print0 2>/dev/null || true)

    printf '%s\n' "${docs[@]}" | jq -R -s 'split("\n") | map(select(length > 0)) | unique'
}

discover_changed_docs() {
    local changed_files
    local impacted_docs=()

    # Files touched on the current branch vs main.
    changed_files=$(git diff --name-only origin/main...HEAD 2>/dev/null \
        || git diff --name-only main...HEAD 2>/dev/null \
        || echo "")

    if [[ -z "$changed_files" ]]; then
        echo "[]"
        return
    fi

    # Directly modified Claude docs.
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        is_excluded "$file" && continue
        if [[ "$file" == "CLAUDE.md" || "$file" == *"/SKILL.md" ]]; then
            impacted_docs+=("$file")
        fi
    done <<< "$changed_files"

    # Docs that reference a changed file or its directory (smart detection).
    local all_docs
    all_docs=$(discover_all_docs)

    while IFS= read -r changed_file; do
        [[ -z "$changed_file" ]] && continue
        local changed_dir
        changed_dir=$(dirname "$changed_file")
        while IFS= read -r doc; do
            [[ -f "$doc" ]] || continue
            if grep -qF -e "$changed_file" -e "$changed_dir" "$doc" 2>/dev/null; then
                impacted_docs+=("$doc")
            fi
        done < <(echo "$all_docs" | jq -r '.[]')
    done <<< "$changed_files"

    printf '%s\n' "${impacted_docs[@]}" | sort -u \
        | jq -R -s 'split("\n") | map(select(length > 0))'
}

MODE="${1:-full}"
case "$MODE" in
    changed) discover_changed_docs ;;
    full | "") discover_all_docs ;;
    *)
        echo "Unknown mode: $MODE (use full|changed)" >&2
        exit 1
        ;;
esac
