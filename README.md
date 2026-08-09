<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniGraph

A generic, pedagogical graph data structure library for Nim.

If you've never used a graph library before: a **graph** is just vertices
(the dots) connected by edges (the lines). UniGraph lets you build one,
walk it (breadth-first or depth-first), find the shortest path between two
vertices, find the cheapest way to connect everything (a minimum spanning
tree), and a few other classic algorithms. Traversals, shortest paths, spanning
trees, Tarjan SCCs, and articulation points are generic over storage and
payload types; Kosaraju, TSP, and visualization use `ListKernel`. The `book/`
directory walks through all of this from scratch.

## What's inside

- **Four storage kernels under one contract** — `ListKernel`, `SeqKernel`,
  `CsrKernel`, `MatrixKernel` (`src/UniGraph/kernels/`). Generic algorithms
  compute the same result across them with different memory and performance
  trade-offs; List-specific modules are identified in
  `docs/kernel-doctrine.md`.
- **A formal contract, not a convention** — `GraphKernel[V, E]`
  (`src/UniGraph/kernel_concept.nim`) is a Nim `concept`: a kernel either
  satisfies it or the code doesn't compile. Checked explicitly in
  `tests/unit/test_kernel_concept.nim`.
- **Immutable by default** — `ImmutableGraph` operations return a *new*
  graph instead of changing the old one (`src/UniGraph/graph.nim`);
  `MutableGraph` is the deliberate escape hatch when you need in-place
  performance.
- **Pedagogical tracing** — the `Visitor` pattern (`src/UniGraph/visitor.nim`)
  lets BFS/DFS emit a step-by-step trace of what they did and why, so you
  can *see* the algorithm run instead of just getting its final answer.
- **Classic graph algorithms** — iterative and recursive traversals,
  reachability, Dijkstra, A*, Bellman–Ford, Prim, Kruskal, Tarjan, Kosaraju,
  articulation points, and three TSP solvers (`src/UniGraph/algorithms/`).
- **Rendering and statistics** — ASCII and Graphviz DOT output, plus degree
  distributions (`src/UniGraph/visualize/`).

## Layout

```text
src/UniGraph.nim              umbrella module — re-exports the public API
src/UniGraph/types.nim        VertexId, Vertex, Edge, Direction, GraphType
src/UniGraph/kernel_concept.nim  the GraphKernel contract
src/UniGraph/kernels/         ListKernel, SeqKernel, CsrKernel, MatrixKernel
src/UniGraph/graph.nim        ImmutableGraph / MutableGraph wrappers
src/UniGraph/visitor.nim      Visitor pattern for pedagogical tracing
src/UniGraph/algorithms/      traversals, shortest_path, mst, scc, tsp
src/UniGraph/visualize/       ASCII / DOT rendering
src/UniGraph/c_api.nim        C ABI (ug_*) — one monomorphized graph, see below
include/UniGraph.h            hand-written C header, kept in sync with c_api.nim
tests/c/                      C ABI test (links the header against the lib)
py/                           Cython binding (unigraph) + pytest
tests/unit/                   one suite per Nim module above
examples/                     runnable Nim + C demos, performance benchmark
benchmarks/                   cross-library benchmarks vs networkx/igraph/Boost/petgraph
book/                         nimib book — start here if you're new
docs/kernel-doctrine.md       why four kernels, what each is for
ADRs/                         0001 sibling deps, 0002 license, 0003 C ABI/Python, 0004 module conventions
.github/workflows/ci.yml      3-OS Nim + C ABI + Python matrix, lint, V-graph check, docs
```

## Build

```bash
nimble install -y
nimble test           # Nim, debug
nimble testRelease    # Nim, release
nimble testAll        # debug + release + C ABI
nimble example         # run the Nim demos
nimble benchmark        # performance oracle: CsrKernel.edges() O(V+E) vs O(V*E)
nimble benchmarkCross    # build the Nim side of benchmarks/ (see benchmarks/README.md)
nimble ctest            # C ABI: static lib + tests/c
nimble cexample         # C demo
nimble pyTest           # Cython + pytest
nimble coverage        # gcov + lcov -> coverage/
nimble book             # nimib book -> book/__site/
nimble docs             # API reference + book -> pages/
nimble lint             # nimpretty check
nimble checkVGraph      # no import climbs the kernel/algorithm layering
```

### C ABI and Python binding

`UniGraph`'s public Nim API is generic (`ImmutableGraph[K, V, E]`/
`MutableGraph[K, V, E]` over any kernel and any vertex/edge type), which
isn't C-ABI-shaped. `src/UniGraph/c_api.nim` exposes exactly one concrete
instantiation instead — a directed-or-undirected, simple graph with an
`int64` vertex label and a `float64` edge weight (`ug_graph_new`,
`ug_graph_add_vertex`, traversal, shortest-path, spanning-tree, component,
TSP, rendering, and statistics operations). Vertex removal is intentionally
not exposed because a raw integer cannot preserve `VertexId`'s generation
counter. The Python package `unigraph` (`py/`) wraps the same complete concrete
surface. C callers must invoke `ug_init()` before any other ABI function;
the Python extension does this when imported.

## The Uni* family

UniGraph is a layer-1 engine: its Nim core depends only on the standard library
and NimContracts, and higher-level Uni* packages may build graph-shaped domains
on it. The family’s scope and design principles are documented in the
[lituus-lab organization profile](https://github.com/lituus-lab/.github).

## Provenance & development

UniGraph consolidates textbook graph algorithms and the earlier hand-written
`graphn` implementation into the Uni* engine/kernel structure. Its deliberately
short, linear public history was reconstructed during an LLM-assisted review of
that pre-existing code and design; it does not imply that the library was
designed from scratch in the span represented by those commits. Every shipped
claim, example, and binding is validated by the repository’s executable tests.

## CI

`test` runs the Nim matrix on ubuntu/macOS/Windows. `cabi`/`python` build and
test the C ABI and Python binding on all three OSes; `consume-cabi`/
`consume-wheel` rebuild against the published artifacts on a machine without
Nim, so what ships is what was tested. `lint` runs `nimpretty` and the
V-graph import-direction check. `coverage` and `docs` run on ubuntu.

`dco` blocks PRs missing a `Signed-off-by` trailer; `commitizen` blocks PRs whose
commits or title are not [Conventional Commits](https://www.conventionalcommits.org/)
(`CONTRIBUTING.md`).

The same gates run locally with pre-commit: `pip install pre-commit && pre-commit install`
(`CONTRIBUTING.md`).

`docs` publishes to GitHub Pages only from a public repo.

## AI-assisted contributions

Assistance from AI/LLM tools is welcome on the same terms as any other
contribution.

- **Accountability.** The human contributor is the author and remains fully
  responsible for the change. The DCO sign-off (`Signed-off-by`) is the mechanism:
  by signing you certify the content is yours or properly licensed — this covers
  AI-assisted work, provided you can stand behind it.
- **No third-party contamination.** Ensure AI output introduces no code from a
  third party without a compatible license and attribution. If an LLM reproduced
  protected material, do not submit it.
- **Correctness is yours.** The gates (tests, `nimble lint`, conventional commits,
  pre-commit) catch a lot, but you own the result — review and verify what you
  commit.
- **Atomic commits.** Each commit is one logical change. A PR may stack
  several atomic commits (one per element, say) — one monolithic big-bang
  commit is not.
- **Disclosure.** State in the PR whether AI assistance was used (see the PR
  template). It is not a hard requirement — the DCO remains the gate.

## License

Apache-2.0 (`LICENSE`). DCO sign-off on every commit (`CONTRIBUTING.md`).
