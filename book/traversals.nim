# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook

nbInit(theme = useNimibook)
nbText: "# Graph Traversals"
nbText: """
**Traversal** algorithms visit every reachable vertex in a graph systematically. They are the foundation for more complex algorithms.

## Breadth-First Search (BFS)

**BFS** explores the graph **level by level**, visiting all neighbors before going deeper.

### Algorithm

```
1. Start at source vertex S
2. Mark S as visited, enqueue S
3. While queue is not empty:
   a. Dequeue vertex V
   b. For each unvisited neighbor N of V:
      - Mark N as visited
      - Enqueue N
```

### Visualization

```
Level 0:        A
               / \
Level 1:      B   C
              |   |
Level 2:      D   E

BFS order: A → B → C → D → E
```

### Implementation with Visitor

```nim
import UniGraph

var g = newImmutableGraph[string, float](Directed)

# Build graph. addVertex on the wrapper returns (newGraph, id) -- use it, not
# g.kernel directly, or g.vertexCount won't reflect what you just added.
var vA, vB, vC, vD, vE: VertexId
(g, vA) = g.addVertex("A")
(g, vB) = g.addVertex("B")
(g, vC) = g.addVertex("C")
(g, vD) = g.addVertex("D")
(g, vE) = g.addVertex("E")

g = g.addEdge(vA, vB, 1.0)
g = g.addEdge(vA, vC, 1.0)
g = g.addEdge(vB, vD, 1.0)
g = g.addEdge(vC, vE, 1.0)

# BFS with tracing
var visitor = newVisitor[float]()
g.kernel.bfs(vA, visitor)

# Print execution trace
visitor.printTrace()
```

**Output** (the `(order, time)` pair on discovery and the `(ekTree/...)` tag
on each edge come from the Visitor's discovery/finish timestamps and edge
classification — see "Edge Classification" below):
```
Step 1: Discovered vertex 0 (order: 0, time: 0)
Step 2: Traversed edge 0 -> 1 (ekTree)
Step 3: Discovered vertex 1 (order: 1, time: 1)
Step 4: Traversed edge 0 -> 2 (ekTree)
Step 5: Discovered vertex 2 (order: 2, time: 2)
Step 6: Traversed edge 1 -> 3 (ekTree)
Step 7: Discovered vertex 3 (order: 3, time: 3)
Step 8: Traversed edge 2 -> 4 (ekTree)
Step 9: Discovered vertex 4 (order: 4, time: 4)
```

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O(V + E) |
| **Space** | O(V) |
| **Queue operations** | O(V) |

**Why O(V + E)?**
- Each vertex is enqueued once: O(V)
- Each edge is examined once: O(E)

### Applications

1. **Shortest path in unweighted graphs**: BFS finds the path with fewest edges
2. **Connected components**: Find all vertices reachable from a source
3. **Web crawling**: Crawl pages level by level
4. **Social networks**: Find friends within N degrees of separation
5. **Broadcasting**: Spread information in networks

### Finding Shortest Path (Unweighted)

```nim
import std/tables

proc shortestPathBFS[V, E](
    kernel: ListKernel[V, E],
    start, goal: VertexId
): seq[VertexId] =
  var queue = @[(vertex: start, path: @[start])]
  var visited = initTable[VertexId, bool]()
  visited[start] = true
  
  while queue.len > 0:
    let (current, path) = queue[0]
    queue.delete(0)
    
    if current == goal:
      return path
    
    for edge in kernel.neighbors(current):
      if edge.target notin visited:
        visited[edge.target] = true
        var newPath = path
        newPath.add(edge.target)
        queue.add((vertex: edge.target, path: newPath))
  
  return @[]  # No path found
```

## Depth-First Search (DFS)

**DFS** explores the graph by going **as deep as possible** before backtracking.

### Algorithm (Conceptual Recursive Form)

DFS is often taught recursively because the call stack mirrors the path being
explored. UniGraph implements the same enter/exit behavior with explicit stack
frames, avoiding a native-stack overflow on a very deep graph.

```
1. Start at source vertex S
2. Mark S as visited
3. For each unvisited neighbor N of S:
   - Recursively call DFS(N)
```

### Visualization

```
    A
   / \
  B   C
 /     \
D       E

DFS order: A → B → D → (backtrack) → C → E
```

### Implementation with Visitor

```nim
# Continuing with `g` and `vA` from the complete BFS example above.
var visitor = newVisitor[float]()
g.kernel.dfs(vA, visitor)

visitor.printTrace()
```

**Verified output** (discovery order starts at 0, same convention as BFS's
`order:` field above — not 1; `time:` is the shared discovery/finish clock,
incremented on every discover *and* every finish — see below):
```
Step 1: Discovered vertex 0 (order: 0, time: 0)
Step 2: Traversed edge 0 -> 1 (ekTree)
Step 3: Discovered vertex 1 (order: 1, time: 1)
Step 4: Traversed edge 1 -> 3 (ekTree)
Step 5: Discovered vertex 3 (order: 2, time: 2)
Step 6: Finished vertex 3 (time: 3)
Step 7: Finished vertex 1 (time: 4)
Step 8: Traversed edge 0 -> 2 (ekTree)
Step 9: Discovered vertex 2 (order: 3, time: 5)
Step 10: Traversed edge 2 -> 4 (ekTree)
Step 11: Discovered vertex 4 (order: 4, time: 6)
Step 12: Finished vertex 4 (time: 7)
Step 13: Finished vertex 2 (time: 8)
Step 14: Finished vertex 0 (time: 9)
```

### Edge Classification

Every `onEdge` call is classified into one of four kinds (`EdgeKind` in
`UniGraph/visitor`), the classic scheme from CLRS — computed by the visitor
itself from its own discovery/finish state, not by the traversal algorithm:

- **`ekTree`**: the target was undiscovered — this edge is part of the
  traversal tree/forest.
- **`ekBack`**: the target is discovered but not yet finished — it's an
  ancestor still on the current path. A back edge in a directed graph's DFS
  means a **cycle**.
- **`ekForward`**: the target is already finished and was discovered
  *after* the source — a shortcut to a descendant.
- **`ekCross`**: the target is already finished and was discovered *before*
  the source, with no ancestor/descendant relationship. This graph is a tree,
  so its DFS produces only `ekTree` edges.
  The Quickstart chapter's DFS example (`A→B→D`, `A→C→D`, both branches
  reaching `D`) shows one: by the time DFS follows `C -> D`, `D` is already
  finished (reached first via `B -> D`) and `D`'s discovery time is *before*
  `C`'s, so `C -> D` classifies as `ekCross`.

`bfs`/`bfsIterative` never call `onFinish` (BFS doesn't have a notion of
"done" for a vertex — see Core Concepts' Vocabulary section), so every
non-tree edge they report classifies as `ekBack`: "discovered but not
finished" is trivially true for every vertex in a BFS run. Only
`dfs`/`dfsIterative` can produce `ekForward`/`ekCross`.

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O(V + E) |
| **Space** | O(V) |
| **Explicit stack** | O(V) worst case |

### Applications

1. **Topological sorting**: Order tasks with dependencies
2. **Cycle detection**: Find cycles in directed graphs
3. **Maze solving**: Explore all possible paths
4. **Strongly connected components**: Kosaraju's and Tarjan's algorithms
5. **Bipartite checking**: Test if graph is bipartite

### Iterative DFS (Avoiding Recursion)

```nim
import std/[sequtils, tables]

proc teachingDfsIterative[V, E](
    kernel: ListKernel[V, E],
    start: VertexId,
    visitor: Visitor[E]
): seq[VertexId] =
  result = @[]
  var stack = @[start]
  var visited = initTable[VertexId, bool]()
  
  while stack.len > 0:
    let current = stack.pop()
    
    if current in visited:
      continue
    
    visited[current] = true
    result.add(current)
    visitor.onDiscover(current, result.len - 1)
    
    # Push neighbors in reverse order (for correct ordering)
    let neighbors = toSeq(kernel.neighbors(current))
    for i in countdown(neighbors.len - 1, 0):
      let edge = neighbors[i]
      visitor.onEdge(current, edge.target, edge.data)
      if edge.target notin visited:
        stack.add(edge.target)
```

## BFS vs DFS Comparison

| Aspect | BFS | DFS |
|--------|-----|-----|
| **Data structure** | Queue | Explicit stack |
| **Exploration** | Level by level | Depth first |
| **Shortest path** | Yes (unweighted) | No |
| **Memory** | O(V) - stores frontier | O(V) - stores path |
| **Use case** | Find closest vertices | Explore all possibilities |

## Reachability Analysis

```nim
import std/[sequtils, tables]

proc reachableVertices[V, E](
    kernel: ListKernel[V, E],
    start: VertexId
): seq[VertexId] =
  ## Get all vertices reachable from start
  result = @[]
  var queue = @[start]
  var visited = initTable[VertexId, bool]()
  visited[start] = true
  result.add(start)
  
  while queue.len > 0:
    let current = queue[0]
    queue.delete(0)
    
    for edge in kernel.neighbors(current):
      if edge.target notin visited:
        visited[edge.target] = true
        result.add(edge.target)
        queue.add(edge.target)

# A single forward search establishes connectivity only for undirected graphs.
proc isConnectedUndirected[V, E](kernel: ListKernel[V, E]): bool =
  let vertices = toSeq(kernel.vertices())
  if vertices.len == 0:
    return true
  
  let startVertex = vertices[0].id
  let reachable = kernel.reachableVertices(startVertex)
  
  return reachable.len == vertices.len
```

## Practice Exercises

### Exercise 1: Level Order Traversal
Modify BFS to return vertices grouped by level.

```nim
proc bfsByLevel[V, E](
    kernel: ListKernel[V, E],
    start: VertexId
): seq[seq[VertexId]] =
  # Return: [[level0], [level1], [level2], ...]
  discard
```

### Exercise 2: Bipartite Check
A graph is bipartite if vertices can be colored with 2 colors such that no adjacent vertices share the same color.

```nim
proc isBipartite[V, E](kernel: ListKernel[V, E]): bool =
  # Use BFS with 2-coloring
  discard
```

### Exercise 3: Cycle Detection (Undirected)
Detect if an undirected graph contains a cycle.

```nim
proc hasCycle[V, E](kernel: ListKernel[V, E]): bool =
  # Use DFS, check for back-edges
  discard
```

## References

- Wikipedia: [Breadth-first search](https://en.wikipedia.org/wiki/Breadth-first_search)
- Wikipedia: [Depth-first search](https://en.wikipedia.org/wiki/Depth-first_search)
- Wikipedia: [Tree traversal](https://en.wikipedia.org/wiki/Tree_traversal)
- Cormen, Leiserson, Rivest, Stein — *Introduction to Algorithms* (CLRS),
  chapters 22.2–22.3 — the source of the tree/back/forward/cross edge
  classification `EdgeKind` implements
"""
nbSave
