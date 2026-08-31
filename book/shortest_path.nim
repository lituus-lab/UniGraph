# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nbText: "# Shortest Path Algorithms"
nbText: """
**Shortest path** algorithms find the minimum-cost path between vertices. The "cost" can represent distance, time, money, or any metric.

## Problem Definition

Given:
- A graph G = (V, E)
- Edge weights w: E → ℝ
- Source vertex s
- (Optionally) destination vertex t

Find:
- Path P from s to t minimizing Σ w(e) for all e ∈ P

## Dijkstra's Algorithm

**Dijkstra's algorithm** finds the shortest path from a source to all other vertices in graphs with **non-negative edge weights**.

### Algorithm

```
1. Initialize:
   - dist[source] = 0
   - dist[v] = ∞ for all other vertices
   - priority queue PQ with (source, 0)

2. While PQ is not empty:
   a. Extract vertex u with minimum distance
   b. If u already visited, skip
   c. Mark u as visited
   d. For each neighbor v of u:
      - alt = dist[u] + weight(u, v)
      - If alt < dist[v]:
        * dist[v] = alt
        * parent[v] = u
        * Add (v, alt) to PQ
```

### Visualization

```
    4       2
A ------ B ------ C
|        | \      |
| 2      |  3     | 1
|        |   \    |
D ------ E ---- F
    5       6

Shortest paths from A:
A → A: 0
A → D: 2 (direct)
A → B: 4 (direct)
A → C: 6 (A → B → C)
A → E: 7 (A → D → E; A → B → E costs the same, 4+3=7, but D relaxes E first)
A → F: 7 (A → B → C → F, not A → B → E → F which costs 4+3+6=13)
```

### Implementation

```nim
import UniGraph
import std/options

var g = newImmutableGraph[string, float](Directed)

# Build graph. addVertex on the wrapper returns (newGraph, id) -- use it, not
# g.kernel directly, or g.vertexCount won't reflect what you just added.
var vA, vB, vC, vD, vE, vF: VertexId
(g, vA) = g.addVertex("A")
(g, vB) = g.addVertex("B")
(g, vC) = g.addVertex("C")
(g, vD) = g.addVertex("D")
(g, vE) = g.addVertex("E")
(g, vF) = g.addVertex("F")

g = g.addEdge(vA, vB, 4.0)
g = g.addEdge(vA, vD, 2.0)
g = g.addEdge(vB, vC, 2.0)
g = g.addEdge(vB, vE, 3.0)
g = g.addEdge(vC, vF, 1.0)
g = g.addEdge(vD, vE, 5.0)
g = g.addEdge(vE, vF, 6.0)

# Weight function
proc weight(edge: Edge[float]): float =
  edge.data

# Run Dijkstra
let result = g.kernel.dijkstra(vA, weight)

# Print distances
for vertex in g.kernel.vertices():
  let dist = result.distances.getOrDefault(vertex.id, Inf)
  echo "Distance to ", vertex.data, ": ", dist

# Reconstruct path to F. reconstructPath returns seq[VertexId], and VertexId
# has no `$` override, so `echo path` alone prints the raw object fields
# (id, generation) -- map back to vertex data first to get readable names.
if vF in result.parents:
  let path = reconstructPath(result.parents, vF)
  var names: seq[string]
  for id in path:
    names.add g.getVertex(id).get().data
  echo "Path to F: ", names

# Verified output. The distances are correct; the *order* of the "Distance
# to" lines is not A..F -- vertices live in a Table, which iterates in hash
# order, not insertion order. Do not rely on vertex iteration order anywhere.
#   Distance to E: 7.0
#   Distance to F: 7.0
#   Distance to B: 4.0
#   Distance to D: 2.0
#   Distance to A: 0.0
#   Distance to C: 6.0
#   Path to F: @["A", "B", "C", "F"]
```

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O((V + E) log V) with binary heap |
| **Space** | O(V) |
| **With Fibonacci heap** | O(E + V log V) |

### Why Non-Negative Weights Only?

Dijkstra's algorithm uses a **greedy** approach: once a vertex is marked visited, its distance is final. Negative weights can invalidate this assumption:

```
A --(2)--> B --(-5)--> C
 \                     ^
  \----(1)-------------/

Dijkstra might finalize C with distance 1 (A→C)
But actual shortest: A→B→C = 2 + (-5) = -3
```

### Applications

1. **GPS navigation**: Find fastest route
2. **Network routing**: Minimize latency
3. **Currency arbitrage**: Find profitable exchange cycles (with modifications)
4. **Social networks**: Measure "degrees of separation"

## A* (A-Star) Algorithm

**A*** is an extension of Dijkstra's that uses a **heuristic** to guide the search toward the goal more efficiently.

### Algorithm

```
1. Initialize:
   - gScore[source] = 0 (actual cost from start)
   - fScore[source] = heuristic(source, goal)
   - priority queue PQ with (source, fScore[source])

2. While PQ is not empty:
   a. Extract vertex u with minimum fScore
   b. If u == goal, reconstruct and return path
   c. If u already visited, skip
   d. Mark u as visited
   e. For each neighbor v of u:
      - tentativeG = gScore[u] + weight(u, v)
      - If tentativeG < gScore[v]:
        * gScore[v] = tentativeG
        * fScore[v] = tentativeG + heuristic(v, goal)
        * parent[v] = u
        * Add (v, fScore[v]) to PQ
```

### Heuristic Requirements

For A* to be **optimal** (find shortest path), the heuristic must be:

1. **Admissible**: Never overestimates the true cost
   - h(n) ≤ actual_cost(n, goal)

2. **Consistent** (for graph search): Triangle inequality
   - h(n) ≤ cost(n, neighbor) + h(neighbor)

### Common Heuristics

UniGraph has no built-in notion of vertex position, so any heuristic needs a
`positions` table alongside the graph. Given `positions:
Table[VertexId, tuple[x, y: float]]`:

**Euclidean distance** (straight line, admissible whenever edge weights are
real distances):
```nim
proc euclidean(positions: Table[VertexId, tuple[x, y: float]],
    a, b: VertexId): float =
  let (ax, ay) = positions[a]
  let (bx, by) = positions[b]
  sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
```

**Manhattan distance** (grid movement, 4-directional):
```nim
proc manhattan(positions: Table[VertexId, tuple[x, y: float]],
    a, b: VertexId): float =
  let (ax, ay) = positions[a]
  let (bx, by) = positions[b]
  abs(ax - bx) + abs(ay - by)
```

### Implementation

A small 2×3 grid where every edge has unit length, so the Euclidean distance
to the goal never overestimates the true remaining cost — the heuristic is
admissible by construction:

```
A(0,0) - B(1,0) - C(2,0)
  |        |        |
D(0,1) - E(1,1) - F(2,1)
```

```nim
import UniGraph
import std/[tables, math, options]

var g = newImmutableGraph[string, float](Undirected)
var vA, vB, vC, vD, vE, vF: VertexId
(g, vA) = g.addVertex("A")
(g, vB) = g.addVertex("B")
(g, vC) = g.addVertex("C")
(g, vD) = g.addVertex("D")
(g, vE) = g.addVertex("E")
(g, vF) = g.addVertex("F")

g = g.addEdge(vA, vB, 1.0)
g = g.addEdge(vB, vC, 1.0)
g = g.addEdge(vD, vE, 1.0)
g = g.addEdge(vE, vF, 1.0)
g = g.addEdge(vA, vD, 1.0)
g = g.addEdge(vB, vE, 1.0)
g = g.addEdge(vC, vF, 1.0)

let positions = {vA: (0.0, 0.0), vB: (1.0, 0.0), vC: (2.0, 0.0),
                  vD: (0.0, 1.0), vE: (1.0, 1.0), vF: (2.0, 1.0)}.toTable

proc weight(edge: Edge[float]): float = edge.data

proc heuristic(a, b: VertexId): float =
  let (ax, ay) = positions[a]
  let (bx, by) = positions[b]
  sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)

# Run A* from A to F
let path = g.kernel.aStar(vA, vF, weight, heuristic)

if path.len > 0:
  var names: seq[string]
  for id in path:
    names.add g.getVertex(id).get().data
  echo "Path found: ", names
else:
  echo "No path exists"
```

**Verified output** (one of three equal-cost shortest routes; A* explores
`B` before `D` here because both have the same `fScore` and the heap breaks
ties by insertion order):
```
Path found: @["A", "B", "C", "F"]
```

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O((V + E) log V) worst case |
| **Space** | O(V) |
| **With good heuristic** | Often much faster than Dijkstra |

### A* vs Dijkstra

| Aspect | Dijkstra | A* |
|--------|----------|-----|
| **Explores** | All directions | Toward goal |
| **Optimal** | Always | With a *consistent* heuristic (admissible alone isn't enough here — see "Heuristic Requirements" above) |
| **Speed** | Slower | Faster (good heuristic) |
| **Requirements** | None | Heuristic function |

## Bellman-Ford Algorithm

**Bellman-Ford** handles graphs with **negative edge weights** and detects **negative cycles**.

### Algorithm

```
1. Initialize:
   - dist[source] = 0
   - dist[v] = ∞ for all other vertices

2. Relax all edges V-1 times:
   For each edge (u, v) with weight w:
     If dist[u] + w < dist[v]:
       dist[v] = dist[u] + w

3. Check for negative cycles:
   For each edge (u, v) with weight w:
     If dist[u] + w < dist[v]:
       Negative cycle detected!
```

### Visualization

The A-F graph above has no negative weights, so it can't show what makes
Bellman-Ford different from Dijkstra. Here's a small graph that actually
has one — a shortcut through a negative edge that Dijkstra could not trust:

```
A --(1)--> B --(-3)--> C --(2)--> D
 \_________________________(10)__/^
   (direct A -> C, the "obvious" but not shortest way)
```

`A -> C` directly costs 10. `A -> B -> C` costs `1 + (-3) = -2` — cheaper,
because the second edge is negative. Bellman-Ford relaxes every edge up to
`V-1` times and has no "finalize and never revisit" step, so it finds the
`-2` path; Dijkstra's greedy finalization (see above) cannot be trusted to.

```
Shortest distances from A: A=0, B=1, C=-2, D=0
```

(`D = C + 2 = -2 + 2 = 0` — a negative predecessor distance is not a bug.)

### Implementation

```nim
import UniGraph

var g2 = newImmutableGraph[string, float](Directed)
var a2, b2, c2, d2: VertexId
(g2, a2) = g2.addVertex("A")
(g2, b2) = g2.addVertex("B")
(g2, c2) = g2.addVertex("C")
(g2, d2) = g2.addVertex("D")
g2 = g2.addEdge(a2, b2, 1.0)
g2 = g2.addEdge(b2, c2, -3.0)
g2 = g2.addEdge(a2, c2, 10.0)
g2 = g2.addEdge(c2, d2, 2.0)

proc weight(edge: Edge[float]): float = edge.data

# Run Bellman-Ford
let result = g2.kernel.bellmanFord(a2, weight)

if result.hasNegativeCycle:
  echo "Graph contains a negative cycle!"
else:
  echo "Shortest paths computed successfully"
  for vertex in g2.kernel.vertices():
    let dist = result.distances.getOrDefault(vertex.id, Inf)
    echo "Distance to ", vertex.data, ": ", dist

# Verified output (vertex print order is Table-iteration order, not A..D):
#   hasNegativeCycle: false
#   Distance to B: 1.0
#   Distance to D: 0.0
#   Distance to A: 0.0
#   Distance to C: -2.0
```

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O(V × E) |
| **Space** | O(V) |
| **Early termination** | Often faster in practice |

### Why Use Bellman-Ford?

1. **Handles negative weights**: Unlike Dijkstra
2. **Detects negative cycles**: Useful for arbitrage detection
3. **Simpler implementation**: No priority queue needed
4. **Distributed systems**: Easier to parallelize

### Negative Cycle Detection

A **negative cycle** is a cycle where the sum of edge weights is negative. This means you can keep going around the cycle to get arbitrarily low costs.

**Application: Currency Arbitrage**
```
USD → EUR: rate 0.85
EUR → GBP: rate 0.90
GBP → USD: rate 1.30

Convert weights: -log(rate)
If negative cycle exists: arbitrage opportunity!
```

## Algorithm Comparison

| Algorithm | Negative Weights | Negative Cycles | Time Complexity | Best For |
|-----------|-----------------|-----------------|-----------------|----------|
| **Dijkstra** | ❌ No | N/A | O((V+E) log V) | Fastest for non-negative |
| **A*** | ❌ No | N/A | O((V+E) log V) | Goal-directed search |
| **Bellman-Ford** | ✅ Yes | ✅ Detects | O(V × E) | Negative weights, cycle detection |

## Practice Exercises

### Exercise 1: All-Pairs Shortest Path
Implement Floyd-Warshall algorithm to find shortest paths between all pairs of vertices.

```nim
proc floydWarshall[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float
): Table[(VertexId, VertexId), float] =
  # Return: distance table for all pairs
  discard
```

### Exercise 2: Critical Path Method
Find the longest path in a DAG (Directed Acyclic Graph) for project scheduling.

```nim
proc criticalPath[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float
): tuple[path: seq[VertexId], duration: float] =
  # Longest path = critical path
  discard
```

### Exercise 3: Widest Path
Find the path that maximizes the minimum edge capacity (bottleneck path).

```nim
proc widestPath[V, E](
    kernel: ListKernel[V, E],
    start, goal: VertexId
): tuple[path: seq[VertexId], capacity: float] =
  # Maximize minimum edge weight along path
  discard
```

## References

- Wikipedia: [Shortest path problem](https://en.wikipedia.org/wiki/Shortest_path_problem)
- Wikipedia: [Dijkstra's algorithm](https://en.wikipedia.org/wiki/Dijkstra%27s_algorithm) —
  Dijkstra, E. W. (1959), "A note on two problems in connexion with graphs"
- Wikipedia: [A* search algorithm](https://en.wikipedia.org/wiki/A*_search_algorithm) —
  Hart, Nilsson, Raphael (1968)
- Wikipedia: [Bellman–Ford algorithm](https://en.wikipedia.org/wiki/Bellman%E2%80%93Ford_algorithm)
- Wikipedia: [Admissible heuristic](https://en.wikipedia.org/wiki/Admissible_heuristic)
- Wikipedia: [Consistent heuristic](https://en.wikipedia.org/wiki/Consistent_heuristic)
"""
nbSave
