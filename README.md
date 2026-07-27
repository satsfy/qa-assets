# qa-assets

Fuzz corpora for the [rust-bitcoin](https://github.com/rust-bitcoin/rust-bitcoin)
fuzz targets, in the style of Bitcoin Core's
[qa-assets](https://github.com/bitcoin-core/qa-assets) repository.

See rust-bitcoin issue
[#6511](https://github.com/rust-bitcoin/rust-bitcoin/issues/6511) for the
motivation. Fuzzing that always starts from an empty corpus forgets everything
it ever learned, and nothing stops a PR from reintroducing a crash that fuzzing
already found once. Keeping minimized corpora here lets CI replay them on every
PR as a cheap regression test and lets long fuzz runs resume where the last one
stopped.

[USAGE.md](USAGE.md) explains the update cycle in detail, what the runs so far
actually did, and how to run the same loop locally with
[contrib/local-fuzz.sh](contrib/local-fuzz.sh).

## Layout

    fuzz_corpora/<target>/    minimized libFuzzer corpus for one cargo-fuzz target

Target names match the output of `cargo fuzz list` in rust-bitcoin. A target
file `fuzz/fuzz_targets/bitcoin/deserialize_block.rs` becomes the target
`bitcoin_deserialize_block` and its corpus lives in
`fuzz_corpora/bitcoin_deserialize_block/`. Corpus files are named by the SHA-1
of their contents, which is what libFuzzer writes, so updates only ever add or
remove whole files.

Targets whose names start with `bitcoin` are built with
`RUSTFLAGS='--cfg=hashes_fuzz --cfg=secp256k1_fuzz'`, the same weak-crypto
configuration rust-bitcoin CI uses. Their corpora are only meaningful under
those cfgs.

## How the corpora are updated

The [update-corpora](.github/workflows/update-corpora.yml) workflow runs daily
and can be dispatched manually. For every fuzz target found in rust-bitcoin
master it

1. seeds `fuzz/corpus/<target>` from `fuzz_corpora/<target>`
2. fuzzes for `max_total_time` seconds (default 300)
3. minimizes the result with `cargo fuzz cmin`
4. commits whatever changed back to this repository

The target list is read from the rust-bitcoin checkout on every run, so new
targets start accumulating a corpus automatically and corpora of deleted
targets are pruned.

If a run finds a crash, that target's job fails, the crashing input is uploaded
as a `crash-<target>` artifact on the workflow run, and the target's stored
corpus is left untouched. Crashing inputs are never committed here. Report the
crash upstream, and once it is fixed the next run resumes normally.

## Using the corpora locally

    git clone https://github.com/rust-bitcoin/qa-assets
    cd rust-bitcoin
    mkdir -p fuzz/corpus
    cp -r ../qa-assets/fuzz_corpora/* fuzz/corpus/
    cd fuzz && ./fuzz.sh <target>

Or point cargo-fuzz at a corpus directory directly

    cargo +nightly fuzz run <target> ../qa-assets/fuzz_corpora/<target>

## Replaying the corpora in CI

Replaying a corpus executes every stored input once and takes seconds, which
makes it usable on every PR. The rust-bitcoin CI job would look like

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
    # cargo-fuzz 0.12.0 must be built with stable, its locked rustix
    # dependency does not build on current nightlies
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

`-runs=0` makes libFuzzer execute every corpus input during startup and exit
without mutating, so a reintroduced bug whose trigger is in the corpus fails
the job immediately.

## Contributing corpora

Inputs that increase coverage are welcome from any source, manual or from your
own fuzz runs. Copy them into `fuzz_corpora/<target>/`, run
`cargo fuzz cmin <target>` against a seeded corpus to keep only what adds
coverage, and open a PR. Do not submit crashing inputs, report those as issues
against rust-bitcoin instead.
