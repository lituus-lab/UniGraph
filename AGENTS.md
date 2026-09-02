<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# AGENTS.md — UniGraph

## Build & gates

```bash
nimble install -y
nimble testAll         # Nim debug + release + C ABI
nimble example         # runs the Nim demos
nimble ctest           # C ABI: static lib + tests/c
nimble pyTest          # Cython + pytest (needs libUniGraph.so)
nimble coverage        # gcov + lcov -> coverage/ (needs lcov; linux/macOS)
nimble docs            # nimib book + API reference -> pages/ (needs nimib)
nimble lint            # nimpretty check
nimble checkVGraph     # no import climbs the kernel/algorithm layering
```

`nimble docs` needs a complete Nim distribution: `--project` builds `dochack`,
which Homebrew's `nim` omits (no `tools/`). choosenim and the CI action ship it.

CI: 3-OS Nim + C ABI (`ctest`) + Python (`pyTest`) matrix, lint, V-graph check, docs.

## Conventions

- English comments, terse, describe what is done. No "deprecated".
- Core is stdlib plus NimContracts (Design by Contract, compiled away under
  `-d:release`; scoped to `graph.nim`'s wrapper and structural postconditions
  in `mst`/`tsp`/`scc`). `nimib`/`nimibook` are `taskRequires` of the
  `book`/`docs` tasks only, never a package `requires`.
- Four interchangeable storage kernels (`ListKernel`, `SeqKernel`, `CsrKernel`,
  `MatrixKernel`) implement the `GraphKernel[V, E]` concept
  (`src/UniGraph/kernel_concept.nim`) — an algorithm written against the
  concept runs unchanged on any of them. See `docs/kernel-doctrine.md`.
- `ImmutableGraph`/`MutableGraph` (`src/UniGraph/graph.nim`) are generic over
  the kernel type `K` — one definition, not one copy per kernel. `addVertex`
  on the immutable wrapper returns `(newGraph, id)`: the id is needed to chain
  `addEdge`/`removeVertex` next.
- C ABI (`ug_*`): hand-written `include/UniGraph.h` kept in sync with
  `src/UniGraph/c_api.nim`;
  `tests/c` links the header against the lib. Built
  `--app:staticlib`/`--app:lib --noMain --mm:arc -d:release`. Exposes exactly
  one concrete instantiation (`MutableGraph[ListKernel[int64, float64], ...]`)
  since the generic Nim API isn't C-ABI-shaped — see `c_api.nim`'s header
  comment. Vertex removal is intentionally not exposed there.
- A change to `c_api.nim` is verified by `ctest`, `pyTest` and, where there
  is one, `wasmTest`: three linkages, three runtime bootstraps. A green
  `ctest` alone proved nothing the day the shared build lost its
  initializer and every registry answered with the sentinel.
- Python binding (`py/unigraph`): Cython over the C ABI, RPATH `$ORIGIN`
  (Linux) / `@loader_path` (macOS), MSVC static lib on Windows.
- `book/` is nimib, but every chapter uses `nbText` (static, uncompiled),
  not `nbCode` — code/output blocks are hand-verified, not build-checked.
  Converting to `nbCode` is open work.
- End covered sources with a blank line. Nim maps a trailing statement one line
  past EOF. `nimble coverage` suppresses exactly two lcov categories, both
  compiler artefacts with no source-level fix: `mismatch`, where lcov 2.x and
  gcov disagree on the end line of Nim's generated destructors, and that EOF + 1
  attribution -- `range` on lcov 2.5, `unmapped` on the 2.0 the runners install,
  which is why the task asks the version first. Every other error still fails.

## Scope

A generic, pedagogical graph data structure library. Apache-2.0, DCO. Ported
from the standalone `graphn` project; see git history for the port.
