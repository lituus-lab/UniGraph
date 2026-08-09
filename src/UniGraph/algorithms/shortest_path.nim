# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/algorithms/shortest_path.nim
## Shortest path algorithms
##
## This module implements:
## - Dijkstra's algorithm (positive weights)
## - A* algorithm (with heuristic)
## - Bellman-Ford algorithm (negative weights)

import ../types, ../kernel_concept, ../kernels/list_kernel,
    ../kernels/seq_kernel, ../kernels/matrix_kernel, ../kernels/csr_kernel
import std/[sequtils, tables, heapqueue, options, sets]

type
  DistanceMap* = Table[VertexId, float]
  ParentMap* = Table[VertexId, VertexId]

  # Use primitive tuple to avoid HeapQueue generic lookup bugs in Nim
  DistancePair* = tuple[distance: float, id: int, generation: uint16]

  DistancePairQueue* = HeapQueue[DistancePair]

proc dijkstra*[K, E, D](
    kernel: K,
    start: VertexId,
    weight: proc(edge: Edge[E]): D {.closure.},
    zero: D
): tuple[distances: Table[VertexId, D], parents: Table[VertexId, VertexId]] =
  ## Single-source shortest paths for non-negative weights, with a generic
  ## distance type.
  ##
  ## `D` needs `+` and `<`; `zero` is the distance from `start` to itself
  ## (0.0 for float, initRational(0, 1) for Rational, ...). Vertices absent
  ## from the distance table stand for "not reached yet", so `D` does not
  ## need an infinity value — exact numeric types work unchanged.
  mixin vertices, neighbors

  if kernel.getVertex(start).isNone:
    result.distances = initTable[VertexId, D]()
    result.parents = initTable[VertexId, VertexId]()
    result.distances[start] = zero
    return

  # Distances/parents accumulate in dense arrays-by-id, not directly in the
  # returned Tables: a hash table costs a hash on every heap-pop and every
  # edge relaxation, an array a direct index (see maxVertexId's doc comment
  # in kernel_concept.nim). The Tables are built once at the end instead.
  let capacity = kernel.capacityFor(start)
  var hasDist = newSeq[bool](capacity)
  var dist = newSeq[D](capacity)
  var vidOf = newSeq[VertexId](capacity) # the id's actual VertexId (right
                                         # generation), for the final Tables
  var hasParent = newSeq[bool](capacity)
  var parentOf = newSeq[VertexId](capacity)
  var visited = newSeq[bool](capacity)

  hasDist[start.id] = true
  dist[start.id] = zero
  vidOf[start.id] = start

  var pq = initHeapQueue[(D, int, uint16)]()
  pq.push((zero, start.id, start.generation))

  while pq.len > 0:
    let (_, cid, cgen) = pq.pop()
    if visited[cid]:
      continue
    visited[cid] = true
    let currentVertex = newVertexId(cid, cgen)
    let du = dist[cid]
    for edge in kernel.neighbors(currentVertex):
      let tid = edge.target.id
      let alt = du + weight(edge)
      if not hasDist[tid] or alt < dist[tid]:
        hasDist[tid] = true
        dist[tid] = alt
        vidOf[tid] = edge.target
        hasParent[tid] = true
        parentOf[tid] = currentVertex
        pq.push((alt, tid, edge.target.generation))

  result.distances = initTable[VertexId, D]()
  result.parents = initTable[VertexId, VertexId]()
  for id in 0 ..< capacity:
    if hasDist[id]:
      result.distances[vidOf[id]] = dist[id]
      if hasParent[id]:
        result.parents[vidOf[id]] = parentOf[id]

proc dijkstra*[K, E](
    kernel: K,
    start: VertexId,
    weightProc: proc(edge: Edge[E]): float {.closure.}
): tuple[distances: Table[VertexId, float], parents: Table[VertexId, VertexId]] =
  ## float64 distances with an implicit zero.
  dijkstra(kernel, start, weightProc, 0.0)

proc reconstructPath*(
    parents: Table[VertexId, VertexId],
    goal: VertexId
): seq[VertexId] =
  ## 🇬🇧 Reconstruct path from source to goal
  result = @[goal]
  var current = goal
  var visited = initHashSet[VertexId]()

  while current in parents and current notin visited:
    visited.incl(current)
    current = parents[current]
    result.insert(current, 0)

