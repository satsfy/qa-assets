#!/usr/bin/env bash
# Fuzz rust-bitcoin locally for testing, seeded from the corpora stored in this repo,
# and copy the minimized results back.
#
# Usage:
#   contrib/local-fuzz.sh <rust-bitcoin-dir> [target] [seconds]
#
# Without a target it cycles over every target once.
# Defaults to 300 seconds per target.
# Needs a nightly toolchain and cargo-fuzz installed.

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
  case "$t" in
    hashes_*) unset RUSTFLAGS || true ;;
    *) export RUSTFLAGS='--cfg=hashes_fuzz --cfg=secp256k1_fuzz' ;;
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
