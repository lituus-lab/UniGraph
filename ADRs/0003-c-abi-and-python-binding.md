<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0003: C ABI and Python binding

- Status: Accepted
- Date: 2026-07-15
- Scope: `src/UniGraph/c_api.nim`, `include/UniGraph.h`, `py/`

## Decision

- The engine is pure Nim; a thin C ABI (`src/UniGraph/c_api.nim`) is the
  only supported entry point for foreign callers, built
  `--app:staticlib`/`--app:lib --noMain --mm:arc -d:release` into
  `libUniGraph.a` / `libUniGraph.so`.
- The C header (`include/UniGraph.h`) is hand-written and kept in sync
  with `c_api.nim`; `tests/c` links the header against the built lib, so a
  renamed or retyped symbol fails to link — the C test is the ABI drift
  detector. Nim's `--header:` auto-generation is not used.
- `--mm:arc`: a deterministic memory model for foreign callers, with no
  cycle collector running behind the host's back. `--noMain`: the host
  controls when `NimMain` runs. A C caller must invoke `ug_init()` exactly
  once before any other ABI function; repeated calls are harmless. The Python
  extension performs this initialization during import.
- The generic Nim API is monomorphized as
  `MutableGraph[ListKernel[int64, float64], int64, float64]`. Its graph
  operations, algorithms, rendering, and statistics are exposed in C and
  Python. Vertex removal is excluded because the plain integer foreign ID
  cannot carry `VertexId`'s generation counter. Callback-oriented tracing and
  direct file/stdout helpers are represented by traversal results and returned
  rendering strings instead of foreign callbacks or hidden side effects.
- The Python binding is a Cython extension over the shared library, located
  relative to the extension through `$ORIGIN` on ELF systems or `@loader_path`
  on macOS. Windows links the Nim static library into the extension.

## Surface mapping

| Nim surface | C/Python representation |
|---|---|
| `VertexId`, `Vertex`, `Edge`, their constructors, and equality/order | Integer vertex IDs, integer labels, and `UgEdge`; construction is performed by graph operations. |
| `MutableGraph` construction, counts, vertex lookup/addition, and edge lookup/addition/removal | `ug_graph_new`, count/get/add/has/remove functions; Python `Graph` methods and properties. |
| `vertices`, `edges`, `neighbors`, `inNeighbors`, `outNeighbors` | Measured buffers in C; lists returned by Python. |
| BFS/DFS, `reachableVertices`, `isConnected` | Traversal buffers and `ug_graph_is_connected`; Python traversal methods. Recursive/iterative Nim overloads map to one result-oriented foreign operation each. |
| Dijkstra overloads, `reconstructPath`, A*, Bellman–Ford | Distance maps and path operations. A* uses a zero heuristic because a foreign callback would not have a safe ownership or exception contract. |
| Prim, Kruskal, Tarjan, Kosaraju, articulation points | Edge or component buffers; matching Python methods. Internal DFS/reversal helpers remain implementation details. |
| Naive, 2-opt, and nearest-neighbor TSP | Path buffers plus costs; matching Python tuple results. |
| `toAscii`, `toDot`, `degreeDistribution` | Measured UTF-8 buffers or typed count buffers; Python strings or lists. |

The four generic kernel types, immutable copy-returning graph wrapper, generic
payload types, and visitor callbacks have no stable monomorphic C
representation. `ListKernel[int64, float64]` and the mutable wrapper are the
chosen foreign instantiation. Vertex removal is excluded because its generation
counter cannot be represented by the foreign integer ID. `saveDot`, `render`,
`printTrace`, and `printStats` are effectful conveniences over returned data;
foreign callers use the corresponding string, traversal, or statistics result
and choose their own I/O policy.
