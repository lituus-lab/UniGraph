# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook

nbInit(theme = useNimibook)
nbText: "# Graph Kernels"
nbText: """
**Kernels** are the low-level data storage backends in **UniGraph**. They determine:
- Memory layout
- Access patterns
- Performance characteristics

Choosing the right kernel is crucial for optimal performance.

## Kernel Comparison

There are **four** kernels, not three — `SeqKernel` is easy to miss since
it looks like `ListKernel` from the outside (same operations, same
complexity), but stores data differently underneath.

| Kernel | Space | Add Vertex | Add Edge | Has Edge | Best For |
|--------|-------|------------|----------|----------|----------|
| List | O(V + E) | O(1) | O(degree) | O(degree) | Sparse graphs |
| Seq | O(V + E) | O(1) amortized | O(degree) | O(degree) | Sparse graphs, cache locality |
| Matrix | O(V²) | O(1) | O(1) | O(1) | Dense graphs, hard-capped at 256 vertices |
| CSR | O(V + E) | O(1) before `build()`, then unsupported | O(degree) before `build()`, then unsupported | O(log degree) after `build()` | Static analysis |

## List Kernel (Default)

The **List Kernel** uses adjacency lists - each vertex maintains a list of its neighbors.

```nim
import UniGraph

var g = newImmutableGraph[string, float](Directed)
# Internally uses ListKernel by default
```

### Structure:
```
Vertex 0: [Edge to 1, Edge to 2]
Vertex 1: [Edge to 3]
Vertex 2: [Edge to 1, Edge to 3]
Vertex 3: []
```

### Advantages:
- ✅ **Space efficient** for sparse graphs (real-world networks)
- ✅ **Fast iteration** over neighbors
- ✅ **Dynamic**: Easy to add/remove vertices and edges

### Disadvantages:
- ❌ **Slower edge lookup**: O(degree) to check if edge exists
- ❌ **Cache unfriendly**: backed by `Table[VertexId, seq[Edge[E]]]` — hash
  lookups and per-vertex `seq` indirection, not the pointer-chasing of a
  classic linked adjacency list, but still not contiguous like `SeqKernel`

### Best Use Cases:
- Social networks (average person knows ~150 others)
- Web graphs (pages link to few others)
- Dependency graphs (tasks have few dependencies)

## Seq Kernel

The **Seq Kernel** has the same API and complexity as `ListKernel`, but
stores vertices and adjacency lists in flat `seq`s indexed by vertex slot
instead of a `Table` keyed by `VertexId`. Same big-O, better constants: no
hashing, and vertex data sits contiguously in memory.

```nim
import UniGraph
import UniGraph/kernels/seq_kernel

var kernel = newSeqKernel[string, float]()
```

### Advantages:
- ✅ **Cache friendly**: contiguous `seq` storage, no hashing
- ✅ **Dynamic**: same add/remove support as List Kernel
- ✅ **Stable ids**: reuses freed slots via a free list, same generation
  scheme as List Kernel (see Core Concepts)

### Disadvantages:
- ❌ Slot-based storage can waste space if vertex ids are sparse after many
  removals, until the free list catches up

### Best Use Cases:
- Same as List Kernel, when the extra cache-locality is worth a slightly
  more specialized implementation

## Matrix Kernel

The **Matrix Kernel** uses an adjacency matrix - a 2D array where `matrix[i][j]` stores the edge from i to j.

```nim
# Real backing storage (src/UniGraph/kernels/matrix_kernel.nim):
# matrix*: array[256, array[256, Option[E]]]
# Fixed at 256x256 regardless of the requested capacity — newMatrixKernel
# raises RangeDefect if you ask for more.
```

### Structure:
```
    0   1   2   3
0 [ 0  w1   w2   0 ]
1 [ 0   0    0  w3 ]
2 [ 0  w4    0  w5 ]
3 [ 0   0    0   0 ]
```

### Advantages:
- ✅ **O(1) edge lookup**: Direct array access
- ✅ **Cache friendly**: Contiguous memory
- ✅ **Simple**: No pointer chasing

### Disadvantages:
- ❌ **O(V²) space**: Wasteful for sparse graphs
- ❌ **Slow vertex removal**: O(V) to shift rows/columns
- ❌ **Hard-capped at 256 vertices**: not a soft guideline — `newMatrixKernel`
  raises past it, there's no larger option

### Best Use Cases:
- Dense graphs (most vertices connected), 256 vertices or fewer
- Small graphs where V² fits in cache
- Applications needing frequent edge queries

## CSR Kernel (Compressed Sparse Row)

The **CSR Kernel** is optimized for **read-only** scenarios, but it has a
**two-phase lifecycle**, not a build-once constructor:

1. **Loading phase**: `addVertex`/`addEdge` work normally, appending into
   temporary per-vertex buffers.
2. Call **`build()`**: compresses those buffers into the three flat arrays
   below and sorts each row's column indices (enabling `hasEdge`'s binary
   search). The build costs O(V + E + Σ d log d), including each row sort.
3. **Query phase**: after `build()`, the kernel is immutable —
   `addVertex`/`addEdge` **raise `ValueError`**; `removeVertex`/`removeEdge`
   don't raise, they just always return `false` (a no-op, not an error).

```nim
import UniGraph
import UniGraph/kernels/csr_kernel

var kernel = newCsrKernel[string, float]()
let a = kernel.addVertex("A")   # fine: not built yet
let b = kernel.addVertex("B")
discard kernel.addEdge(a, b, 1.0)
kernel.build()                  # compress + sort; now immutable
# kernel.addEdge(a, b, 2.0) would raise ValueError here
```

```nim
# The three arrays build() produces:
values:      [edge_data_0, edge_data_1, ...]
colIndices:  [target_vertex_0, target_vertex_1, ...]
rowOffsets:  [start_index_for_vertex_0, start_index_for_vertex_1, ...]
```

### Advantages:
- ✅ **Most compact**: Minimal memory overhead
- ✅ **Fast iteration**: Sequential memory access
- ✅ **Cache optimal**: Prefetcher-friendly

### Disadvantages:
- ❌ **Immutable after `build()`**: no more mutation once you've compressed
- ❌ **Build cost**: O(V + E + Σ d log d), paid once at `build()`

### Best Use Cases:
- Static graphs (road networks, circuit layouts)
- Read-heavy workloads (repeated traversals)
- Memory-constrained environments

## Kernel Selection Guide

### Choose List Kernel when:
- Graph is **sparse** (E << V²)
- You need **dynamic updates**
- You iterate over neighbors frequently

### Choose Matrix Kernel when:
- Graph is **dense** (E ≈ V²)
- You need **frequent edge lookups**
- Graph size is **small and fixed**

### Choose CSR Kernel when:
- Graph is **static** (no modifications after an initial `build()`)
- You need **maximum performance** for traversals
- **Memory efficiency** is critical

## Example: Kernel Performance Comparison

```nim
import UniGraph, UniGraph/algorithms/traversals, UniGraph/visitor, std/times

# Sparse graph: a chain of 1000 vertices (999 edges) built on the List Kernel.
var g = newImmutableGraph[int, float](Directed)
var ids: seq[VertexId] = @[]
for i in 0..<1000:
  var id: VertexId
  (g, id) = g.addVertex(i)
  ids.add id
for i in 0..<999:
  g = g.addEdge(ids[i], ids[i+1], 1.0)

let t1 = cpuTime()
var vis = newVisitor[float]()
g.kernel.bfs(ids[0], vis)
echo "List kernel BFS over 1000 vertices: ", cpuTime() - t1, " seconds"

# A MatrixKernel storing the same graph would allocate 1000 x 1000 = 1,000,000
# cells for 999 edges; the List/Seq/CSR kernels store roughly one entry per
# edge -- about 1000x more space-efficient for a graph this sparse.
```

## Practical Example

```nim
import UniGraph
import UniGraph/kernels/csr_kernel
import std/tables

# Social network (sparse, keeps changing) - use the immutable-graph wrapper
# over ListKernel (or SeqKernel for the same API with better cache locality).
let people = ["Alice", "Bob", "Charlie"]
var socialNet = newImmutableGraph[string, float](Directed)
var personId = initTable[string, VertexId]()
for name in people:
  var id: VertexId
  (socialNet, id) = socialNet.addVertex(name)
  personId[name] = id

let friendships = [("Alice", "Bob", 0.9), ("Bob", "Charlie", 0.7)]
for (a, b, strength) in friendships:
  socialNet = socialNet.addEdge(personId[a], personId[b], strength)

# Road network (loaded once, then queried millions of times) - CsrKernel.
let cities = ["Paris", "Lyon", "Marseille"]
var roads = newCsrKernel[string, float]()
var cityId = initTable[string, VertexId]()
for name in cities:
  cityId[name] = roads.addVertex(name)

let roadSegments = [("Paris", "Lyon", 465.0), ("Lyon", "Marseille", 315.0)]
for (fromCity, toCity, distanceKm) in roadSegments:
  discard roads.addEdge(cityId[fromCity], cityId[toCity], distanceKm)
roads.build()  # compress + sort; roads is immutable from here on

# Now run millions of route queries efficiently, e.g.:
echo "Paris -> Lyon exists: ", roads.hasEdge(cityId["Paris"], cityId["Lyon"])
```

**Verified output**:
```
Paris -> Lyon exists: true
```

## References

- Wikipedia: [Adjacency list](https://en.wikipedia.org/wiki/Adjacency_list) —
  `ListKernel`/`SeqKernel`
- Wikipedia: [Adjacency matrix](https://en.wikipedia.org/wiki/Adjacency_matrix) —
  `MatrixKernel`
- Wikipedia: [Sparse matrix § Compressed sparse row (CSR, CRS or Yale format)](https://en.wikipedia.org/wiki/Sparse_matrix#Compressed_sparse_row_(CSR,_CRS_or_Yale_format)) —
  `CsrKernel`'s three flat arrays
- Wikipedia: [Time complexity](https://en.wikipedia.org/wiki/Time_complexity)
"""
nbSave
