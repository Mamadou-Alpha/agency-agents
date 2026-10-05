#!/usr/bin/env bash
#
# Validates agent markdown files:
#   1. YAML frontmatter must exist with name, description, color (ERROR)
#   2. Recommended sections checked but only warned (WARN)
#   3. File must have meaningful content
#
# Usage: ./scripts/lint-agents.sh [file ...]
#   If no files given, scans all agent directories.
#
# Implementation note: this used to shell out ~10 times per file (grep/head/
# awk/wc/tr) and crawled on Windows Git Bash, where every fork costs ~50ms
# across 273 files. It now reads each file once and parses with bash builtins
# only. Output messages are byte-identical to the forked version.

set -euo pipefail

# Keep in sync with AGENT_DIRS in scripts/convert.sh
AGENT_DIRS=(
  academic
  design
  engineering
  finance
  game-development
  gis
  healthcare
  marketing
  paid-media
  product
  project-management
  research
  sales
  security
  spatial-computing
  specialized
  support
  testing
)

REQUIRED_FRONTMATTER=("name" "description" "color")
RECOMMENDED_SECTIONS=("Identity" "Core Mission" "Critical Rules")

errors=0
warnings=0

# Sets HEADER_TARGET to "soul" or "agents" (no printf subshell: called once
# per ## header, and a fork per header re-introduced the Windows crawl).
classify_header_target() {
  local header_lower="$1"

  if [[ "$header_lower" =~ identity ]] ||
     [[ "$header_lower" =~ learning.*memory ]] ||
     [[ "$header_lower" =~ communication ]] ||
     [[ "$header_lower" =~ style ]] ||
     [[ "$header_lower" =~ critical.rule ]] ||
     [[ "$header_lower" =~ rules.you.must.follow ]]; then
    HEADER_TARGET='soul'
  else
    HEADER_TARGET='agents'
  fi
}

lint_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "ERROR $file: not a file or does not exist"
    errors=$((errors + 1))
    return
  fi

  # Single builtin read of the whole file; trailing newlines are dropped,
  # which none of the checks below depend on.
  local content
  content="$(<"$file")"

  # 0. Reject CRLF line endings (repo standard is LF — see .gitattributes).
  # A trailing \r otherwise makes the frontmatter check below fail with a
  # confusing "missing frontmatter ---" even when the file clearly starts ---.
  if [[ "$content" == *$'\r'* ]]; then
    echo "ERROR $file: CRLF line endings detected — convert to LF (e.g. 'perl -i -pe \"s/\\r\$//\" $file'); repo uses LF per .gitattributes"
    errors=$((errors + 1))
    return
  fi

  # 1. Check frontmatter delimiters
  local first_line="${content%%$'\n'*}"
  if [[ "$first_line" != "---" ]]; then
    echo "ERROR $file: missing frontmatter opening ---"
    errors=$((errors + 1))
    return
  fi

  # Extract frontmatter (between first and second ---) and the body after it.
  local rest="${content#*$'\n'}"
  local frontmatter="" body=""
  if [[ "$rest" == *$'\n---\n'* ]]; then
    frontmatter="${rest%%$'\n---\n'*}"
    body="${rest#*$'\n---\n'}"
  elif [[ "$rest" == *$'\n---' ]]; then
    frontmatter="${rest%$'\n---'}"
  fi

  if [[ -z "$frontmatter" ]]; then
    echo "ERROR $file: empty or malformed frontmatter"
    errors=$((errors + 1))
    return
  fi

  # 2. Check required frontmatter fields (at a line start of the frontmatter)
  local field
  for field in "${REQUIRED_FRONTMATTER[@]}"; do
    if [[ "$frontmatter" != "$field:"* && "$frontmatter" != *$'\n'"$field:"* ]]; then
      echo "ERROR $file: missing frontmatter field '${field}'"
      errors=$((errors + 1))
    fi
  done

  # 3. Check recommended sections (warn only)
  local section lower_body="${body,,}" lower_section
  for section in "${RECOMMENDED_SECTIONS[@]}"; do
    lower_section="${section,,}"
    if [[ "$lower_body" != *"$lower_section"* ]]; then
      echo "WARN  $file: missing recommended section '${section}'"
      warnings=$((warnings + 1))
    fi
  done

  # 4. Check file has meaningful content (unquoted split = wc -w semantics)
  local word_count=0 w
  for w in $body; do
    word_count=$((word_count + 1))
  done
  if [[ "${word_count:-0}" -lt 50 ]]; then
    echo "WARN  $file: body seems very short (< 50 words)"
    warnings=$((warnings + 1))
  fi

  local soul_headers=0
  local agents_headers=0
  while IFS= read -r line; do
    if [[ "$line" == '## '* || "$line" == $'##\t'* ]]; then
      classify_header_target "${line,,}"
      if [[ "$HEADER_TARGET" == "soul" ]]; then
        soul_headers=$((soul_headers + 1))
      else
        agents_headers=$((agents_headers + 1))
      fi
    fi
  done <<< "$body"

  if [[ $soul_headers -eq 0 ]]; then
    echo "WARN  $file: no section headers map to SOUL.md in convert.sh"
    warnings=$((warnings + 1))
  fi

  if [[ $agents_headers -eq 0 ]]; then
    echo "WARN  $file: no section headers map to AGENTS.md in convert.sh"
    warnings=$((warnings + 1))
  fi
}

# Collect files to lint
files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  for dir in "${AGENT_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
      while IFS= read -r f; do
        files+=("$f")
      done < <(find "$dir" -name "*.md" -type f | sort)
    fi
  done
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No agent files found."
  exit 1
fi

echo "Linting ${#files[@]} agent files..."
echo ""

for file in "${files[@]}"; do
  lint_file "$file"
done

echo ""
echo "Results: ${errors} error(s), ${warnings} warning(s) in ${#files[@]} files."

if [[ $errors -gt 0 ]]; then
  echo "FAILED: fix the errors above before merging."
  exit 1
else
  echo "PASSED"
  exit 0
fi
