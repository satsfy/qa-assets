# Usage

What the pipeline actually does, evidence from the runs so far, and how to run
the whole loop on your own machine.

## What a corpus is and why it is worth saving

A fuzz target is a tiny program that feeds arbitrary bytes into some
rust-bitcoin code path, for example `bitcoin_deserialize_block` calls block
deserialization on whatever bytes it receives. libFuzzer runs the target
millions of times with mutated inputs while measuring code coverage. Most
inputs do nothing new. When an input reaches a branch that no previous input
reached, libFuzzer keeps it, writing it to the corpus directory as a file
named by the SHA-1 of its bytes.

The corpus is therefore the distilled memory of everything fuzzing ever
learned about a target. A block that exercises witness parsing, a script with
a weird opcode sequence, an amount string that hits an overflow edge. Before
this repo existed that memory was thrown away after every CI run and each
night restarted from zero. This repo makes it persistent.

## What one CI run does

The [update-corpora](.github/workflows/update-corpora.yml) workflow runs
daily at 2am UTC and on manual dispatch, in three stages.

1. The `setup` job checks out rust-bitcoin master and lists the fuzz targets
   by scanning `fuzz/fuzz_targets/`. The list becomes a job matrix, so
   targets added or removed upstream are picked up with no change here.
2. One `fuzz` job per target (108 today). Each job copies
   `fuzz_corpora/<target>` from this repo into the checkout's
   `fuzz/corpus/<target>`, so the fuzzer starts from everything already
   known instead of from nothing. It fuzzes for `max_total_time` seconds
   (default 300), then runs `cargo fuzz cmin`, which keeps only the smallest
   set of inputs that still reaches all discovered coverage, then uploads
   the directory as an artifact.
3. The `merge` job downloads all artifacts, replaces each
   `fuzz_corpora/<target>` wholesale, prunes directories of targets that no
   longer exist, and pushes a commit if anything changed.

If a target crashes, its job goes red, the crashing input is uploaded as a
`crash-<target>` artifact on the run page, and its stored corpus is left
untouched. Crashes never enter this repo. They are bugs to report against
rust-bitcoin, and the corpus replay in PR CI is what will keep them from
coming back once fixed.

## What the runs so far actually did

