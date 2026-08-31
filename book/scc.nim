# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nbText: "# Strongly Connected Components"
nbText: """
A **Strongly Connected Component (SCC)** is a maximal subgraph where every vertex is reachable from every other vertex.

## Definitions

### Strong Connectivity

In a **directed graph**, vertices u and v are **strongly connected** if:
- There exists a path from u to v
- There exists a path from v to u

### Strongly Connected Component

An SCC is a **maximal** set of vertices C such that:
- Every pair of vertices in C is strongly connected
- No vertex outside C can be added while preserving this property

A **DAG** (Directed Acyclic Graph) is a directed graph with no cycles — no
sequence of edges leads back to where it started.

A **back-edge** is an edge discovered by DFS that points to a vertex already
on the current recursion stack (an ancestor in the DFS tree). A directed
graph has a cycle if and only if a DFS on it finds a back-edge — this is the
fact both algorithms below build on.

The **condensation graph** collapses every SCC into a single vertex, keeping
one edge between two SCCs whenever the original graph had any edge between
their members. The condensation graph is always a DAG: if it had a cycle,
every SCC on that cycle would actually be one bigger SCC, contradicting
maximality.

### Visualization

```
    A → B
    ↑   ↓
    +---C → D
            ↑↓
            E

SCCs: {A, B, C}, {D, E}

Condensation graph (DAG of SCCs):
  {A, B, C} → {D, E}
```

`{A,B,C}` is strongly connected (A→B→C→A). `{D,E}` is strongly connected
(D→E→D). The only edge between the two components is C→D, so the
condensation graph has exactly one edge, in one direction — as any DAG must.

## Applications

1. **Dependency analysis**: Find circular dependencies
2. **Social networks**: Identify tightly-knit communities
3. **Web analysis**: Discover link farms, web rings
4. **Circuit design**: Find feedback loops
5. **Model checking**: Verify system properties
6. **2-SAT solving**: Boolean satisfiability

## Kosaraju's Algorithm

**Kosaraju's algorithm** uses two DFS passes to find all SCCs.

### Algorithm (Two-Pass DFS)

```
Pass 1: Compute finish order
1. Run DFS on original graph G
2. Record vertices in order of finish time (post-order)

Pass 2: Find SCCs
3. Compute transpose graph G^T (reverse all edges)
4. Process vertices in reverse finish order
5. For each unvisited vertex, run DFS on G^T
6. Each DFS tree is one SCC
```

### Why It Works

**Key Insight**: Reverse finish order selects a source SCC in `G`. That SCC
becomes a sink in the transpose `G^T`, so a DFS started there cannot leave it.

**Intuition**:
- The first selected component has no incoming edge from another unvisited SCC in `G`
- Reversing every edge makes it a sink in `G^T`
- DFS in `G^T` can move inside that SCC but cannot escape it

### Visualization

Same graph as above (numbered 1-5 instead of lettered, to match the code
below): 1→2, 2→3, 3→1 (a cycle), 3→4 (the bridge), 4→5, 5→4 (a second cycle).

```
Original graph G:         Transpose G^T:
  1 → 2 → 3 → 4 ⇄ 5          1 ← 2 ← 3 ← 4 ⇄ 5
  ↑_______|                        |_______↑
  (3 → 1 closes the cycle)   (1 → 3 closes the cycle)
```

Pass 1 (DFS on G, recording finish order) finishes each vertex only after
every vertex reachable from it is already finished — so 4 and 5 (the sink
component) finish before 1, 2, 3 do, and among 1/2/3 whichever DFS enters
last finishes first. The exact order depends on which neighbor `neighbors()`
visits first, which the concept doesn't fix — but it is guaranteed that some
permutation of `{4, 5}` precedes some permutation of `{1, 2, 3}`.

Pass 2 runs DFS on the transpose, taking vertices in *reverse* finish order
(so a vertex from `{1, 2, 3}` starts first). From vertex 1, G^T's edges
(2→1, 1→3, 3→2, 4→3, 5→4, 4→5) reach 2 and 3 but stop at 3: 3→4 does not
exist in G^T's direction from inside this component, so the DFS tree is
exactly `{1, 2, 3}` — one SCC. The remaining unvisited vertices, 4 and 5,
form the second DFS tree and the second SCC.

```
Strongly Connected Components:
SCC #1: {1, 2, 3}
SCC #2: {4, 5}
```

### Implementation

```nim
import UniGraph
import std/options

var g = newImmutableGraph[string, float](Directed)

# Build graph: two cycles joined by a bridge edge (3 -> 4). addVertex on the
# wrapper returns (newGraph, id) -- use it, not g.kernel directly.
var v1, v2, v3, v4, v5: VertexId
(g, v1) = g.addVertex("1")
(g, v2) = g.addVertex("2")
(g, v3) = g.addVertex("3")
(g, v4) = g.addVertex("4")
(g, v5) = g.addVertex("5")

g = g.addEdge(v1, v2, 1.0)
g = g.addEdge(v2, v3, 1.0)
g = g.addEdge(v3, v1, 1.0)  # closes the {1,2,3} cycle
g = g.addEdge(v3, v4, 1.0)  # bridge: crosses from one SCC to the other
g = g.addEdge(v4, v5, 1.0)
g = g.addEdge(v5, v4, 1.0)  # closes the {4,5} cycle

# Run Kosaraju's algorithm
let sccs = g.kernel.kosaraju()

echo "Strongly Connected Components:"
for i, scc in sccs:
  echo "SCC #", i + 1, ":"
  for vertexId in scc:
    let vertex = g.getVertex(vertexId).get()
    echo "  Vertex ", vertexId.id, " (", vertex.data, ")"

# One possible component order (vertex ids 0..4 carry labels "1".."5"):
#   {0, 1, 2}  -> labels {1, 2, 3}
#   {3, 4}     -> labels {4, 5}
# Component and member order are not part of the API contract.
```

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O(V + E) |
| **Space** | O(V + E) |
| **DFS passes** | 2 |
| **Graph transpose** | O(V + E) |

### Advantages

- ✅ Simple to understand and implement
- ✅ Linear time complexity
- ✅ No complex data structures

### Disadvantages

- ❌ Requires graph transpose (extra memory)
- ❌ Two separate DFS passes
- ❌ Not intuitive why it works

## Tarjan's Algorithm

**Tarjan's algorithm** finds all SCCs in a **single DFS pass** using discovery times and low-link values.

### Key Concepts

**Discovery Time (disc[u])**: When vertex u was first visited during DFS

**Low-Link Value (low[u])**: Smallest discovery time reachable from u (including through back-edges)

**Stack**: Tracks vertices in current DFS path and potential SCCs

### Algorithm

```
1. Initialize:
   - index = 0
   - empty stack
   - disc[u] = undefined for all u
   - onStack[u] = false for all u

2. For each unvisited vertex v:
   call strongconnect(v)

strongconnect(v):
  a. disc[v] = low[v] = index++
  b. Push v onto stack, set onStack[v] = true
  
  c. For each neighbor w of v:
     - If w not visited:
       * strongconnect(w)
       * low[v] = min(low[v], low[w])
     - Else if w on stack:
       * low[v] = min(low[v], disc[w])  # Back-edge
  
  d. If low[v] == disc[v]:  # v is root of SCC
     - Pop vertices from stack until v
     - These vertices form one SCC
```

### Visualization

Same graph as the Kosaraju section: 1→2, 2→3, 3→1, 3→4, 4→5, 5→4. Starting
`strongconnect` at vertex 1, visiting each vertex's only unvisited neighbor:

```
strongconnect(1): disc=0, low=0, stack=[1]
  strongconnect(2): disc=1, low=1, stack=[1,2]
    strongconnect(3): disc=2, low=2, stack=[1,2,3]
      3 -> 1: 1 is on the stack (back-edge). low[3]=min(2, disc[1]=0)=0
      strongconnect(4): disc=3, low=3, stack=[1,2,3,4]
        strongconnect(5): disc=4, low=4, stack=[1,2,3,4,5]
          5 -> 4: 4 is on the stack (back-edge). low[5]=min(4, disc[4]=3)=3
        low[5] (3) != disc[5] (4): 5 is not an SCC root, nothing pops
        back in 4: low[4]=min(low[4]=3, low[5]=3)=3
      low[4] == disc[4] (3 == 3): pop until 4 -> SCC #1 = {5, 4}
      back in 3: low[3]=min(low[3]=0, low[4]=3)=0  # unchanged, low[3] was already 0
    low[3] (0) != disc[3] (2): 3 is not an SCC root, nothing pops
    back in 2: low[2]=min(low[2]=1, low[3]=0)=0
  low[2] (0) != disc[2] (1): 2 is not an SCC root, nothing pops
  back in 1: low[1]=min(low[1]=0, low[2]=0)=0
low[1] == disc[1] (0 == 0): pop until 1 -> SCC #2 = {3, 2, 1}
```

`5` and `4` pop first — while still deep in the recursion, before DFS ever
returns to `1`. That is the algorithm's advantage over Kosaraju: no second
pass over a transpose graph, an SCC is emitted the moment its root's `low`
value catches up to its own `disc` value.

```
Strongly Connected Components (Tarjan):
SCC #1: {5, 4}
SCC #2: {3, 2, 1}
```

### Implementation

```nim
# Continuing with the graph from the complete Kosaraju example above.
let sccs = g.kernel.tarjan()

echo "Strongly Connected Components (Tarjan):"
for i, scc in sccs:
  echo "SCC #", i + 1, ": ", scc.len, " vertices"

# One possible output is a 2-vertex SCC followed by a 3-vertex SCC;
# component order is not part of the API contract.
```

### Complexity Analysis

| Metric | Value |
|--------|-------|
| **Time** | O(V + E) |
| **Space** | O(V) |
| **DFS passes** | 1 |
| **Stack space** | O(V) |

### Advantages

- ✅ Single DFS pass
- ✅ No graph transpose needed
- ✅ More memory efficient

### Disadvantages

- ❌ More complex to understand
- ❌ More bookkeeping: UniGraph uses explicit DFS frames plus Tarjan's
  active-component stack to avoid native-stack exhaustion

## Algorithm Comparison

| Aspect | Kosaraju's | Tarjan's |
|--------|------------|----------|
| **DFS passes** | 2 | 1 |
| **Graph transpose** | Required | Not needed |
| **Memory** | O(V + E) | O(V) |
| **Complexity** | Simple | Moderate |
| **Performance** | Same O(V+E) | Same O(V+E) |
| **Practical speed** | Slower (2 passes) | Faster (1 pass) |

## Finding Articulation Points

An **articulation point** (cut vertex) is a vertex whose removal disconnects
the graph. This is an **undirected-graph** concept: the algorithm below skips
the edge back to a vertex's own parent using an *undirected* notion of
"the edge I just came from", which only makes sense when every edge is
symmetric. Running it on a directed graph gives meaningless results.

**UniGraph already ships this** as `kernel.findArticulationPoints()` — same
low-link DFS as Kosaraju/Tarjan above, so unlike this chapter's other
"Practice Exercises" (Condensation Graph, 2-SAT, Bridge Detection,
Biconnected Components), there's nothing here you actually need to write.
The simplified recursive pseudocode below explains the low-link rules. The
shipped implementation uses explicit DFS frames instead of native recursion;
call `kernel.findArticulationPoints()` directly in real code:

### Algorithm (Simplified Recursive Pseudocode)

```nim
proc findArticulationPoints[V, E](
    kernel: ListKernel[V, E]
): seq[VertexId] =
  ## Find all articulation points
  
  var disc = initTable[VertexId, int]()  # Discovery times
  var low = initTable[VertexId, int]()   # Low-link values
  var parent = initTable[VertexId, VertexId]()
  var ap = initTable[VertexId, bool]()   # Articulation points
  var time = 0
  
  proc dfs(u: VertexId) =
    var children = 0
    disc[u] = time
    low[u] = time
    inc time
    
    for edge in kernel.neighbors(u):
      let v = edge.target
      if v notin disc:
        inc children
        parent[v] = u
        dfs(v)
        low[u] = min(low[u], low[v])
        
        # u is articulation point if:
        # 1. u is root and has > 1 children
        # 2. u is not root and low[v] >= disc[u]
        if u notin parent and children > 1:
          ap[u] = true
        if u in parent and low[v] >= disc[u]:
          ap[u] = true
      
      elif v != parent.getOrDefault(u):
        low[u] = min(low[u], disc[v])
  
  for vertex in kernel.vertices():
    if vertex.id notin disc:
      dfs(vertex.id)
  
  for vertex in kernel.vertices():
    if ap.getOrDefault(vertex.id, false):
      result.add(vertex.id)
```

### Applications

1. **Network reliability**: find critical vertices
2. **Infrastructure**: identify single points of failure
3. **Social networks**: find key connectors

## Example: Dependency Cycle Detection

```nim
import UniGraph
import std/options

# Module dependencies
var deps = newImmutableGraph[string, float](Directed)

let modules = ["core", "utils", "io", "net", "crypto", "ui"]
var moduleIds: seq[VertexId] = @[]

for modName in modules:
  var id: VertexId
  (deps, id) = deps.addVertex(modName)
  moduleIds.add(id)

# Dependencies (circular!)
deps = deps.addEdge(moduleIds[0], moduleIds[1], 1.0)  # core → utils
deps = deps.addEdge(moduleIds[1], moduleIds[2], 1.0)  # utils → io
deps = deps.addEdge(moduleIds[2], moduleIds[3], 1.0)  # io → net
deps = deps.addEdge(moduleIds[3], moduleIds[5], 1.0)  # net → ui
deps = deps.addEdge(moduleIds[5], moduleIds[0], 1.0)  # ui → core (cycle!)
deps = deps.addEdge(moduleIds[0], moduleIds[4], 1.0)  # core → crypto

# Find SCCs
let sccs = deps.kernel.kosaraju()

echo "Dependency analysis:"
for i, scc in sccs:
  if scc.len > 1:
    echo "⚠️  Circular dependency (SCC #", i + 1, "):"
    for vertexId in scc:
      let modName = deps.getVertex(vertexId).get().data
      echo "   - ", modName
  else:
    let modName = deps.getVertex(scc[0]).get().data
    echo "✓ Module '", modName, "' has no circular dependencies"
```

**Verified output** (the cycle spans all five modules on the `core → ... →
ui → core` loop; only `crypto`, reached solely via the one-way `core →
crypto` edge, sits outside it):
```
Dependency analysis:
⚠️  Circular dependency (SCC #1):
   - ui
   - net
   - io
   - utils
   - core
✓ Module 'crypto' has no circular dependencies
```

## Practice Exercises

### Exercise 1: Condensation Graph
Build the condensation graph (DAG of SCCs).

```nim
type
  CondensationGraph = object
    sccIds: Table[VertexId, int]
    dag: ListKernel[int, float]  # SCC index as vertex

proc buildCondensationGraph[V, E](
    kernel: ListKernel[V, E],
    sccs: seq[seq[VertexId]]
): CondensationGraph =
  # Create DAG where each vertex is an SCC
  discard
```

### Exercise 2: 2-SAT Solver
Solve 2-SAT problems using SCCs.

```nim
proc solve2Sat(
    n: int,           # Number of variables
    clauses: seq[tuple[a, b: int]]  # (literal, literal)
): seq[bool] =
  # Build implication graph, find SCCs
  # If x and ¬x in same SCC: unsatisfiable
  # Otherwise: assign truth values
  discard
```

### Exercise 3: Bridge Detection
Find all bridges (cut edges) in an undirected graph.

```nim
proc findBridges[V, E](
    kernel: ListKernel[V, E]
): seq[tuple[u, v: VertexId]] =
  # Similar to articulation points
  # Edge (u,v) is bridge if low[v] > disc[u]
  discard
```

### Exercise 4: Biconnected Components
Find all biconnected components (maximal subgraphs without articulation points).

```nim
proc findBiconnectedComponents[V, E](
    kernel: ListKernel[V, E]
): seq[seq[Edge[E]]] =
  # Use stack to track edges during DFS
  discard
```

## References

- Wikipedia: [Strongly connected component](https://en.wikipedia.org/wiki/Strongly_connected_component)
- Wikipedia: [Kosaraju's algorithm](https://en.wikipedia.org/wiki/Kosaraju%27s_algorithm)
- Wikipedia: [Tarjan's strongly connected components algorithm](https://en.wikipedia.org/wiki/Tarjan%27s_strongly_connected_components_algorithm)
- Wikipedia: [Biconnected component](https://en.wikipedia.org/wiki/Biconnected_component) —
  articulation points and `findArticulationPoints`
- Wikipedia: [Directed acyclic graph](https://en.wikipedia.org/wiki/Directed_acyclic_graph) —
  the condensation graph
- Wikipedia: [2-satisfiability](https://en.wikipedia.org/wiki/2-satisfiability) —
  Exercise 2's implication-graph SCC reduction
"""
nbSave
