# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook

nbInit(theme = useNimibook)
nbText: "# Minimum Spanning Tree"
nbText: """
A **Minimum Spanning Tree (MST)** is a subset of edges that connects all vertices with minimum total weight, without any cycles.

## Problem Definition

Given:
- An undirected graph G = (V, E)
- Edge weights w: E → ℝ

Find:
- A subset of edges T ⊆ E such that:
  - T connects all vertices within the same connected component (spanning)
  - T has no cycles (a tree, per component)
  - Σ w(e) for all e ∈ T is minimized

If G is not connected, there is no single spanning tree — UniGraph's `prim`
detects the exhausted frontier at the end of one component and restarts on
the next unvisited vertex, returning a **minimum spanning forest**: one tree
per component, still minimal within each. Kruskal needs no explicit restart:
Union-Find merges sets only when an input edge connects them, so disconnected
components remain separate and the result is naturally a forest.

### Properties

- **Number of edges**: for a connected graph, |T| = |V| - 1. A minimum
  spanning forest with c connected components has |V| - c edges.
- **Unique MST**: If all edge weights are distinct
- **Multiple MSTs**: If some edge weights are equal

## Applications

1. **Network design**: Minimize cable/wire length
2. **Clustering**: Group similar data points
3. **Approximation algorithms**: TSP, Steiner Tree
4. **Image segmentation**: Group similar pixels
5. **Circuit design**: Minimize wire length

## Prim's Algorithm

**Prim's algorithm** builds the MST by growing a single tree from an arbitrary start vertex.

### Algorithm (Greedy Approach)

```
1. Initialize:
   - Choose arbitrary start vertex
   - MST = empty set
   - Add all edges from start to priority queue

2. While the priority queue is not empty:
   a. Extract minimum weight edge (u, v) from queue
   b. If v already in MST, skip
   c. Add (u, v) to MST
   (if the queue empties before MST reaches V-1 edges, the graph was
   disconnected -- restart step 1 from an unvisited vertex to grow the
   next tree of the spanning forest)
   d. Add all edges from v to queue
```

### Visualization

```
Graph:                MST construction:
    2                     2
A ------ B          A ------ B
| \      |
|   \    | 3
4     \  |
|       \|
C ------ D          C ------ D
    1                   1

Step 1: Start at A, add edges (A,B,2), (A,C,4), (A,D,3)
Step 2: Pick (A,B,2) (cheapest), add edges (B,D,3) [already have (A,D,3), same weight]
Step 3: Pick (A,D,3) (cheapest of the remaining frontier), add edges (D,C,1)
Step 4: Pick (D,C,1) - MST complete!

MST edges: (A,B,2), (A,D,3), (D,C,1)
Total weight: 6
```

### Implementation

```nim
import UniGraph

var g = newImmutableGraph[string, float](Undirected)

# Build graph. addVertex on the wrapper returns (newGraph, id) -- use it, not
# g.kernel directly, or g.vertexCount won't reflect what you just added.
var vA, vB, vC, vD: VertexId
(g, vA) = g.addVertex("A")
(g, vB) = g.addVertex("B")
(g, vC) = g.addVertex("C")
(g, vD) = g.addVertex("D")

g = g.addEdge(vA, vB, 2.0)
g = g.addEdge(vA, vC, 4.0)
g = g.addEdge(vA, vD, 3.0)
g = g.addEdge(vB, vD, 3.0)
g = g.addEdge(vC, vD, 1.0)

# Weight function
proc weight(edge: Edge[float]): float =
  edge.data

# Run Prim's algorithm
let mst = g.kernel.prim(weight)

echo "MST edges:"
var totalWeight = 0.0
for edge in mst:
  echo "  ", edge.source.id, " -> ", edge.target.id, " (weight: ", edge.data, ")"
  totalWeight += edge.data

echo "Total MST weight: ", totalWeight
```

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O((V + E) log V) with binary heap |
| **Space** | O(V + E) |
| **With Fibonacci heap** | O(E + V log V) |

### Why It Works (Proof Sketch)

**Cut Property**: For any cut (partition of vertices), a minimum-weight edge
crossing that cut is *safe*: at least one MST contains it. If several crossing
edges tie, different choices can lead to different MSTs with the same weight.

Prim's algorithm always picks the minimum edge from the current tree to a vertex outside, which is exactly the cut property.

## Kruskal's Algorithm

**Kruskal's algorithm** builds the MST by adding edges in order of increasing weight, avoiding cycles.

### Algorithm (Union-Find Approach)

```
1. Sort all edges by weight (ascending)

2. Initialize Union-Find:
   - Each vertex in its own set

3. For each edge (u, v) in sorted order:
   a. If u and v are in different sets:
      - Add (u, v) to MST
      - Union the sets containing u and v
   b. Otherwise, skip (would create cycle)

4. Stop when MST has V-1 edges
```

### Visualization

```
Graph edges sorted by weight:
(C,D,1), (A,B,2), (A,D,3), (B,D,3), (A,C,4)

Step 1: Add (C,D,1) - sets: {A}, {B}, {C,D}
Step 2: Add (A,B,2) - sets: {A,B}, {C,D}
Step 3: Add (A,D,3) - sets: {A,B,C,D} ✓ MST complete!

Skip (B,D,3) - would create cycle
Skip (A,C,4) - would create cycle
```

### Union-Find Data Structure

```nim
type
  UnionFind = object
    parent: seq[int]
    rank: seq[int]

proc initUnionFind(n: int): UnionFind =
  result.parent = newSeq[int](n)
  result.rank = newSeq[int](n)
  for i in 0..<n:
    result.parent[i] = i  # Each element is its own parent initially
    result.rank[i] = 0    # All trees have height 0 initially

proc find(uf: var UnionFind, x: int): int =
  ## Find with path compression
  if uf.parent[x] != x:
    uf.parent[x] = uf.find(uf.parent[x])  # Compress path
  result = uf.parent[x]

proc union(uf: var UnionFind, x, y: int): bool =
  ## Union by rank, returns true if union was performed
  let rootX = uf.find(x)
  let rootY = uf.find(y)
  
  if rootX == rootY:
    return false  # Already in same set
  
  # Attach smaller tree under larger tree
  if uf.rank[rootX] < uf.rank[rootY]:
    uf.parent[rootX] = rootY
  elif uf.rank[rootX] > uf.rank[rootY]:
    uf.parent[rootY] = rootX
  else:
    uf.parent[rootY] = rootX
    inc uf.rank[rootX]
  
  result = true
```

### Implementation

```nim
# Continuing with `g` and `weight` from the complete Prim example above.
let mst = g.kernel.kruskal(weight)

echo "MST edges:"
var totalWeight = 0.0
for edge in mst:
  echo "  ", edge.source.id, " -> ", edge.target.id, " (weight: ", edge.data, ")"
  totalWeight += edge.data

echo "Total MST weight: ", totalWeight
```

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O(E log E) = O(E log V) |
| **Space** | O(V + E) — the full edge list is materialized and sorted |
| **Sorting** | O(E log E) dominates |
| **Union-Find** | O(E α(V)) ≈ O(E) |

Note: α(V) is the inverse Ackermann function, nearly constant (≤ 4 for all practical values).

## Prim's vs Kruskal's

| Aspect | Prim's | Kruskal's |
|--------|--------|-----------|
| **Approach** | Grow single tree | Merge forests |
| **Data structure** | Priority queue | Union-Find |
| **Best for** | Dense graphs | Sparse graphs |
| **Time** | O((V+E) log V) | O(E log E) |
| **Space** | O(V + E) | O(V + E) |
| **Start vertex** | Needs one | None needed |

### When to Use Each

**Use Prim's when:**
- Graph is dense (E ≈ V²)
- You have a natural starting point
- Memory is not a constraint

**Use Kruskal's when:**
- Graph is sparse (E << V²)
- Edges are already sorted
- Memory is limited

## Example: Network Design

```nim
import UniGraph
import std/options

# Design a fiber optic network connecting 6 cities
var network = newImmutableGraph[string, float](Undirected)

var cityA, cityB, cityC, cityD, cityE, cityF: VertexId
(network, cityA) = network.addVertex("Paris")
(network, cityB) = network.addVertex("Lyon")
(network, cityC) = network.addVertex("Marseille")
(network, cityD) = network.addVertex("Toulouse")
(network, cityE) = network.addVertex("Bordeaux")
(network, cityF) = network.addVertex("Nantes")

# Add possible connections with construction costs (in millions)
network = network.addEdge(cityA, cityB, 450.0)  # Paris-Lyon
network = network.addEdge(cityA, cityF, 380.0)  # Paris-Nantes
network = network.addEdge(cityB, cityC, 310.0)  # Lyon-Marseille
network = network.addEdge(cityB, cityE, 520.0)  # Lyon-Bordeaux
network = network.addEdge(cityC, cityD, 400.0)  # Marseille-Toulouse
network = network.addEdge(cityD, cityE, 240.0)  # Toulouse-Bordeaux
network = network.addEdge(cityE, cityF, 280.0)  # Bordeaux-Nantes
network = network.addEdge(cityA, cityE, 550.0)  # Paris-Bordeaux

proc cost(edge: Edge[float]): float =
  edge.data

# Find minimum cost network
let mst = network.kernel.prim(cost)

echo "Optimal network connections:"
var totalCost = 0.0
for edge in mst:
  let sourceCity = network.getVertex(edge.source).get().data
  let targetCity = network.getVertex(edge.target).get().data
  echo "  ", sourceCity, " <-> ", targetCity, " (€", edge.data, "M)"
  totalCost += edge.data

echo "Total construction cost: €", totalCost, "M"
```

**One possible verified output** (the edge order is not part of the API):
```
Optimal network connections:
  Bordeaux <-> Toulouse (€240.0M)
  Bordeaux <-> Nantes (€280.0M)
  Nantes <-> Paris (€380.0M)
  Toulouse <-> Marseille (€400.0M)
  Marseille <-> Lyon (€310.0M)
Total construction cost: €1610.0M
```

## Practice Exercises

### Exercise 1: Maximum Spanning Tree
Find the spanning tree with **maximum** total weight.

```nim
proc maximumSpanningTree[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float
): seq[Edge[E]] =
  # Hint: negate weights or reverse comparison
  discard
```

### Exercise 2: Second-Best MST
Find the spanning tree with the second-smallest total weight.

```nim
proc secondBestMST[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float
): tuple[edges: seq[Edge[E]], weight: float] =
  # Hint: for each MST edge, try replacing it
  discard
```

### Exercise 3: MST with Constraints
Find MST that must include a specific edge.

```nim
proc constrainedMST[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float,
    requiredEdge: tuple[u, v: VertexId]
): seq[Edge[E]] =
  # Hint: contract the required edge first
  discard
```

### Exercise 4: Verify MST
Given a set of edges, verify if it forms an MST.

```nim
proc verifyMST[V, E](
    kernel: ListKernel[V, E],
    candidateEdges: seq[Edge[E]],
    weightProc: proc(edge: Edge[E]): float
): bool =
  # Check: spans all vertices, no cycles, minimum weight
  discard
```

## References

- Wikipedia: [Minimum spanning tree](https://en.wikipedia.org/wiki/Minimum_spanning_tree)
- Wikipedia: [Prim's algorithm](https://en.wikipedia.org/wiki/Prim%27s_algorithm)
- Wikipedia: [Kruskal's algorithm](https://en.wikipedia.org/wiki/Kruskal%27s_algorithm)
- Wikipedia: [Disjoint-set data structure](https://en.wikipedia.org/wiki/Disjoint-set_data_structure) —
  the Union-Find structure behind `kruskal`
- Wikipedia: [Cut (graph theory)](https://en.wikipedia.org/wiki/Cut_(graph_theory)) —
  the "cut property" `prim`'s correctness argument relies on
"""
nbSave