[Run 1](https://github.com/satsfy/qa-assets/actions/runs/30218728625)
(2026-07-26, manual) started from a nearly empty repo and committed
[08c92a0a](https://github.com/satsfy/qa-assets/commit/08c92a0a), corpora for
all 108 targets, 17310 files, about 70 MB.

[Run 2](https://github.com/satsfy/qa-assets/actions/runs/30240939279)
(2026-07-27, the daily cron, no human involved) loaded those corpora and
committed [140d2856](https://github.com/satsfy/qa-assets/commit/140d2856),
which touched 93 of the 108 targets, adding 8150 files and removing 8916.

Proof the loading works is in run 2's own logs. The
`bitcoin_deserialize_block` job printed

    INFO: 382 files found in .../fuzz/corpus/bitcoin_deserialize_block

which is exactly the 382 files run 1 had committed for that target. Five
minutes and 8.1 million executions later, cmin settled on 396 files and the
merge committed them. Next run starts from those 396.

Removals are normal and good. cmin often finds that a newer, smaller input
covers everything two older inputs covered, so file counts can go down while
coverage goes up. `units_parse_int` shrank from 430 to 420 files in run 2.
The corpus is a rolling minimal cover of the coverage frontier, not an
append-only log.

## What happens when rust-bitcoin code changes

Nothing here ever needs manual editing to follow code changes. The cycle
adapts on its own within a run or two.

- A new fuzz target is added upstream. `setup` sees the new file, the next
  run fuzzes it from an empty corpus and commits `fuzz_corpora/<target>`,
  which then grows nightly like the rest.
- A fuzz target is deleted upstream. The merge job prunes its directory.
- New code becomes reachable from an existing target, say a new opcode in
  script parsing. The stored corpus does not exercise it yet, but the fuzzer
  mutates stored inputs toward it, and every input that reaches the new code
  gets saved. Coverage of the new code accumulates over the following runs.
- Code is removed or becomes unreachable. Inputs that only existed to cover
  it stop contributing coverage and the next cmin drops them. The corpus
  shrinks by itself.

Deleting corpus files by hand is never needed and never fatal. An uncommitted
local deletion affects nothing, CI works from what is pushed. If a deletion
of a whole target directory did land on main, the next run would simply
rebuild that target from empty. It self-heals, though the rebuilt corpus only
has one run's worth of depth instead of the accumulated history, and the old
files remain recoverable from git history anyway.

## Running the whole loop locally

One-time setup

    rustup toolchain install stable nightly
    cargo +stable install --locked --version 0.12.0 cargo-fuzz

cargo-fuzz must be built with stable. Built with nightly it fails on its
locked rustix dependency. Newer cargo-fuzz (0.13.x) also works locally.

Clone rust-bitcoin anywhere, including inside this repo as `rust-bitcoin/`
(that path is gitignored, and it mirrors the CI layout). Then

    ./contrib/local-fuzz.sh rust-bitcoin units_parse_int 60

runs the exact CI cycle for one target: seed from `fuzz_corpora/`, fuzz 60
seconds, cmin, copy the result back here. Without a target it cycles over
all of them. Without a time it uses 300 seconds.

A validated example session from 2026-07-27 against the corpora at
[140d2856](https://github.com/satsfy/qa-assets/commit/140d2856):

    INFO: 420 files found in .../fuzz/corpus/units_parse_int
    #421  INITED cov: 1344 ft: 2498 corp: 352/12740b
    Done 1479546 runs in 21 second(s)
    MERGE-OUTER: 400 new files with 2593 new features added

It loaded all 420 stored inputs and started at coverage 1344 (from empty it
starts near zero), did 1.48 million executions, and cmin settled on 400
files. `jj st` (or `git status`) here then showed the changed files under
`fuzz_corpora/units_parse_int/`, ready to commit or discard.

Saving as you go is just committing. Fuzz as long as you like, stop whenever,
commit the `fuzz_corpora/` delta, and the next session (or the next CI run,
once pushed) resumes from there. Stopping early loses nothing, the corpus on
disk is always current, time only ever adds to it.

If a run crashes the script stops before saving that target. The crashing
input is at `fuzz/artifacts/<target>/` in the rust-bitcoin checkout, with
reproduction instructions printed in the output (`cargo fuzz run <target>
<file>` to replay, `cargo fuzz tmin` to shrink it). Report it upstream, do
not commit it here.

To only check the stored corpus against your working tree without fuzzing,
replay it. This takes seconds and is the regression mode intended for PR CI

    cd rust-bitcoin
    cargo +nightly fuzz run units_parse_int ../fuzz_corpora/units_parse_int -- -runs=0

## Reading the fuzzer output

    #421 INITED cov: 1344 ft: 2498 corp: 352/12740b exec/s: 0 rss: 44Mb
    #1234 NEW    cov: 1350 ft: 2510 corp: 353/12801b ... MS: 2 ChangeByte-CrossOver-

- `INITED` appears after all seed inputs were executed. `cov` is the number
  of covered code edges, the main number to watch. Higher is better, and a
  seeded run starting with high `cov` is the corpus doing its job.
- `NEW` means the mutated input just found new coverage and was added to the
  corpus. A steady stream of NEW lines means the target is still learning.
  Silence for a long time means the corpus has plateaued at this time budget.
- `ft` counts finer-grained features (edge plus hit count), `corp` is corpus
  size in inputs and bytes, `MS` names the mutations that built the input.
- `Done N runs in M seconds` is the normal end of a timed run. A panic or
  crash prints a stack trace and an `artifact_prefix` path instead.
