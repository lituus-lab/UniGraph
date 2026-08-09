# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook

nbInit(theme = useNimibook)
nbText: "# Quickstart"
nbText: """
Let's create your first graph and run some algorithms! This guide will get you up and running in 5 minutes.

## Creating a Graph

### Step 1: Import UniGraph

```nim
import UniGraph
```

### Step 2: Create a directed graph

```nim
# Create an immutable directed graph with string vertices and float edge weights
var g = newImmutableGraph[string, float](Directed)
```

### Step 3: Add vertices

```nim
# addVertex on the wrapper returns (newGraph, id) — use it, not g.kernel
# directly, or vertexCount below won't reflect what you just added.
let (g1, vA) = g.addVertex("A")
let (g2, vB) = g1.addVertex("B")
let (g3, vC) = g2.addVertex("C")
let (g4, vD) = g3.addVertex("D")
g = g4

echo "Added ", g.vertexCount, " vertices"
```

### Step 4: Add edges

```nim
# Add edges (returns new graph instance due to immutability)
g = g.addEdge(vA, vB, 1.0)
g = g.addEdge(vA, vC, 2.0)
g = g.addEdge(vB, vD, 3.0)
g = g.addEdge(vC, vD, 4.0)

echo "Graph now has ", g.edgeCount, " edges"
```

## Basic Operations

### Check if an edge exists

```nim
if g.hasEdge(vA, vB):
  echo "Edge A -> B exists"
```

### Get edge data

```nim
let edgeData = g.getEdge(vA, vB)
if edgeData.isSome:
  echo "Edge weight: ", edgeData.get()
```

### Get vertex data

```nim
let vertex = g.getVertex(vA)
if vertex.isSome:
  echo "Vertex A data: ", vertex.get().data
```

## Traversal Algorithms

### Breadth-First Search (BFS)

```nim
# Tracing fragment; `g` and `vA` come from the graph constructed above.

# Create a visitor to trace the execution
var visitor = newVisitor[float]()

# Run BFS from vertex A
g.kernel.bfs(vA, visitor)

# Print the execution trace
echo "BFS Execution:"
visitor.printTrace()

# Get visit order
echo "Visit order: ", visitor.visitOrder
```

**Verified output** (`bfs` calls `onEdge` for every edge it looks at, even
ones to an already-visited target — the 2->3 edge below is one of those, not
a bug; see Traversals' "Edge Classification" section for what `(ekTree)`/
`(ekBack)` mean and why BFS never produces `ekForward`/`ekCross`):
```
BFS Execution:
Step 1: Discovered vertex 0 (order: 0, time: 0)
Step 2: Traversed edge 0 -> 1 (ekTree)
Step 3: Discovered vertex 1 (order: 1, time: 1)
Step 4: Traversed edge 0 -> 2 (ekTree)
Step 5: Discovered vertex 2 (order: 2, time: 2)
Step 6: Traversed edge 1 -> 3 (ekTree)
Step 7: Discovered vertex 3 (order: 3, time: 3)
Step 8: Traversed edge 2 -> 3 (ekBack)
Visit order: @[(id: 0, generation: 0), (id: 1, generation: 0), (id: 2, generation: 0), (id: 3, generation: 0)]
```

`visitOrder` is `seq[VertexId]`, and `VertexId` has no `$` override, so
`echo` prints the raw `(id, generation)` fields, not a plain `[0, 1, 2, 3]`.
Map to `.id` first if you want the bare numbers:
`echo visitor.visitOrder.mapIt(it.id)` (needs `import std/sequtils`).

### Depth-First Search (DFS)

```nim
var visitor = newVisitor[float]()
g.kernel.dfs(vA, visitor)

echo "DFS Execution:"
visitor.printTrace()
```

**Verified output** — unlike BFS, DFS calls `onFinish`, so its edge
classification can produce all four kinds. Here `2 -> 3` is `ekCross`: `D`
(vertex 3) is already finished by the time DFS follows `C -> D`, and `D`'s
discovery time (2) is *before* `C`'s (5):
```
DFS Execution:
Step 1: Discovered vertex 0 (order: 0, time: 0)
Step 2: Traversed edge 0 -> 1 (ekTree)
Step 3: Discovered vertex 1 (order: 1, time: 1)
Step 4: Traversed edge 1 -> 3 (ekTree)
Step 5: Discovered vertex 3 (order: 2, time: 2)
Step 6: Finished vertex 3 (time: 3)
Step 7: Finished vertex 1 (time: 4)
Step 8: Traversed edge 0 -> 2 (ekTree)
Step 9: Discovered vertex 2 (order: 3, time: 5)
Step 10: Traversed edge 2 -> 3 (ekCross)
Step 11: Finished vertex 2 (time: 6)
Step 12: Finished vertex 0 (time: 7)
```

## Shortest Path with Dijkstra

```nim
# Define weight function
proc weight(edge: Edge[float]): float =
  edge.data

# Run Dijkstra's algorithm
let result = g.kernel.dijkstra(vA, weight)

# Print distances
for vertex in g.kernel.vertices():
  let dist = result.distances.getOrDefault(vertex.id, Inf)
  echo "Distance from A to ", vertex.data, ": ", dist

# Reconstruct path to D
if vD in result.parents:
  let path = reconstructPath(result.parents, vD)
  echo "Path to D: ", path
```

## Visualization

### ASCII Rendering

```nim
echo "Graph structure:"
g.kernel.render()
```

**Verified output** (`kernel.vertices()` iterates in `Table` hash order,
not insertion order — see Shortest Path's Dijkstra example for the same
caveat; `render` also prints a trailing blank line, since it's
`echo kernel.toAscii(...)` and `toAscii`'s result already ends in `\n`):
```
Graph structure:
  [1] -> 3
  [3] (isolated)
  [0] -> 1, 2
  [2] -> 3

```

### Export to Graphviz

```nim
# Save to DOT file
g.kernel.saveDot("mygraph.dot", directed = true)

# Then in terminal:
# dot -Tpng mygraph.dot -o mygraph.png
```

## Complete Example

Here's a complete working program:

```nim
import UniGraph
import std/options

# Create a graph representing city distances
var cities = newImmutableGraph[string, float](Undirected)

# Add cities — addVertex returns (newGraph, id); chain both
let (citiesWithParis, paris) = cities.addVertex("Paris")
let (citiesWithLyon, lyon) = citiesWithParis.addVertex("Lyon")
let (citiesWithMarseille, marseille) = citiesWithLyon.addVertex("Marseille")
cities = citiesWithMarseille

# Add distances (in km)
cities = cities.addEdge(paris, lyon, 450.0)
cities = cities.addEdge(lyon, marseille, 310.0)
cities = cities.addEdge(paris, marseille, 775.0)

# Display graph
echo "French Cities Graph"
echo "==================="
cities.kernel.render()

# Find shortest path
proc weight(edge: Edge[float]): float = edge.data

let result = cities.kernel.dijkstra(paris, weight)
echo "\nDistances from Paris:"
for vertex in cities.kernel.vertices():
  let dist = result.distances.getOrDefault(vertex.id, Inf)
  echo "  ", vertex.data, ": ", dist, " km"

# Check direct connection
if cities.hasEdge(paris, marseille):
  let direct = cities.getEdge(paris, marseille).get()
  echo "\nDirect Paris-Marseille: ", direct, " km"
```

**Verified output** (the distances are correct; the vertex print order is
Table-iteration order, not insertion order — see Shortest Path's Dijkstra
example for the same caveat):
```
French Cities Graph
===================
  [1] -> 0, 2
  [0] -> 1, 2
  [2] -> 1, 0


Distances from Paris:
  Lyon: 450.0 km
  Paris: 0.0 km
  Marseille: 760.0 km

Direct Paris-Marseille: 775.0 km
```

## Next Steps

Now that you have the basics, explore:

1. **[Graph Kernels](kernels.html)** - Learn about List, Seq, Matrix, and CSR backends
2. **[Traversals](traversals.html)** - Deep dive into BFS and DFS
3. **[Shortest Path](shortest_path.html)** - Master Dijkstra, A*, and Bellman-Ford

Happy graph coding! 🚀
"""
nbSave
