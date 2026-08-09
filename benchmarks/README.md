<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Cross-library benchmarks

UniGraph's design goal is to be performance-oriented (see
`book/what_is_unigraph.nim`); this directory checks that against something
external instead of the library's own assumptions. It runs the same
algorithms, on the same generated graphs, through UniGraph and four
external graph libraries — two purposes, not one:

1. **Correctness**: if every library agrees on the answer (reachable-vertex
   counts, MST weight, SCC count, shortest-path distances, tour cost), that's
   real evidence UniGraph's algorithm implementations are right, not just
   internally self-consistent.
2. **Performance**: once correctness is established, the timings are
   comparable — same input, same algorithm, different implementation.

## Honesty notes — read before trusting any number this produces

- **Single machine, single run.** This is not a rigorous statistical
  benchmark (no repeated trials, no variance reported, no warm/cold-cache
  control, background load on the machine not controlled for). Treat the
  numbers as a rough order-of-magnitude comparison, not a citable result.
- **Sandboxed CI/dev-container runs are not representative.** Wall-clock
  timing on a shared, possibly throttled, virtualized environment doesn't
  reflect real hardware performance. Run this on a quiet, dedicated machine
  before drawing any conclusion.
- **Different libraries, different design goals.** networkx is pure Python
  and explicitly not optimized for speed; igraph/Boost/petgraph all wrap or
  are compiled, general-purpose libraries with years of tuning UniGraph
  hasn't had. A gap either way says as much about library maturity as it
  does about the underlying algorithm or language.
- **What the Nim/UniGraph harness actually measures:**
  - `bench_unigraph` builds its graphs on `SeqKernel`, not `ListKernel`.
    `traversals`/`shortest_path`/`mst`/`scc.tarjan` are generic over the
    kernel; `SeqKernel`'s `neighbors()` is a direct array index, matching
    how petgraph/Boost/networkx/igraph represent a graph, while
    `ListKernel`'s `vertices`/`adjacency` are `Table[VertexId, _]` — a hash
    on every access. `ListKernel` trades that for cheap vertex
    insertion/removal (see `docs/kernel-doctrine.md`); it isn't part of
    this comparison.
  - `bfs`/`dfsIterative` run with `newVisitor[float](trace = false)`: the
    default `Visitor` formats a trace string and updates two tables on
    every edge for step-by-step pedagogical output (see `visitor.nim`),
    a feature none of the other four libraries have an equivalent of and
    that dominates runtime on a large graph. `trace = false` keeps
    `visitOrder`/`discovered`/`finished`/`edgeTraversals` but skips the
    formatted log, matching what a non-tracing BFS/DFS call actually costs.
- **Known coverage gaps, on purpose, not silently:**
  - petgraph ships only one MST algorithm (Kruskal-based
    `petgraph::algo::min_spanning_tree`) — its results are recorded as
    `mst_default`, not split into `mst_prim`/`mst_kruskal`.
  - igraph's Python binding exposes one spanning-tree call — same
    `mst_default` treatment.
  - Neither igraph nor Boost nor petgraph ships a nearest-neighbor/2-opt TSP
    heuristic, so `tsp_nn`/`tsp_2opt` are hand-implemented identically in
    every language (see "TSP methodology" below) — this deliberately tests
    "can the same algorithm be implemented as fast in language X", not
    "does library X have a better TSP solver".
  - UniGraph's own shipped `algorithms/tsp.nim` (`tspNearestNeighbor`,
    `tsp2Opt`) is edge/kernel-based and rescans every vertex through
    `kernel.getEdge` at each step — quadratic-to-cubic on top of the graph
    itself, fine for the small, explicitly-listed graphs the book chapter
    demonstrates it on, not for a thousands-of-cities instance. The Nim
    harness cross-checks it against the standalone implementation for
    `n <= 200` (row `unigraph-kernel-api`), then relies on the standalone
    version for the actual timed comparison at larger `n`.
  - Both UniGraph's `tarjan` and petgraph's `tarjan_scc` recurse once per
    DFS-tree edge, with no library-level iterative alternative for either.
    On the million-vertex directed fixture that recursion depth overflows
    the default 8MB thread stack in both. Neither harness relies on the
    caller raising `ulimit -s` to cope: `bench_unigraph` runs the whole
    benchmark on a pthread created with an explicit 1GiB stack (see the
    comment above `when isMainModule` in `nim/bench_unigraph.nim` — Nim's
    own `std/typedthreads` stack size is a fixed ~2MB compile-time constant
    on desktop targets, so this goes to libc directly instead), and
    `bench_petgraph` does the same via `std::thread::Builder::stack_size`.
    Boost's `strong_components` and both Python bindings' SCC calls need no
    such workaround at this size.
  - `generate_graphs.py` drops the rare accidental duplicate `(u, v)` pair
    from random sampling instead of keeping it (a handful out of millions at
    the largest sizes). This matters because libraries disagree on how to
    handle a parallel edge: UniGraph's `ListKernel` silently rejects one
    under its default `Simple` graph type (keeping only the first-written
    weight), while Boost/petgraph keep every parallel edge and let the
    algorithm pick the best one during relaxation. Each behavior is
    internally correct for the graph its own library ends up building, but
    the two builds then differ from the same file. Deduplicating at
    generation time removes the ambiguity: every language builds the exact
    same simple graph, independent of its own parallel-edge policy.
  - Fixture sizes are tiered (1e3/1e4/1e5), with 1e6 generated only for the
    generators cheap enough to build and traverse at that scale in every
    language within a reasonable run (`er_sparse_undirected`, `ba_scalefree`,
    `grid`, and the directed ER variant used for SCC) — not for dense ER,
    which doesn't scale that far without a fundamentally different
    (non-complete-graph) approach.
  - TSP instances stop at `n = 500`. Every harness's 2-opt recomputes the
    full tour cost per candidate move (see "TSP methodology" below), making
    each pass O(n³); measured directly, one 2-opt run takes ~9s at n=1000
    and ~74s at n=2000 in compiled, release-mode Nim — the fastest of the
    five harnesses — which would run to tens of minutes per instance in
    pure Python. `n = 500` keeps every harness in the range of seconds to
    low tens of seconds.

