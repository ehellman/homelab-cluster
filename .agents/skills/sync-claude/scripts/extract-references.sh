#!/usr/bin/env bash
# Extract references from one Claude doc (CLAUDE.md or a SKILL.md).
# Outputs categorized JSON: markdown links, code paths, task commands,
# skill references, and bare file/dir paths.
# Usage: extract-references.sh <file_path>

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <file_path>" >&2
    exit 1
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
    echo "File not found: $FILE" >&2
    exit 1
fi

CONTENT=$(cat "$FILE")

# Markdown links [text](path) — local targets only.
extract_md_links() {
    echo "$CONTENT" \
        | grep -oE '\]\([^)]+\)' \
        | sed -E 's/^\]\(//; s/\)$//' \
        | grep -vE '^(https?:|#|mailto:)' \
        | sort -u || true
}

# Stack paths likely to resolve against the working tree.
extract_code_paths() {
    echo "$CONTENT" \
        | grep -oE '(kubernetes|\.agents|\.taskfiles|\.github|talos|bootstrap|docs)/[a-zA-Z0-9_./-]+' \
        | sed -E 's/[.,:;)"'"'"'`]+$//' \
        | sort -u || true
}

# `task <name>` invocations (namespaced names allowed: template:validate-schemas).
extract_task_commands() {
    echo "$CONTENT" \
        | grep -oE 'task [a-zA-Z0-9:_-]+' \
        | sed 's/^task //' \
        | sort -u || true
}

# Referenced skills: `name` near the word "skill", plus .agents/skills/<name>.
extract_skill_refs() {
    {
        echo "$CONTENT" | grep -oE '\.agents/skills/[a-zA-Z0-9-]+' | sed 's#.*/##'
        echo "$CONTENT" \
            | grep -oiE '`[a-zA-Z0-9-]+` skill|skill[^`]*`[a-zA-Z0-9-]+`' \
            | grep -oE '`[a-zA-Z0-9-]+`' | tr -d '`'
    } | sort -u || true
}

# Notable repo config files referenced inline.
extract_config_refs() {
    echo "$CONTENT" \
        | grep -oE '\.mcp\.json|Taskfile\.yaml|versions\.env|renovate\.json5|\.sops\.yaml' \
        | sort -u || true
}

to_json_array() {
    jq -R -s 'split("\n") | map(select(length > 0)) | unique'
}

jq -n \
    --arg file "$FILE" \
    --argjson md_links "$(extract_md_links | to_json_array)" \
    --argjson code_paths "$(extract_code_paths | to_json_array)" \
    --argjson task_commands "$(extract_task_commands | to_json_array)" \
    --argjson skill_refs "$(extract_skill_refs | to_json_array)" \
    --argjson config_refs "$(extract_config_refs | to_json_array)" \
    '{
        file: $file,
        markdown_links: $md_links,
        code_paths: $code_paths,
        task_commands: $task_commands,
        skill_references: $skill_refs,
        config_references: $config_refs
    }'
