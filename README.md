# qa-assets

Fuzz corpora for the [rust-bitcoin](https://github.com/rust-bitcoin/rust-bitcoin)
fuzz targets, in the style of Bitcoin Core's
[qa-assets](https://github.com/bitcoin-core/qa-assets). Motivated by issue
[#6511](https://github.com/rust-bitcoin/rust-bitcoin/issues/6511).

This repository is updated automatically and frequently from Forgejo Actions.
Storing a fuzzing corpora lets CI replay them on every PR as a regression test and lets
long fuzz runs resume where the last one stopped, preserving progress and edge cases.

## How the corpora are updated

The [update-corpora](.github/workflows/update-corpora.yml) workflow runs daily and on manual dispatch. For every target in rust-bitcoin master it seeds `fuzz/corpus/<target>` from `fuzz_corpora/<target>`, fuzzes for `max_total_time` seconds, minimizes the output with `cargo fuzz cmin`, and commits the result back. The target list is read from the checkout on every run, so new targets accumulate a corpus automatically and deleted ones are pruned.

A crash fails that target's job, uploads the input as a `crash-<target>` artifact, and leaves the stored corpus untouched. Crashing inputs are never committed.

## Layout

- `fuzz_corpora/<target>/`: minimized libFuzzer corpus for one cargo-fuzz target
- `.github/workflows/`: the update-corpora automation
- `contrib/local-fuzz.sh`: (for local runs only) run one CI-style fuzz cycle
- `rust-bitcoin/`: (for local runs only) ignored checkout used for fuzzing

A directory is created per fuzz target under `fuzz_corpora/`, named as in
rust-bitcoin's `cargo fuzz list`. Each file is one corpus input, named by the SHA-1 of
its contents (libFuzzer's scheme), so updates only add or remove whole files.

## Running rust-bitcoin fuzzing with corpora

If not already, setup cargo-fuzz on stable.

```bash
rustup toolchain install stable nightly
cargo +stable install --locked --version 0.12.0 cargo-fuzz
```

Clone `rust-bitcoin` to `./rust-bitcoin/` and then:

```bash
./contrib/local-fuzz.sh rust-bitcoin units_parse_int 3
```

Expect output like:

```
=== units_parse_int: seed from .../qa-assets/fuzz_corpora/units_parse_int
=== units_parse_int: fuzz for 3 seconds
    Finished `release` profile [optimized + debuginfo] target(s) in 0.03s
     Running `target/x86_64-unknown-linux-gnu/release/units_parse_int -artifact_prefix=.../fuzz/artifacts/units_parse_int/ -max_total_time=3 .../fuzz/corpus/units_parse_int`
INFO: Running with entropic power schedule (0xFF, 100).
INFO: Seed: 3486394695
INFO: Loaded 1 modules   (28171 inline 8-bit counters): 28171 [0x58c620681c40, 0x58c620688a4b),
INFO: Loaded 1 PC tables (28171 PCs): 28171 [0x58c620688a50,0x58c6206f6b00),
INFO:      412 files found in .../fuzz/corpus/units_parse_int
INFO: -max_len is not provided; libFuzzer will not generate inputs larger than 4096 bytes
INFO: seed corpus: files: 412 min: 2b max: 291b total: 14721b rss: 34Mb
#413    INITED cov: 1244 ft: 2345 corp: 409/14450b exec/s: 0 rss: 46Mb
#93474  REDUCE cov: 1244 ft: 2345 corp: 409/14449b lim: 1218 exec/s: 46737 rss: 172Mb L: 38/291 MS: 1 EraseBytes-
#131072 pulse  cov: 1244 ft: 2345 corp: 409/14449b lim: 1588 exec/s: 43690 rss: 225Mb
#162858 DONE   cov: 1244 ft: 2345 corp: 409/14449b lim: 1908 exec/s: 40714 rss: 266Mb
Done 162858 runs in 4 second(s)
=== units_parse_int: minimize
     Running `target/x86_64-unknown-linux-gnu/release/units_parse_int -merge=1 .../fuzz/.tmpyddnOG/corpus .../fuzz/corpus/units_parse_int`
MERGE-OUTER: 413 files, 0 in the initial corpus, 0 processed earlier
MERGE-OUTER: attempt 1
MERGE-INNER: 413 total files; 0 processed earlier; will process 413 files now
#1      pulse  cov: 318 ft: 319 exec/s: 0 rss: 34Mb
#2      pulse  cov: 362 ft: 363 exec/s: 0 rss: 34Mb
...
#413    DONE   cov: 1256 ft: 2357 exec/s: 0 rss: 44Mb
MERGE-OUTER: successful in 1 attempt(s)
MERGE-OUTER: 408 new files with 2357 new features added; 1256 new coverage edges
=== units_parse_int: save back
Done. Review with: git -C .../qa-assets status
```

The script runs the following phases:

- Seed: copies the 412 stored inputs from `fuzz_corpora/units_parse_int/` into the checkout's `fuzz/corpus/`.
- Fuzz: builds and runs the target for 3 seconds. Each line is a status update. `cov` is coverage edges hit, `ft` features, `corp` the in-memory corpus, `exec/s` throughput. Coverage stayed at 1244, no new paths were found because a corpus already existed and the run was only 3 seconds.
- Minimize: `cargo fuzz cmin` replays every input and keeps only those that add coverage.
- Save: 408 files are copied over `fuzz_corpora/units_parse_int/`, so the next session resumes from there.

## Replaying the corpora in CI

Replaying a corpus mean we executes the saved memory. This is fast enough that it could be part of the CI of every rust-bitcoin PR.

```yaml
fuzz-regression:
  runs-on: ubuntu-24.04
  steps:
    - uses: actions/checkout@v6
    - uses: actions/checkout@v6
      with:
        repository: rust-bitcoin/qa-assets
        path: qa-assets
    - uses: dtolnay/rust-toolchain@nightly
    - run: |
        rustup toolchain install stable --profile minimal
        cargo +stable install --locked --version 0.12.0 cargo-fuzz
    - name: Replay corpora
      run: |
        for target in $(cd fuzz && cargo fuzz list); do
          if [[ "$target" =~ ^bitcoin ]]; then
            export RUSTFLAGS='--cfg=hashes_fuzz --cfg=secp256k1_fuzz'
          else
            unset RUSTFLAGS
          fi
          mkdir -p "qa-assets/fuzz_corpora/$target"
          cargo +nightly fuzz run "$target" "qa-assets/fuzz_corpora/$target" -- -runs=0
        done
```

## Fuzzing considerations

Targets prefixed `bitcoin` are built with `RUSTFLAGS='--cfg=hashes_fuzz --cfg=secp256k1_fuzz'` (as in rust-bitcoin CI). Those cfgs swap real hashing and secp256k1 for cheap stand-ins so the fuzzer explores logic instead of crypto.
