#!/usr/bin/env bash
# Fuzz rust-bitcoin locally, seeded from the corpora stored in this repo,
# and copy the minimized results back. This is the same seed/fuzz/cmin/save
# cycle the update-corpora workflow runs in CI.
#
# Usage:
#   contrib/local-fuzz.sh <rust-bitcoin-dir> [target] [seconds]
#
# Without a target it cycles over every target once. Seconds per target
# defaults to 300. Needs a nightly toolchain and cargo-fuzz installed.
#
# When it finishes, review the changes with git status / git diff --stat
# in this repo and commit what you want to keep. If a target crashes the
# script stops, the crashing input is under fuzz/artifacts/<target>/ in
# the rust-bitcoin checkout, and nothing is saved for that target.

set -euo pipefail

QA_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
RB_DIR=${1:?usage: local-fuzz.sh <rust-bitcoin-dir> [target] [seconds]}
RB_DIR=$(cd -- "$RB_DIR" && pwd)
TARGET=${2:-}
TIME_PER_TARGET=${3:-300}

cd "$RB_DIR"

if [ -n "$TARGET" ]; then
  targets=$TARGET
else
  targets=$(cd fuzz && find fuzz_targets/ -type f -name '*.rs' \
    | sed 's/^fuzz_targets\///; s/\.rs$//; s/\//_/g; s/^_//' | LC_ALL=C sort)
fi

for t in $targets; do
  # Same weak-crypto cfgs rust-bitcoin CI uses for these targets.
  case "$t" in
    bitcoin*) export RUSTFLAGS='--cfg=hashes_fuzz --cfg=secp256k1_fuzz' ;;
    *) unset RUSTFLAGS || true ;;
  esac

  echo "=== $t: seed from $QA_DIR/fuzz_corpora/$t"
  mkdir -p "fuzz/corpus/$t"
  if [ -d "$QA_DIR/fuzz_corpora/$t" ]; then
    find "$QA_DIR/fuzz_corpora/$t" -maxdepth 1 -type f \
      -exec cp -t "fuzz/corpus/$t/" {} +
  fi

  echo "=== $t: fuzz for $TIME_PER_TARGET seconds"
  cargo +nightly fuzz run "$t" -- -max_total_time="$TIME_PER_TARGET"

  echo "=== $t: minimize"
  cargo +nightly fuzz cmin "$t"

  echo "=== $t: save back"
  rm -rf "${QA_DIR:?}/fuzz_corpora/$t"
  mkdir -p "$QA_DIR/fuzz_corpora/$t"
  find "fuzz/corpus/$t" -maxdepth 1 -type f \
    -exec cp -t "$QA_DIR/fuzz_corpora/$t/" {} +
done

echo "Done. Review with: git -C $QA_DIR status"
