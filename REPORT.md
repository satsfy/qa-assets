40 second fuzzings of 15 minute jobs WTF!! Its horrible

can't even call this fuzzing

Apparently, after this merged, https://github.com/rust-bitcoin/rust-bitcoin/pull/6589 every shard of the Fuzz cron runs cargo fuzz list | sort | awk before anything installs cargo-fuzz. The error (no
such command: fuzz) is swallowed by the pipeline (no pipefail), the target array comes out empty, the loop body never executes, and the job goes green in ~30-40 seconds instead of the 12+ minutes real fuzzing takes. Worse, the job "succeeding" saves a cache without cargo-fuzz in it, so it can never self-heal, and #6589 also deleted the verify-execution job that existed to catch exactly this. Evidence: run 30249393588 https://github.com/rust-bitcoin/rust-bitcoin/actions/runs/30249393588 — the shard log literally prints error: no such command: fuzz and passes. Worth reporting upstream immediately (your call how); it's also strong motivation for this PR, which deletes that workflow entirely.

