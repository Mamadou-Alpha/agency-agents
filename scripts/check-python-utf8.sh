#!/usr/bin/env bash
#
# check-python-utf8.sh — Fail on any Python text-I/O call that would use the
# platform-locale encoding ('cp1252' on Windows, 'utf-8' on Linux). That is how
# a script that passes CI can still crash the moment someone runs it on
# Windows: check-hermes-config-rewrite.py shipped exactly this bug.
#
# Rules (skip comment-only lines; a trailing "# utf8-ok" opts a line out):
#   - "open(" with no encoding= on the line
#       (exempt when a binary mode string is also present: rb/wb/ab/xb)
#   - ".read_text(" with no encoding=
#   - ".write_text(" with no encoding=
#   - "text=True" with no encoding=   (subprocess pipes decode with the locale)
#
# Known limitation: a multi-line call payload (open spelled across several
# lines) may be missed; the common crash pattern is a single-line call.
#
# Usage: scripts/check-python-utf8.sh [file ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  while IFS= read -r rel; do
    files+=("scripts/${rel#./}")
  done < <(cd "$REPO_ROOT/scripts" 2>/dev/null && find . -name '*.py' -type f | sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "PASSED: no Python files to scan."
  exit 0
fi

violations=0
for rel in "${files[@]}"; do
  path="$REPO_ROOT/$rel"
  if [[ ! -f "$path" ]]; then
    echo "ERROR $rel: not a file"
    violations=$((violations + 1))
    continue
  fi

  # Join continuation lines (unbalanced parens) into logical lines, so a call
  # spelled across several lines still sees its encoding= argument. Strings or
  # comments containing parentheses can skew the balance; heuristic by design.
  mapfile -t phys < <(LC_ALL=C grep -v '^[[:space:]]*#' "$path" | tr -d '\r')
  i=0
  while (( i < ${#phys[@]} )); do
    line="${phys[$i]}"
    logical="$line"
    # Bare ( or ) inside $(( )) breaks bash parsing — keep them in quoted vars.
    op='(' cl=')'
    no_open="${logical//"$op"/}" no_close="${logical//"$cl"/}"
    opens=$(( ${#logical} - ${#no_open} ))
    closes=$(( ${#logical} - ${#no_close} ))
    while (( opens != closes )) && (( i + 1 < ${#phys[@]} )); do
      i=$((i + 1))
      logical="$logical ${phys[$i]}"
      no_open="${logical//"$op"/}" no_close="${logical//"$cl"/}"
      opens=$(( ${#logical} - ${#no_open} ))
      closes=$(( ${#logical} - ${#no_close} ))
    done
    i=$((i + 1))
    line="$logical"
    [[ "$line" =~ utf8-ok ]] && continue
    has_enc=0
    [[ "$line" =~ encoding[[:space:]]*= ]] && has_enc=1

    flag() {
      local rule="$1"
      echo "ERROR $rel: $rule without explicit encoding= (locale-dependent): $line"
      violations=$((violations + 1))
    }

    # open( — exempt if a binary mode arg appears on the line.
    if [[ "$line" =~ (^|[^A-Za-z0-9_.])open[[:space:]]*\( ]]; then
      if [[ "$line" =~ [\'\"](rb|wb|ab|xb|rb\+|wb\+|ab\+|xb\+|br|bw|ba|bx)[\'\"] ]]; then
        :
      elif [[ $has_enc -eq 0 ]]; then
        flag "open()"
      fi
    fi

    [[ "$line" =~ \.(read_text|write_text)[[:space:]]*\( ]] && [[ $has_enc -eq 0 ]] \
      && flag "${BASH_REMATCH[1]}()"
    [[ "$line" =~ text[[:space:]]*=[[:space:]]*True ]] && [[ $has_enc -eq 0 ]] && flag "subprocess text=True"
  done
done

if [[ $violations -gt 0 ]]; then
  echo ""
  echo "FAILED: $violations locale-dependent I/O call(s). Pass encoding=\"utf-8\""
  echo "explicitly (see check-hermes-config-rewrite.py history)."
  exit 1
fi
echo "PASSED: all text-mode I/O calls specify encoding=."
