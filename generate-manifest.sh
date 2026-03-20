#!/usr/bin/env bash
#
# generate-manifest.sh - Generate MANIFEST.json from git-tracked files
#
# Reads VERSION from the repo root and computes SHA-256 hashes for all
# git-tracked files. Each file is tagged with an install mode:
#
#   always  - overwrite on every install/update (tooling, schemas, workflows)
#   seed    - only copy if the file doesn't exist (docs, agents, tasks — user-owned)
#   skip    - never installed (repo metadata like LICENSE, README, .gitignore)
#
# The manifest is the source of truth for the installer.
#
# Usage:
#   ./generate-manifest.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$REPO_ROOT/MANIFEST.json"
VERSION=$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Files/patterns that are always overwritten on install/update
is_always() {
    local f="$1"
    case "$f" in
        tooling/*) return 0 ;;
        schemas/*) return 0 ;;
        VERSION) return 0 ;;
        planning/boards/*) return 0 ;;
    esac
    return 1
}

# Files/patterns that are never installed
is_skip() {
    local f="$1"
    case "$f" in
        LICENSE) return 0 ;;
        README.md) return 0 ;;
        .gitignore) return 0 ;;
        MANIFEST.json) return 0 ;;
        generate-manifest.sh) return 0 ;;
    esac
    return 1
}

cd "$REPO_ROOT"

# Build JSON
{
    printf '{\n'
    printf '  "version": "%s",\n' "$VERSION"
    printf '  "generated_at": "%s",\n' "$GENERATED_AT"
    printf '  "files": {\n'

    first=true
    git ls-files | sort | while IFS= read -r filepath; do
        # Skip the manifest itself and this script
        if is_skip "$filepath"; then
            continue
        fi

        # Skip directories (.gitkeep files are fine)
        [ -f "$filepath" ] || continue

        # Compute hash
        hash=$(shasum -a 256 "$filepath" | cut -d' ' -f1)

        # Determine install mode
        if is_always "$filepath"; then
            mode="always"
        else
            mode="seed"
        fi

        if [ "$first" = true ]; then
            first=false
        else
            printf ',\n'
        fi
        printf '    "%s": {\n      "hash": "sha256:%s",\n      "install": "%s"\n    }' "$filepath" "$hash" "$mode"
    done

    printf '\n  }\n'
    printf '}\n'
} > "$MANIFEST"

echo "Generated $MANIFEST (version $VERSION)"
