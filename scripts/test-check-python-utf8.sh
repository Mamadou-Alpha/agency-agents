#!/usr/bin/env bash
#
# test-check-python-utf8.sh — Self-test for check-python-utf8.sh.
#
# Violation-fixtures MUST make the guard exit non-zero (one expected ERROR
# message each), and a compliant fixture MUST pass with exit 0, including
# binary-mode open and the "# utf8-ok" opt-out.
#
# Keeps ISO-8859-1 text out of the fixtures; no non-ASCII needed here.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
guard="$script_dir/check-python-utf8.sh"
# The guard resolves every argument against the repo root, so fixtures must
# live at repo-root-relative paths. Relative temp keeps absolute /tmp out.
cd "$repo_root"
tmp=".tmp-utf8-guard-test"
rm -rf "$tmp"
mkdir -p "$tmp"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

# Violation fixtures: name|expected-ERROR-fragment
violations=(
  "open-txt|open()"
  "read-txt|read_text()"
  "write-txt|write_text()"
  "sub-txt|text=True"
)
mkdir "$tmp/bad" && touch "$tmp/bad/__init__.py"
printf 'f = open("x.txt")\n'                       > "$tmp/bad/01-open-txt.py"
printf 'from pathlib import Path\n'                > "$tmp/bad/02-read-txt.py"
printf 'Path("x").read_text(data)\n'              >> "$tmp/bad/02-read-txt.py"
printf 'from pathlib import Path\n'                > "$tmp/bad/03-write-txt.py"
printf 'Path("x").write_text(data)\n'             >> "$tmp/bad/03-write-txt.py"
printf 'run(cmd, capture_output=True, text=True)\n' > "$tmp/bad/04-sub-txt.py"

if bash "$guard" "$tmp"/bad/*.py >"$tmp/bad.out" 2>&1; then
  echo "FAIL: guard unexpectedly passed on violation fixtures"
  cat "$tmp/bad.out"
  exit 1
fi
for spec in "${violations[@]}"; do
  frag="${spec#*|}"
  if ! grep -q "$frag" "$tmp/bad.out"; then
    echo "FAIL: guard output missing ERROR for pattern '$frag'"
    cat "$tmp/bad.out"
    exit 1
  fi
done

# Compliant fixture: same patterns with explicit encodings + opt-outs.
mkdir "$tmp/good" && touch "$tmp/good/__init__.py"
cat > "$tmp/good/ok.py" <<'PY'
from pathlib import Path

with open("f.yaml", encoding="utf-8") as fh:
    data = fh.read()
Path("f.yaml").write_text(data, encoding="utf-8")
Path("blob.png").write_bytes(raw)
with open("raw.bin", "rb") as fh:
    blob = fh.read()
run(cmd, text=True, encoding="utf-8", capture_output=True)
with open("leg.bin", "wb") as fh:
    fh.write(raw)
open("opt.txt")  # utf8-ok
PY

if ! bash "$guard" "$tmp"/good/ok.py >"$tmp/good.out" 2>&1; then
  echo "FAIL: guard rejected compliant fixture"
  cat "$tmp/good.out"
  exit 1
fi

echo "PASS: guard flags violations, accepts compliant code"
