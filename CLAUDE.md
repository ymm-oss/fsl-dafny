<!-- SPDX-License-Identifier: Apache-2.0 -->

# fsl-dafny: instructions for Claude Code

`docs/details.md` describes what each piece does and the current results. This file
holds the working rules that are not there.

## Sources of truth

- **Input contract**: fslc's Public Kernel (`fslc kernel`, schema
  `kernel.v1.schema.json` in ymm-oss/fsl) and the JSON of `fslc conformance`,
  `testgen`, `replay` and `verify`. This repository never parses `.fsl` itself
  (the planted-`init` copies in `invcheck.mjs` and the enlarged-type copy in
  `core.mjs` are the only text edits).
- **Undocumented Kernel shapes**: the schema leaves some objects open (binders,
  assignment targets; ymm-oss/fsl#1927). When the schema says nothing, read the
  exporter's actual output (`fslc kernel` on a small spec) and handle every field
  it emits.
- **Pinned fslc**: v5.1.0 (CI downloads the release binary). Results in
  `docs/details.md` name the fslc, Dafny and Node versions they were measured with.
- **History**: this started as the spike for ymm-oss/fsl#1908, in
  ymm-oss/fsl#1918 (closed, branch `spike/issue-1908-dafny-core`).

## Commands

```bash
npm ci
FSLC=/path/to/fslc ./run-all.sh        # every positive run and negative control (~20 min locally, ~7 min in CI)
node core.mjs <spec.fsl> [--widen T] [--seed 1]  # one spec end to end; prints one JSON report
RUN_AI=1 ./run-all.sh                  # also the real-model proof-loop controls (uses the claude CLI)
```

`fslc` defaults to the one on `PATH`. CI (`.github/workflows/ci.yml`) runs
`run-all.sh` on ubuntu-24.04, because the fslc release binary needs glibc 2.39.

## Rules

- **Fail closed.** `gen.mjs` exits 2 on any Kernel construct, field or kind it
  does not translate. Never default an unknown case to a guess (finding B1: a
  binder treated as "the whole type" dropped `where` filters and still proved).
- **A new construct comes with three things**:
  - a positive spec in `fixtures/`, run through `core.mjs` in `run-all.sh`;
  - a generated-Dafny mutant (`gen_mutant`) that must report divergences;
  - a refusal control for the forms still not handled.
- **Negative controls check the reason, not only the exit code.** Grep the
  message, or require `"divergences": [1-9]` / `"disagreements": [1-9]` /
  `"failed": [1-9]`. A control that passes on any nonzero exit is not evidence.
- **Proofs.** A proof file is accepted only by `build.sh`: the structure check,
  `dafny audit` with no findings, and `dafny verify --verify-included-files`.
  Never add `assume`, `{:axiom}` or `{:verify false}`, or edit the generated
  module to make a proof pass. A failure located in `out/<Name>.gen.dfy` is a
  `gen.mjs` defect or a reachable partial operation, not a proof problem.
  - Say who wrote each proof: the model through `prove.mjs`, or by hand.
- **`specs/` is a copy.** These are fsl's specs, copied unchanged at d1df480b.
  Do not edit them. To refresh, copy them again from a named fsl commit and
  update `docs/details.md` (the SHA, results table) in the same change. This
  repository's own specs go in `fixtures/`.
- **`out/` is generated** and ignored; never commit it or hand-edit it.
- **Changes to checks.** Run `run-all.sh` twice and require identical
  `out/core-results.jsonl`. Update the counts and the results table in
  `docs/details.md` from the run, not from memory.
- New source files carry the Apache-2.0 SPDX header.

## Open items

- ymm-oss/fsl#1927: the Kernel schema does not yet describe binders,
  assignment targets, or the `ite` chain a collection `sum` is lowered to. When
  it lands, check `gen.mjs` against the published schema.
- Not translated: relations, `transitions` properties, `leadsTo` (left to
  `fslc verify` with `--liveness-by-fslc`), `compose` specs (refused by
  `fslc kernel` v1).
- testgen `forbidden` scenarios: only the requirements and business dialects
  have them, so `testgen.mjs`'s forbidden branch is not exercised by any spec here.
- ymm-oss/fsl#1908 follow-ups: contract functions, the IO shell.