proc aStar*[K, E](
    kernel: K,
    start, goal: VertexId,
    weightProc: proc(edge: Edge[E]): float {.closure.},
    heuristic: proc(a, b: VertexId): float {.closure.}
): seq[VertexId] =
  ## 🎯 A* Algorithm - Pathfinding with Heuristic
  ##
  ## The returned path is optimal only when `heuristic` is consistent
  ## (monotone) — i.e. for every edge (u, v), `heuristic(u, goal) <=
  ## weight(u, v) + heuristic(v, goal)`. Consistency is stronger than mere
  ## admissibility (never overestimating the true cost): this implementation
  ## keeps a closed set (`visited`, below) and never reopens a vertex once
  ## popped, which is only safe under a consistent heuristic — an admissible
  ## but inconsistent one can still yield a suboptimal path here. Any
  ## heuristic still returns *a* valid path, just not necessarily the
  ## shortest one when it isn't consistent.
  mixin vertices, neighbors

  var gScore = initTable[VertexId, float]()       # Cost from start
  var fScore = initTable[VertexId, float]()       # gScore + heuristic
  var parents = initTable[VertexId, VertexId]()

  gScore[start] = 0.0
  fScore[start] = heuristic(start, goal)

  var pq = initHeapQueue[DistancePair]()
  pq.push((distance: fScore[start], id: start.id, generation: start.generation))

  var visited = initTable[VertexId, bool]()

  while pq.len > 0:
    let currentRaw = pq.pop()
    let currentVertex = newVertexId(currentRaw.id, currentRaw.generation)

    if currentVertex == goal:
      return reconstructPath(parents, goal)

    if currentVertex in visited:
      continue

    visited[currentVertex] = true

    for edge in kernel.neighbors(currentVertex):
      let tentativeG = gScore.getOrDefault(currentVertex, Inf) + weightProc(edge)

      if tentativeG < gScore.getOrDefault(edge.target, Inf):
        parents[edge.target] = currentVertex
        gScore[edge.target] = tentativeG
        fScore[edge.target] = tentativeG + heuristic(edge.target, goal)
        pq.push((distance: fScore[edge.target], id: edge.target.id,
            generation: edge.target.generation))

  # No path found
  result = @[]

proc bellmanFord*[K, E](
    kernel: K,
    start: VertexId,
    weightProc: proc(edge: Edge[E]): float {.closure.}
): tuple[distances: Table[VertexId, float], parents: Table[VertexId, VertexId],
    hasNegativeCycle: bool] =
  ## 🎯 Bellman-Ford Algorithm - Shortest Path (handles negative weights).
  ## When `hasNegativeCycle` is true, `distances` and `parents` are partial
  ## and unusable; `parents` may itself contain a cycle. Check the flag first.
  mixin vertices, neighbors

  result.distances = initTable[VertexId, float]()
  result.parents = initTable[VertexId, VertexId]()
  result.hasNegativeCycle = false

  # Initialize explicitly using vertices
  for vertex in kernel.vertices():
    result.distances[vertex.id] = Inf
  result.distances[start] = 0.0

  let verticesList = toSeq(kernel.vertices())
  let n = verticesList.len

  # Relax edges V-1 times
  for i in 0..<n-1:
    var changed = false
    for vertex in verticesList:
      if result.distances[vertex.id] == Inf:
        continue
      for edge in kernel.neighbors(vertex.id):
        # Skip edges to vertices not in the seeded table instead of raising
        # KeyError — a defensive guard, not a behavior change, since the
        # kernel only stores edges between existing vertices.
        if edge.target notin result.distances:
          continue
        let alt = result.distances[vertex.id] + weightProc(edge)
        if alt < result.distances[edge.target]:
          result.distances[edge.target] = alt
          result.parents[edge.target] = vertex.id
          changed = true
    if not changed:
      break # Early termination

  # Check for negative cycles
  for vertex in verticesList:
    if result.distances[vertex.id] == Inf:
      continue
    for edge in kernel.neighbors(vertex.id):
      if edge.target notin result.distances:
        continue
      let alt = result.distances[vertex.id] + weightProc(edge)
      if alt < result.distances[edge.target]:
        result.hasNegativeCycle = true
        return
