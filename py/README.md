<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# unigraph

Graph data structures and classic graph algorithms for Python, backed by the
native [UniGraph](https://github.com/lituus-lab/UniGraph) engine written in
Nim.

`unigraph` provides a compact, concrete graph for signed 64-bit vertex labels
and `float64` edge weights. Graphs may be directed or undirected; the Python
surface uses simple-graph semantics, so self-loops and parallel edges are
rejected. Traversals, shortest paths, spanning forests, strongly connected
components, TSP solvers, and DOT/ASCII rendering all run in the native core.

## Install

```bash
pip install unigraph
```

Prebuilt wheels include the native UniGraph library for Linux, macOS, and
Windows on CPython 3.10–3.14. Installing a wheel needs neither Nim nor a C
compiler.

## Quick start

```python
import unigraph

g = unigraph.Graph(directed=False)
paris = g.add_vertex(75)
lyon = g.add_vertex(69)
marseille = g.add_vertex(13)

g.add_edge(paris, lyon, 465.0)
g.add_edge(lyon, marseille, 315.0)
g.add_edge(paris, marseille, 775.0)

g.bfs(paris)                         # [paris, lyon, marseille]
g.dijkstra(paris)[marseille]         # 775.0
g.shortest_path(paris, marseille)    # ([paris, marseille], 775.0)
g.kruskal()                          # two edges, total weight 780.0
print(g.to_dot())                    # Graphviz DOT
```

Vertex IDs are stable handles returned by `add_vertex`; labels remain
available through `get_vertex_data`. Algorithms consume IDs, not labels, so
duplicate labels are allowed without making vertices ambiguous.

## What's included

| Category | Python API |
|---|---|
| Graph construction | `Graph`, `add_vertex`, `add_edge`, `remove_edge`, `vertex_count`, `edge_count` |
| Inspection | `vertices`, `edges`, `neighbors`, `in_neighbors`, `out_neighbors`, `get_vertex_data`, `get_edge_weight`, `has_edge` |
| Traversal | `bfs`, `dfs`, `reachable`, `is_connected` |
| Shortest paths | `dijkstra`, `shortest_path`, `a_star`, `bellman_ford` |
| Spanning forest | `prim`, `kruskal` on undirected graphs |
| Components | `strongly_connected_components`, `kosaraju`, `articulation_points` |
| Traveling salesperson | `tsp_naive`, `tsp_nearest`, `tsp_2opt` |
| Presentation | `to_ascii`, `to_dot`, `degree_distribution` |

`shortest_path` returns `None` when the goal is unreachable. Bellman–Ford
returns `(distances, has_negative_cycle)`; when the flag is true, do not treat
the partial distances as shortest paths. Prim, Kruskal, and articulation
points reject directed graphs with `ValueError`. Exact TSP is intentionally
limited to at most ten vertices; the nearest-neighbor and 2-opt methods are
heuristics and do not promise the optimum.

The full Nim API is generic over vertex data, edge data, and four storage
kernels. Python deliberately exposes one stable ABI specialization; use the
[Nim API](https://lituus-lab.github.io/UniGraph/) when custom payload types,
multigraphs, or kernel selection are required.

## Links

- Source, Nim API, C ABI, ADRs, and teaching book: <https://github.com/lituus-lab/UniGraph>
- Documentation: <https://lituus-lab.github.io/UniGraph/>
- Issues: <https://github.com/lituus-lab/UniGraph/issues>
- License: Apache-2.0

## Development

Building from source requires Nim 2.2, Nimble, a C compiler, Cython, and
Python development headers.

```bash
nimble install -y
nimble pyLib
cd py
python3 -m pip install -e .
python3 -m pytest -q
```

On Windows, run the commands from a Developer Command Prompt and use `python`
if `python3` is not available.
