# rust-bitcoin QA Assets

This repository contains fuzz seeds, fixed test vectors, and other assets used for testing the
projects in the rust-bitcoin ecosystem.

Assuming this stuff is copyrightable at all, it is available on a CC0 license and other projects
are free to use them for any purpose whatsoever.

## Fuzz corpora

When a fuzz target stores and reuses a corpus, the fuzzing quality matures. See rust-bitcoin issue
[#6511](https://github.com/rust-bitcoin/rust-bitcoin/issues/6511) for motive. `fuzz_corpora/` holds
the minimized libFuzzer corpora for the rust-bitcoin fuzz targets, in the style of Bitcoin Core's
[qa-assets](https://github.com/bitcoin-core/qa-assets). One directory per target under
`fuzz_corpora/`, named as in rust-bitcoin's `cargo fuzz list`.

A scheduled workflow in rust-bitcoin pull the stored corpus, fuzzes, minimizes with
`cargo fuzz cmin`, and pushes what changed back here. The target list is read from the checkout
every run, so new targets accumulate a corpus and deleted ones are pruned. A crash fails that
target's job and leaves its stored corpus untouched.

## Running the fuzzing locally

Install cargo-fuzz with stable. Its locked `rustix` dependency does not build on nightly.

```bash
rustup toolchain install stable nightly
cargo +stable install --locked --version 0.12.0 cargo-fuzz
```

Clone rust-bitcoin next to this checkout, then run one seed, fuzz, minimize and save cycle for a
single target:

```bash
./contrib/local-fuzz.sh ../rust-bitcoin units_parse_int 60
```

The script copies the stored inputs in, so the run starts from everything already known
rather than from scratch, and copies the minimized result back when it finishes. Crashing input are
written under `fuzz/artifacts/<target>/` in the rust-bitcoin checkout.
