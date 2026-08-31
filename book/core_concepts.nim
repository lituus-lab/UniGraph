# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nbText: "# Core Concepts"
nbText: """
This chapter covers the fundamental concepts of **UniGraph** and graph theory basics.

## What is a Graph?

A **graph** is a mathematical structure consisting of:
- **Vertices (nodes)**: The fundamental entities being connected
- **Edges**: The connections between vertices

Graphs can model:
- Social networks (people and friendships)
- Computer networks (routers and connections)
- Dependencies (tasks and prerequisites)
- Maps (locations and roads)

## Vocabulary

A handful of terms recur throughout every chapter of this book. Defining
them once here means later chapters (Traversals, Shortest Path, MST, SCC,
TSP) can use them without re-explaining:

- **Degree**: the number of edges incident to a vertex. In a directed graph,
  a vertex has an **in-degree** (incoming edges) and an **out-degree**
  (outgoing edges); "degree" alone usually means their sum, or the plain
  edge count for an undirected graph.
- **Simple path**: a sequence of vertices where each consecutive pair is
  joined by an edge, with no vertex repeated. "Shortest Path" (the algorithms
  chapter) finds the path with the lowest total edge weight between two
  vertices.
- **Cycle**: a path that returns to its starting vertex (the only repeated
  vertex is the first/last one). A graph with no cycles is **acyclic**; a
  directed graph with no cycles is a **DAG** (directed acyclic graph, used
  in the Strongly Connected Components chapter). The Traveling Salesman
  Problem searches for a specific kind of cycle — one that visits every
  vertex exactly once (a Hamiltonian cycle).
- **Connected**: an undirected graph is connected if there is a path
  between every pair of vertices. A **connected component** is a maximal
  set of vertices that are pairwise connected; a disconnected graph has
  more than one. The directed analogue — reachability in both directions —
  is what Strongly Connected Components (SCC) computes. The Minimum
  Spanning Tree chapter assumes a connected graph for its textbook
  definition, then explains what UniGraph's implementations actually do
  when that assumption doesn't hold.
- **Tree**: a connected, acyclic undirected graph. A tree with `V` vertices
  always has exactly `V - 1` edges. A **spanning tree** of a graph is a
  tree that touches every vertex using only that graph's edges (see
  Minimum Spanning Tree); a **forest** is a disjoint union of trees (what
  you get from a spanning-tree algorithm run on a disconnected graph).

## Graph Types in UniGraph

### Direction

**UniGraph** supports two direction types:

```nim
type Direction = enum
  Directed   ## Edge from source to target only
  Undirected ## Edge mirrored (both directions)
```

**Directed Graph**: Edges have a direction (A → B doesn't imply B → A)

```
A → B → C
↓
D
```

**Undirected Graph**: Edges go both ways (A — B means A ↔ B)

```
A — B
|   |
D — C
```

### Graph Type Variants

```nim
type GraphType = enum
  Simple   ## No self-loops, no parallel edges (default)
  Multi    ## Allows parallel edges between same vertices
  Pseudo   ## Allows both self-loops and parallel edges
```

**Simple Graph** (default):
- No edge from a vertex to itself (no self-loops)
- At most one edge between any two vertices

**Multi Graph**:
- Allows multiple edges between the same pair of vertices
- Useful for modeling multiple relationships

**Pseudo Graph**:
- Allows both self-loops and parallel edges
- Most flexible but requires careful handling

## Vertex ID Stability

**UniGraph** uses a **generation counter** pattern (inspired by Rust's Petgraph):

```nim
type VertexId = object
  id*: int         # The vertex index
  generation*: uint16  # Generation counter
```

### Why Generation Counters?

When a vertex is removed, its ID slot can be reused. The generation counter prevents **dangling references**:

```
Time 0: Add vertex A → id=0, generation=0
Time 1: Remove vertex A
Time 2: Add vertex B → id=0, generation=1  (reuses slot safely!)
```

Old references to `VertexId(id: 0, generation: 0)` won't accidentally access vertex B.

## Immutability by Default

**UniGraph** follows functional programming principles:

```nim
let g = newImmutableGraph[string, float](Directed)
let (g2, idA) = g.addVertex("A")  # Returns (NEW graph, new vertex's id); g unchanged
let (g3, idB) = g2.addVertex("B") # g2 unchanged; the id is needed to add edges next
```

`addVertex` returns a **tuple**, not just a graph — you need the id to refer
to the vertex you just added (for `addEdge`, for example), so it comes back
alongside the new graph rather than making you look it up separately.

### Benefits:
- **Predictability**: No hidden mutations
- **Safer sharing**: wrapper operations do not mutate earlier graph values;
  callers must still avoid mutating the exported `kernel` field concurrently
- **Undo/Redo**: Keep previous versions easily

### Performance:
Nim's `seq` and `Table` assignments have value semantics and may copy their
full contents unless move elision applies. Copying an immutable graph is
therefore not generally O(1).

## The Visitor Pattern

For pedagogical tracing, **UniGraph** uses the Visitor pattern:

```nim
var visitor = newVisitor[float]()
g.kernel.bfs(startVertex, visitor)

for step in visitor.trace:
  echo step  # Step-by-step execution log
```

The visitor captures:
- Vertex discoveries
- Edge traversals
- Processing order
- Finish events (for DFS)

## Putting It Together: A Complete Example

A single program touching every concept from this chapter: `Undirected` +
`Simple`, generation-counter id stability across a `removeVertex` +
`addVertex`, immutability (the pre-removal graph stays valid), and a
`Visitor`-traced BFS.

```nim
import UniGraph
import std/options

# Undirected simple graph: string vertex data, float edge weights.
var g = newImmutableGraph[string, float](Undirected, Simple)

var vA, vB, vC: VertexId
(g, vA) = g.addVertex("A")
(g, vB) = g.addVertex("B")
(g, vC) = g.addVertex("C")

g = g.addEdge(vA, vB, 1.0)
g = g.addEdge(vB, vC, 2.0)

echo "vB = (id: ", vB.id, ", generation: ", vB.generation, ")"

# Remove B, then add a new vertex: it reuses B's freed slot id but bumps
# the generation counter, so the old vB handle can never alias it.
let gAfterRemove = g.removeVertex(vB)
let (gWithD, vD) = gAfterRemove.addVertex("D")

echo "vD = (id: ", vD.id, ", generation: ", vD.generation, ")"
echo "Same slot id? ", vB.id == vD.id
echo "Same VertexId (id AND generation)? ", vB == vD

# g (before removal) is untouched -- immutability.
echo "g still has ", g.vertexCount, " vertices and still knows vB: ", g.getVertex(vB).isSome
echo "gWithD has ", gWithD.vertexCount, " vertices"

# Trace a BFS with the Visitor pattern
var visitor = newVisitor[float]()
g.kernel.bfs(vA, visitor)
echo "BFS trace:"
for step in visitor.trace:
  echo "  ", step
```

**Verified output**:
```
vB = (id: 1, generation: 0)
vD = (id: 1, generation: 1)
Same slot id? true
Same VertexId (id AND generation)? false
g still has 3 vertices and still knows vB: true
gWithD has 3 vertices
BFS trace:
  Step 1: Discovered vertex 0 (order: 0, time: 0)
  Step 2: Traversed edge 0 -> 1 (ekTree)
  Step 3: Discovered vertex 1 (order: 1, time: 1)
  Step 4: Traversed edge 1 -> 0 (ekBack)
  Step 5: Traversed edge 1 -> 2 (ekTree)
  Step 6: Discovered vertex 2 (order: 2, time: 2)
  Step 7: Traversed edge 2 -> 1 (ekBack)
```

## References

- Wikipedia: [Graph (discrete mathematics)](https://en.wikipedia.org/wiki/Graph_(discrete_mathematics))
- Wikipedia: [Directed graph](https://en.wikipedia.org/wiki/Directed_graph)
- Wikipedia: [Multigraph](https://en.wikipedia.org/wiki/Multigraph)
- Wikipedia: [Loop (graph theory)](https://en.wikipedia.org/wiki/Loop_(graph_theory))
- Wikipedia: [Persistent data structure](https://en.wikipedia.org/wiki/Persistent_data_structure) —
  the immutability model `ImmutableGraph` follows
- Wikipedia: [Tree (graph theory)](https://en.wikipedia.org/wiki/Tree_(graph_theory))
- [petgraph](https://docs.rs/petgraph/latest/petgraph/) — the Rust library
  whose generation-counter `StableGraph` pattern UniGraph's `VertexId` is
  based on

## Next Steps

With the vocabulary and core types in hand, head to [Quickstart](quickstart.html) to write your first UniGraph program.
"""
nbSave
