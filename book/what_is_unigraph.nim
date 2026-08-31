# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nbText: "# What is UniGraph?"
nbText: """
**UniGraph** is a generic, pedagogical graph data structure library for Nim.

It builds on Nim's systems-programming foundation with a focus on educational transparency and functional purity.

## Why UniGraph?

### The Problem

Graph libraries tend to pull in two directions: approachable enough to learn
algorithms from, and fast/robust enough to actually use. Optimizing hard for
one often costs the other — a library tuned for raw throughput tends to
hide its internals behind opaque, optimized code, while one built for
teaching tends to skip the performance-oriented data structures production
use needs.

### The UniGraph Goal

**UniGraph** aims at both. `benchmarks/` in the repository runs the same
algorithms through UniGraph, networkx, igraph, Boost Graph Library, and
petgraph on the same generated graphs and checks that they agree on the
answer before comparing timings — see `benchmarks/README.md` for the
methodology, what it does and doesn't cover, and how to run it yourself:

- ✅ **Easy to understand**: Clear code structure, visitor-based tracing
- 🎯 **Performance-oriented**: Zero-cost generic abstractions, multiple kernel backends
- ✅ **Pedagogical**: Step-by-step algorithm visualization
- ✅ **Practical**: a C ABI and Python binding make it usable from other languages, not just Nim

## Design Philosophy

### 1. Compile-Time Specialization

```nim
# Each (kernel, vertex type, edge type) combination is monomorphized --
# no vtables, no boxing.
type
  MyGraph = ImmutableGraph[ListKernel[int, float], int, float]
```

The compiler generates a dedicated instantiation for your specific types,
the same way it would for any other generic Nim type.

### 2. Immutability by Default

```nim
var g = newImmutableGraph[string, float](Directed)
let (g2, idA) = g.addVertex("A")  # Returns (new graph, new id); g unchanged
```

Benefits:
- Predictable behavior
- Earlier graph values are not changed by wrapper operations
- Easy undo/redo

The kernel field is public for algorithms and advanced use. Concurrent code
must not mutate that field while another thread reads it.

### 3. Multiple Backends

Choose the right data structure for your use case:

| Kernel | Best For |
|--------|----------|
| List | Sparse graphs (social networks) |
| Seq | Same as List, better cache locality |
| Matrix | Dense graphs, hard-capped at 256 vertices |
| CSR | Static analysis (read-only) |

### 4. Educational Tracing

```nim
var visitor = newVisitor[float]()
g.kernel.bfs(startVertex, visitor)

for step in visitor.trace:
  echo step  # See every step of the algorithm
```

## Design Choices Worth Calling Out

### Stable Vertex IDs

Following the same pattern as Rust's `petgraph::StableGraph`, removing a vertex
doesn't invalidate other vertex IDs:

```nim
var g = newImmutableGraph[string, float](Directed)
# addVertex on the wrapper returns (newGraph, id) -- use it, not g.kernel
# directly, or g.vertexCount won't reflect what you just added or removed.
var v1, v2, v3: VertexId
(g, v1) = g.addVertex("A")  # id=0
(g, v2) = g.addVertex("B")  # id=1
(g, v3) = g.addVertex("C")  # id=2

g = g.removeVertex(v2)  # Remove B

# v1 and v3 are STILL VALID!
# UniGraph uses generation counters to prevent dangling references
```

### Visitor Pattern for Learning

Every traversal algorithm supports the Visitor pattern:

```nim
# Watch DFS execute step by step
var visitor = newVisitor[float]()
g.kernel.dfs(startVertex, visitor)

echo "Discovery order: ", visitor.discovered
echo "Finish order: ", visitor.finished
echo "Edge traversals: ", visitor.edgeTraversals
```

### One Small Dependency

UniGraph's core is the Nim standard library plus NimContracts, used for
Design by Contract (`require:`/`ensure:` on `addVertex`/`removeVertex` and
a few algorithm postconditions — see the "Immutability by Default" and
algorithm chapters). Contracts compile away entirely under `-d:release`.

```nim
# Just import and use
import UniGraph
```

## Example: Building a Social Network

```nim
import UniGraph
import std/options

# Create a directed graph (follower relationships)
var socialNet = newImmutableGraph[string, float](Directed)

# Add users. addVertex on the wrapper returns (newGraph, id) -- use it, not
# socialNet.kernel directly, or socialNet.vertexCount won't reflect this.
var alice, bob, charlie, diana: VertexId
(socialNet, alice) = socialNet.addVertex("Alice")
(socialNet, bob) = socialNet.addVertex("Bob")
(socialNet, charlie) = socialNet.addVertex("Charlie")
(socialNet, diana) = socialNet.addVertex("Diana")

# Add follower relationships (edge weight = relationship strength)
socialNet = socialNet.addEdge(alice, bob, 0.8)    # Alice follows Bob
socialNet = socialNet.addEdge(bob, charlie, 0.6)  # Bob follows Charlie
socialNet = socialNet.addEdge(charlie, alice, 0.9) # Charlie follows Alice
socialNet = socialNet.addEdge(diana, alice, 0.7)  # Diana follows Alice

# Find who Alice follows
echo "Alice's connections:"
for edge in socialNet.kernel.neighbors(alice):
  let target = socialNet.getVertex(edge.target).get()
  echo "  → ", target.data, " (strength: ", edge.data, ")"

# BFS to find all users reachable from Alice
var visitor = newVisitor[float]()
socialNet.kernel.bfs(alice, visitor)

echo "\nUsers reachable from Alice: ", visitor.visitOrder.len
```

## Performance Characteristics

| Operation | List Kernel | Seq Kernel | Matrix Kernel (max 256 vertices) | CSR Kernel |
|-----------|-------------|------------|-----------------------------------|------------|
| Add Vertex | O(1) | O(1) amortized | O(1) | N/A after `build()` |
| Add Edge | O(degree) | O(degree) | O(1) | O(degree) before `build()`, then N/A |
| Remove Vertex | O(V + E) | O(V + E) | O(V) | N/A |
| Has Edge | O(degree) | O(degree) | O(1) | O(log degree) |
| Iterate Neighbors | O(degree) | O(degree) | O(V) | O(degree) |
| Space | O(V + E) | O(V + E) | O(V²) | O(V + E) |

These are asymptotic complexities derived from each kernel's data structure,
not measured throughput — see `benchmarks/README.md` in the repository for
wall-clock comparisons against networkx, igraph, Boost Graph Library, and
petgraph (run on your own machine; see that file for the methodology and
its limits).

## When to Use UniGraph

### Good Fit

- ✅ Learning graph algorithms
- ✅ Teaching data structures
- ✅ Prototyping new algorithms
- ✅ Graphs bounded by available memory on List/Seq/CSR — Matrix is hard-capped
  at 256 vertices
- ✅ Applications needing tracing/debugging

### Consider Alternatives When

- ❌ Massive graphs (billions of vertices) - use specialized big-data tools
- ❌ Distributed computing - use GraphX, Giraph
- ❌ GPU acceleration - use Gunrock, cuGraph
- ❌ Dynamic graphs at massive scale - use specialized streaming tools

## References

- Wikipedia: [Graph (abstract data type)](https://en.wikipedia.org/wiki/Graph_(abstract_data_type))
- Wikipedia: [Design by contract](https://en.wikipedia.org/wiki/Design_by_contract) —
  the `require`/`ensure` discipline NimContracts brings to `addVertex`/`removeVertex`
- Wikipedia: [Generic programming](https://en.wikipedia.org/wiki/Generic_programming) —
  the compile-time specialization behind `ImmutableGraph[K, V, E]`
- Wikipedia: [Foreign function interface](https://en.wikipedia.org/wiki/Foreign_function_interface) —
  what the C ABI (`ug_*`) and the Cython-based Python binding build on
- [NimContracts](https://github.com/lbartoletti/NimContracts) — the
  Design by Contract library used in `graph.nim` and the `mst`/`tsp`/`scc`
  algorithm postconditions

## Next Steps

Ready to start? See [Installation](installation.html) to get UniGraph set up!
"""
nbSave
