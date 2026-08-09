# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook

nbInit(theme = useNimibook)
nbText: "# Traveling Salesman Problem"
nbText: """
The **Traveling Salesman Problem (TSP)** is one of the most famous NP-hard optimization problems.

## Problem Definition

Given:
- A set of n cities
- Distances (or costs) between each pair of cities

Find:
- The shortest possible route that visits each city exactly once and returns to the start

### Mathematical Formulation

For a complete graph G = (V, E) with edge weights w:

**Minimize**: Σ w(vi, vi+1) for i = 1 to n-1, plus w(vn, v1)

**Subject to**: Each vertex visited exactly once

### Visualization

```
Cities: A, B, C, D, E

Possible tour: A → B → C → D → E → A
Cost: 10 + 15 + 20 + 12 + 18 = 75

Optimal tour: A → C → E → B → D → A
Cost: 8 + 12 + 14 + 10 + 16 = 60
```

## Complexity

### Why is TSP Hard?

**Number of possible tours**: (n-1)! / 2 (for symmetric TSP)

| Cities | Possible Tours |
|--------|----------------|
| 5 | 12 |
| 10 | 181,440 |
| 15 | ~43.6 billion |
| 20 | ~60 quadrillion |
| 60 | More than atoms in the universe! |

### NP-Hardness

- **Optimization TSP is NP-hard**: no polynomial-time exact algorithm is
  known for general instances.
- **A proposed tour is easy to check**: in O(n), verify that every city occurs
  once and add its edge costs. That verifies the tour and its cost, not that
  no cheaper tour exists.
- **Decision TSP is NP-complete**: the yes/no question “is there a tour of
  cost at most K?” has a polynomial-time certificate.

## Exact Algorithms

### Brute Force (Naive)

Try all permutations and find the minimum.

```nim
import UniGraph, algorithm
import std/sequtils

proc tspNaive[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float
): tuple[path: seq[VertexId], cost: float] =
  
  result.cost = Inf
  result.path = @[]
  
  let vertices = toSeq(kernel.vertices())
  if vertices.len == 0:
    return
  
  if vertices.len > 10:
    # Too expensive for large graphs
    return
  
  # Create initial permutation
  var vertexIds: seq[VertexId] = @[]
  for v in vertices:
    vertexIds.add(v.id)
  
  # Sort for deterministic order
  vertexIds.sort(proc(a, b: VertexId): int =
    cmp(a.id, b.id)
  )
  
  # Pin one start: rotations of the same cycle need not be tested again.
  let fixedStart = vertexIds[0]
  var remaining = if vertexIds.len > 1: vertexIds[1 .. ^1] else: @[]

  # Try all permutations of the remaining vertices
  while true:
    let candidate = @[fixedStart] & remaining
    var cost = 0.0
    var valid = true
    
    # Calculate tour cost
    for i in 0..<candidate.len-1:
      let edgeData = kernel.getEdge(candidate[i], candidate[i+1])
      if edgeData.isNone:
        valid = false
        break
      cost += weightProc(newEdge(candidate[i], candidate[i+1], edgeData.get()))
    
    # Return to start
    if valid:
      let edgeData = kernel.getEdge(candidate[^1], candidate[0])
      if edgeData.isNone:
        valid = false
      else:
        cost += weightProc(newEdge(candidate[^1], candidate[0], edgeData.get()))
    
    # Update best
    if valid and cost < result.cost:
      result.cost = cost
      result.path = candidate
    
    # Next permutation
    if not remaining.nextPermutation():
      break
```

**Complexity**: O(n · (n-1)!): the start is fixed, then each of the
`(n-1)!` candidates is priced in O(n)

**Use case**: Only for n ≤ 10

## Heuristic Algorithms

### Nearest Neighbor

Greedy approach: always visit the nearest unvisited city.

```nim
proc tspNearestNeighbor[V, E](
    kernel: ListKernel[V, E],
    start: VertexId,
    weightProc: proc(edge: Edge[E]): float
): tuple[path: seq[VertexId], cost: float] =
  if kernel.getVertex(start).isNone:
    return (@[], 0.0)
  
  result.path = @[start]
  result.cost = 0.0
  
  let vertices = toSeq(kernel.vertices())
  var visited = initTable[VertexId, bool]()
  visited[start] = true
  
  while result.path.len < vertices.len:
    let current = result.path[^1]
    var bestNext: Option[VertexId] = none(VertexId)
    var bestDist = Inf
    
    # Find nearest unvisited neighbor
    for vertex in vertices:
      if vertex.id notin visited:
        let edgeData = kernel.getEdge(current, vertex.id)
        if edgeData.isSome:
          let d = weightProc(newEdge(current, vertex.id, edgeData.get()))
          if d < bestDist:
            bestDist = d
            bestNext = some(vertex.id)
    
    if bestNext.isNone:
      result.cost = Inf
      return
    
    result.path.add(bestNext.get())
    result.cost += bestDist
    visited[bestNext.get()] = true
  
  # Return to start; without this edge there is no tour.
  let edgeData = kernel.getEdge(result.path[^1], start)
  if edgeData.isNone:
    result.cost = Inf
    return
  result.cost += weightProc(newEdge(result.path[^1], start, edgeData.get()))
  result.path.add(start)
```

**Complexity**: O(n²)

**Quality**: No fixed approximation guarantee for arbitrary weighted graphs;
the result depends on the starting city and the weight structure

**Advantages**:
- ✅ Very fast
- ✅ Simple to implement
- ✅ Works for large instances

**Disadvantages**:
- ❌ Can produce poor solutions
- ❌ Depends on starting city

### 2-Opt Heuristic

Iteratively improve a tour by swapping edges.

```nim
proc tsp2Opt[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float,
    initialPath: seq[VertexId] = @[],
    maxIterations: int = 1000
): tuple[path: seq[VertexId], cost: float] =
  
  result.cost = Inf
  result.path = @[]
  
  let vertices = toSeq(kernel.vertices())
  if vertices.len == 0:
    return
  
  # Initialize with given path or vertex order
  if initialPath.len > 0:
    result.path = initialPath
  else:
    for v in vertices:
      result.path.add(v.id)
  
  # Cost calculation helper — takes the kernel/weightProc as explicit
  # params (not a closure over the outer ones) so this nested proc has no
  # captured state; that's what the real shipped `tsp2Opt` does too.
  proc calcCost(path: seq[VertexId], knl: ListKernel[V, E],
      wp: proc(edge: Edge[E]): float): float =
    result = 0.0
    for i in 0..<path.len-1:
      let edgeData = knl.getEdge(path[i], path[i+1])
      if edgeData.isNone:
        return Inf
      result += wp(newEdge(path[i], path[i+1], edgeData.get()))
    let edgeData = knl.getEdge(path[^1], path[0])
    if edgeData.isNone:
      return Inf
    result += wp(newEdge(path[^1], path[0], edgeData.get()))

  result.cost = calcCost(result.path, kernel, weightProc)
  
  # 2-opt iterations
  var improved = true
  var iterations = 0
  
  while improved and iterations < maxIterations:
    improved = false
    inc iterations
    
    # Try all possible 2-opt swaps
    for i in 0..<result.path.len-1:
      for j in i+1..<result.path.len:
        # Reverse segment [i, j]
        var newPath = result.path
        var left = i
        var right = j
        while left < right:
          let temp = newPath[left]
          newPath[left] = newPath[right]
          newPath[right] = temp
          inc left
          dec right
        
        let newCost = calcCost(newPath, kernel, weightProc)
        if newCost < result.cost:
          result.cost = newCost
          result.path = newPath
          improved = true
```

### How 2-Opt Works

```
Original tour:     A → B → C → D → E → A
                   \         /
                    \       /
                     ‾‾‾‾‾‾

2-opt swap (B-C with E-A):
New tour:          A → B → E → D → C → A

Remove edges: (B,C) and (E,A)
Add edges: (B,E) and (C,A)
```

**Complexity**: O(n³) per full sweep — the `i, j` double loop is O(n²)
candidate swaps, and `calcCost` re-walks the whole tour (O(n)) for each one
instead of computing the swap's cost delta in O(1). Typically converges in
O(n) sweeps in practice.

**Quality**: Much better than nearest neighbor, often within 5% of optimal

## Advanced Techniques

### 3-Opt Heuristic

Remove 3 edges and reconnect in the best way (7 possibilities).

**Quality**: Better than 2-opt, but O(n³) per iteration

### Lin-Kernighan Heuristic

Adaptive k-opt: dynamically choose how many edges to swap.

**Quality**: One of the best heuristics, used in production

### Simulated Annealing

Probabilistic approach that accepts worse solutions with decreasing probability.

```nim
proc tspSimulatedAnnealing[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float,
    initialTemp: float = 1000.0,
    coolingRate: float = 0.995
): tuple[path: seq[VertexId], cost: float] =
  # Start with random tour
  # Iteratively make random 2-opt swaps
  # Accept if better, or with probability exp(-Δ/T) if worse
  # Decrease temperature over time
  discard
```

### Genetic Algorithms

Evolutionary approach with crossover and mutation.

**Advantages**:
- ✅ Can escape local optima
- ✅ Parallelizable
- ✅ Good for very large instances

## Approximation Algorithms

### Christofides Algorithm

For **metric TSP** (triangle inequality holds):

1. Find MST
2. Find minimum weight perfect matching on odd-degree vertices
3. Combine to form Eulerian graph
4. Convert to Hamiltonian cycle

**Guarantee**: At most 1.5× optimal

**Complexity**: O(n³)

## Practical Example

```nim
import UniGraph, random

# Delivery route optimization
var deliveryGraph = newImmutableGraph[string, float](Directed)

# Warehouses
let warehouses = ["Central", "North", "South", "East", "West", "Industrial"]
var warehouseIds: seq[VertexId] = @[]

for wh in warehouses:
  var id: VertexId
  (deliveryGraph, id) = deliveryGraph.addVertex(wh)
  warehouseIds.add(id)

# Distances (km) - complete graph, symmetric (distance(i,j) == distance(j,i),
# as real road distances usually are). Roll the distance once per pair, not
# once per direction — rolling it twice would make the two directions
# different, which is a different problem (asymmetric TSP, see Exercise 3)
# that 2-opt as implemented here does not solve correctly.
randomize()
for i in 0..<warehouses.len:
  for j in (i+1)..<warehouses.len:
    let dist = (rand(100) + 10).float  # 10-110 km
    deliveryGraph = deliveryGraph.addEdge(warehouseIds[i], warehouseIds[j], dist)
    deliveryGraph = deliveryGraph.addEdge(warehouseIds[j], warehouseIds[i], dist)

proc distance(edge: Edge[float]): float =
  edge.data

# Solve with 2-opt (start from nearest neighbor)
let nnResult = deliveryGraph.kernel.tspNearestNeighbor(warehouseIds[0], distance)
# deliveryGraph is complete, so nearest-neighbor necessarily returns a closed
# path. tsp2Opt closes the path itself; drop that repeated start vertex first.
doAssert nnResult.path.len > 1 and nnResult.path[0] == nnResult.path[^1]
let optimizedResult = deliveryGraph.kernel.tsp2Opt(
  distance,
  nnResult.path[0 ..^ 2],
  maxIterations = 500
)

echo "Delivery Route Optimization"
echo "==========================="
echo "Starting point: ", warehouses[0]
echo ""
echo "Nearest Neighbor solution:"
echo "  Route: ", nnResult.path
echo "  Distance: ", nnResult.cost, " km"
echo ""
echo "2-Opt optimized solution:"
echo "  Route: ", optimizedResult.path
echo "  Distance: ", optimizedResult.cost, " km"
echo "  Improvement: ", (nnResult.cost - optimizedResult.cost) / nnResult.cost * 100, "%"
```

## Algorithm Comparison

| Algorithm | Time | Quality | Best For |
|-----------|------|---------|----------|
| **Brute Force** | O(n · (n-1)!) | Optimal | n ≤ 10 (enforced by UniGraph) |
| **Nearest Neighbor** | O(n²) | No fixed guarantee in this API | Fast seed tour |
| **2-Opt** | O(n³) per sweep | Stops at a 2-opt local optimum | Small graphs |
| **3-Opt** | O(n³) candidate triples, plus repricing | Not provided by UniGraph | — |
| **Lin-Kernighan** | Variable | Not provided by UniGraph | — |
| **Christofides** | Depends on matching implementation | Not provided by UniGraph | — |

## Practice Exercises

### Exercise 1: Multiple Salesmen (mTSP)
Extend TSP to multiple salesmen starting from the same depot.

```nim
proc mtsp[V, E](
    kernel: ListKernel[V, E],
    depot: VertexId,
    numSalesmen: int,
    weightProc: proc(edge: Edge[E]): float
): seq[seq[VertexId]] =
  # Return: one route per salesman
  # All routes start and end at depot
  # Each city visited exactly once (by one salesman)
  discard
```

### Exercise 2: TSP with Time Windows
Each city must be visited within a specific time window.

```nim
type
  TimeWindow = object
    earliest, latest: float

proc tspTimeWindows[V, E](
    kernel: ListKernel[V, E],
    start: VertexId,
    windows: Table[VertexId, TimeWindow],
    weightProc: proc(edge: Edge[E]): float
): tuple[path: seq[VertexId], cost: float, feasible: bool] =
  discard
```

### Exercise 3: Asymmetric TSP
Handle cases where distance(A,B) ≠ distance(B,A).

```nim
proc tspAsymmetric[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float
): tuple[path: seq[VertexId], cost: float] =
  # Graph may not be symmetric: distance(A,B) != distance(B,A).
  # Standard 2-opt does NOT carry over unchanged. A 2-opt move reverses a
  # segment of the tour; on a symmetric instance the two removed edges are
  # the only ones whose cost changes (every reversed interior edge costs
  # the same read forwards or backwards), so the swap's cost delta is O(1).
  # On an asymmetric instance every interior edge of the reversed segment
  # is now traversed in the opposite direction, at a potentially different
  # cost, so the whole segment must be re-priced -- the O(1) delta trick
  # is invalid, and a naive port would either recompute the full tour cost
  # per candidate (correct but O(n) slower per candidate) or silently
  # produce wrong costs by reusing the symmetric delta formula.
  discard
```

### Exercise 4: Bottleneck TSP
Minimize the maximum edge weight (not the sum).

```nim
proc bottleneckTSP[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float
): tuple[path: seq[VertexId], bottleneckCost: float] =
  # Minimize max edge weight in tour
  discard
```

## Real-World Applications

1. **Logistics**: Delivery route planning
2. **Manufacturing**: PCB drilling, machine scheduling
3. **Genomics**: DNA sequencing
4. **Astronomy**: Telescope scheduling
5. **VLSI Design**: Circuit layout optimization
6. **Emergency Services**: Ambulance routing

## References

- Wikipedia: [Travelling salesman problem](https://en.wikipedia.org/wiki/Travelling_salesman_problem)
- Wikipedia: [NP-hardness](https://en.wikipedia.org/wiki/NP-hardness)
- Wikipedia: [2-opt](https://en.wikipedia.org/wiki/2-opt)
- Wikipedia: [Nearest neighbour algorithm](https://en.wikipedia.org/wiki/Nearest_neighbour_algorithm)
- Wikipedia: [Christofides algorithm](https://en.wikipedia.org/wiki/Christofides_algorithm)
- Wikipedia: [Lin–Kernighan heuristic](https://en.wikipedia.org/wiki/Lin%E2%80%93Kernighan_heuristic)
- Wikipedia: [Simulated annealing](https://en.wikipedia.org/wiki/Simulated_annealing)
"""
nbSave
