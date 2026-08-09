<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0004: UniGraph module conventions

- Status: Accepted
- Date: 2026-07-26
- Scope: UniGraph itself

## Layout

```text
UniGraph.nimble              package + tasks
config.nims                  arch-conditional build flags
src/UniGraph.nim             umbrella — re-exports every public submodule
src/UniGraph/types.nim       VertexId, Vertex, Edge, Direction, GraphType
src/UniGraph/kernel_concept.nim  the GraphKernel contract
src/UniGraph/kernels/        ListKernel, SeqKernel, CsrKernel, MatrixKernel
src/UniGraph/graph.nim       ImmutableGraph / MutableGraph, generic over kernel
src/UniGraph/visitor.nim     Visitor pattern (pedagogical tracing)
src/UniGraph/algorithms/     traversals, shortest_path, mst, scc, tsp
src/UniGraph/visualize/      ASCII / DOT rendering
tests/unit/                  one suite per Nim module above
examples/                    Nim + C demos, performance benchmark
book/                        nimib book (11 chapters, ported from graphn)
docs/kernel-doctrine.md      why four kernels
src/UniGraph/c_api.nim       C ABI (ug_*), one monomorphized graph instantiation
include/UniGraph.h           hand-written C header, kept in sync with c_api.nim
tests/c/                     C ABI test (drift detector)
py/                          Cython binding (unigraph package) + pytest
ADRs/                        0001–0004
.github/workflows/           ci.yml (3-OS Nim + C ABI + Python, lint, V-graph, docs), release.yml
LICENSE NOTICE CONTRIBUTING.md SECURITY.md .gitignore README.md AGENTS.md CLAUDE.md
```

C ABI and Python binding: the public Nim API is generic
(`ImmutableGraph[K, V, E]`/`MutableGraph[K, V, E]` over any kernel `K`), which
is not C-ABI-shaped. `src/UniGraph/c_api.nim` exposes exactly one concrete
instantiation — `MutableGraph[ListKernel[int64, float64], int64, float64]` —
following the pattern ADR-0003 describes. `py/unigraph` is a thin Cython
wrapper over that same C ABI. Both façades expose the graph operations and
algorithms available for this concrete instantiation; ADR-0003 records the
deliberate exclusions.

## Conventions

- Core is stdlib plus NimContracts. `{.contractual.}` +
  `require:`/`ensure:`/`body:`, compiled away under `-d:release` — scoped to
  `ImmutableGraph.addVertex`/`removeVertex` and the structural postconditions
  in `mst`/`tsp`/`scc` (result sizes bounded by `vertexCount`), not every
  proc. `nimib`/`nimibook` are `taskRequires` of the `book`/`docs` tasks only.
- Four interchangeable storage kernels implement `GraphKernel[V, E]`
  (a Nim `concept`, checked at compile time): swapping the kernel never
  changes what an algorithm computes, only its performance profile.
- `types.nim` never imports `kernels/`; `kernels/` never imports
  `algorithms/` — enforced by `nimble checkVGraph` (`vgraph.cfg`), not just
  convention.
- Immutable by default: `ImmutableGraph` operations return a new instance;
  `addVertex` returns `(newGraph, id)` — both are needed, the id to chain
  the next `addEdge`/`removeVertex`. `MutableGraph` is the explicit
  escape hatch for in-place performance, and what the C ABI wraps (a foreign
  caller expects in-place mutation, not a new handle per call).
- English comments, terse, describe what is done. No "deprecated".

## CI gates

- `nimble testCi` + `testCiRelease`, `nimble ctest`, `nimble pyTest` — see
  `.github/workflows/ci.yml` for the current OS matrix per job.
- `consume-cabi`/`consume-wheel` rebuild against the published artifacts on a
  machine without Nim, so what ships is what was tested.
- `nimble lint` + `nimble checkVGraph`.
- `nimble docs` builds the book and API reference. Complete examples in the
  book are extracted and compiled during release verification.