## Layout

```text
benchmarks/
  generate_graphs.py   deterministic fixture generator (seeded, reproducible)
  data/                generated fixtures -- gitignored, regenerate as needed
    *.edges            generic graphs (BFS/DFS/Dijkstra/MST/SCC)
    tsp/*.tsp           TSP city coordinates
    _smoke/             small fixed subset for fast iteration/CI-scale runs
  nim/bench_unigraph.nim         UniGraph harness (reference implementation)
  python/bench_networkx.py       networkx harness
  python/bench_igraph.py         python-igraph harness
  python/tsp_common.py           shared NN/2-opt used by both Python harnesses
  cpp/bench_boost.cpp, Makefile  Boost Graph Library harness
  rust/                          petgraph harness (Cargo project)
  correctness_check.py            cross-library digest comparison
  run_all.sh                      generates + builds + runs + checks everything
  results/results.csv              gitignored -- output of run_all.sh
```

## File formats

`data/*.edges` — one generic graph:
```text
V E DIRECTED WEIGHTED START
u v w
...  (E lines)
```
`V`/`E` are vertex/edge counts, `DIRECTED`/`WEIGHTED` are `0`/`1`. Undirected
graphs list each edge once — every harness adds both directions itself.
`START` is the fixed BFS/DFS/Dijkstra source vertex, **precomputed from the
raw edge list** (max-(out-)degree vertex, ties → lowest index) by
`generate_graphs.py`, not recomputed per harness. That matters: a library
that silently dedupes parallel edges could otherwise land on a different
max-degree vertex than one that doesn't, making digests diverge for a
reason that has nothing to do with the algorithm under test. Vertex 0 is
not used as the fixed start: on a sparse random graph it can be
near-isolated by pure chance, making the traversal trivial.

`data/tsp/*.tsp` — one TSP instance:
```text
N
x y
...  (N lines)
```
2D coordinates; distance is Euclidean; the graph is implicitly complete (no
edge list — materializing one isn't necessary for a coordinate-based
heuristic, and would make the largest instances impractical for the
kernel/edge-based libraries).

## Output

`results/results.csv`: `lang,library,algorithm,graph,n,m,directed,weighted,load_seconds,algo_seconds,digest`.
`load_seconds` is parsing + building the library's graph structure;
`algo_seconds` is the algorithm call alone. `digest` is the correctness
signal described below.

| algorithm | runs on | digest |
|---|---|---|
| `bfs` / `dfs` | every graph | count of vertices reachable from `START` (must match between bfs and dfs, and across libraries) |
| `dijkstra` | `WEIGHTED=1` | sum of all finite distances from `START`, rounded to 2 decimals |
| `mst_prim` / `mst_kruskal` (or `mst_default` where a library only has one) | `DIRECTED=0` | total spanning-tree/forest weight, rounded to 2 decimals |
| `scc_tarjan` | `DIRECTED=1` | number of strongly connected components |
| `tsp_nn` / `tsp_2opt` | every `.tsp` instance | tour cost, rounded to 2 decimals |

## TSP methodology

Nearest-neighbor and 2-opt are implemented **by hand, identically, in every
language** (none of these libraries ship a matching heuristic) directly
against the coordinate array — no graph object involved:

- **Nearest-neighbor**: from the current city, scan every unvisited city in
  index order, move to the strictly closest one; repeat until all visited;
  close the tour back to the start.
- **2-opt**: first-improvement. For up to 1000 full passes, try reversing
  every segment `[i, j]` in index order, keep the reversal immediately if it
  strictly lowers the *full* recomputed tour cost, stop early if a whole
  pass finds no improvement. This recomputes the full tour cost per
  candidate move rather than an incremental delta — less clever, but it's
  what every harness does, so the timing comparison stays apples-to-apples.

## Running it

```bash
cd benchmarks
python3 generate_graphs.py       # ~250 MB in data/, a few seconds
./run_all.sh --smoke             # fast: only the fixed small subset
./run_all.sh                     # slow: full sweep, do this on a quiet machine
python3 correctness_check.py     # also runs automatically at the end of run_all.sh
```

Per-toolchain dependencies (`run_all.sh` installs the Python ones itself):
- Nim: nothing beyond what `nimble install -y` already gets you.
- Python: `pip install --break-system-packages networkx python-igraph`.
- C++: a Boost installation with Boost.Graph headers (`brew install boost`
  on macOS, `apt install libboost-graph-dev` on Debian/Ubuntu) — header-only,
  no linking needed. `make -C cpp` picks up a few common include paths
  automatically; override with `make -C cpp BOOST_INC=/path/to/include` if
  needed.
- Rust: a working `cargo`/`rustc` install; `cargo build --release` in
  `rust/` fetches `petgraph` from crates.io on first build.

Nothing here is wired into CI (`.github/workflows/ci.yml`): the dependency
footprint (Boost, Rust, two extra Python packages) is heavy for a check
that's about comparison, not regression — this is a manually-run tool, not
a gate.
