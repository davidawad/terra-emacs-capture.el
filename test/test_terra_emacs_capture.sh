#!/usr/bin/env bash
# test_terra_emacs_capture.sh -- terra-emacs-capture's ERT suites, one
# batch Emacs at a time, after byte-compiling every package file with
# warnings as errors. Usage: test_terra_emacs_capture.sh [suite-name...],
# where a suite name is a test/test-*.el basename without its extension;
# no argument runs them all.
#
# The engine, terra-emacs, comes from TERRA_EMACS_DIR (default: a sibling
# checkout, ../terra-emacs.el). eat and persp-mode come from
# TERRA_EMACS_TEST_PACKAGES (default /opt/emacs-test-packages), or from
# the colon-separated directories in TERRA_EMACS_TEST_LOAD_PATH; suites
# needing one skip their tests when it is missing.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$TEST_DIR")"
EMACS_BIN="${EMACS:-emacs}"
ENGINE="${TERRA_EMACS_DIR:-$(dirname "$PKG_DIR")/terra-emacs.el}"
if [ ! -f "$ENGINE/terra-emacs.el" ]; then
  echo "terra-emacs not found at $ENGINE: set TERRA_EMACS_DIR" >&2
  exit 2
fi
ENGINE="$(cd "$ENGINE" && pwd)"
export TERRA_EMACS_DIR="$ENGINE"
PKGS="${TERRA_EMACS_TEST_PACKAGES:-/opt/emacs-test-packages}"
LP=(-L "$PKG_DIR" -L "$ENGINE")
IFS=: read -r -a EXTRA <<< "${TERRA_EMACS_TEST_LOAD_PATH:-}"
for d in "$PKGS/eat-0.9.4" "$PKGS/external/pkg-persp-mode" ${EXTRA[@]+"${EXTRA[@]}"}; do
  if [ -n "$d" ] && [ -d "$d" ]; then LP+=(-L "$d"); fi
done

OUT="$(mktemp -d)"
trap 'trash "$OUT" 2> /dev/null || mv "$OUT" "${TMPDIR:-/tmp}/.terra-emacs-capture-trash.$$"' EXIT
cp "$PKG_DIR"/terra-emacs-capture*.el "$OUT"/
"$EMACS_BIN" -Q --batch -L "$OUT" "${LP[@]:2}" \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile "$OUT"/terra-emacs-capture*.el

if [ $# -eq 0 ]; then
  set -- $(cd "$TEST_DIR" && ls test-*.el | sed 's/\.el$//')
fi
RC=0
for suite in "$@"; do
  echo "== $suite"
  if ! "$EMACS_BIN" -Q --batch "${LP[@]}" -l "$TEST_DIR/$suite.el" \
    -f ert-run-tests-batch-and-exit; then
    echo "FAIL: $suite"
    RC=1
  fi
done
exit $RC
