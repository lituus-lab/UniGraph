# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/algorithms/tsp.nim
## Traveling Salesman Problem algorithms
##
## This module implements:
## - Naive brute force (small graphs only)
## - 2-opt heuristic (larger graphs)

import ../types, ../kernels/list_kernel
import std/sequtils, std/algorithm, std/math, std/options, std/tables
import contracts

proc tspNaive*[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float {.closure.}
): tuple[path: seq[VertexId], cost: float] {.contractual.} =
  ## 🎯 TSP - Brute Force (small graphs only)
  ensure:
    # Either no tour was found (empty/too-large/disconnected graph) or a
    # full tour visiting every vertex once.
    result.path.len == 0 or result.path.len == kernel.vertexCount
  body:
    result.cost = Inf
    result.path = @[]

    let vertices = toSeq(kernel.vertices())
    if vertices.len == 0:
      return

    if vertices.len > 10:
      # Too expensive
      return

    # Try all permutations
    var vertexIds: seq[VertexId] = @[]
    for v in vertices:
      vertexIds.add(v.id)

    vertexIds.sort(proc(a, b: VertexId): int = cmp(a.id, b.id))

    let fixedStart = vertexIds[0]
    var remaining = if vertexIds.len > 1: vertexIds[1 .. ^1] else: @[]

    while true:
      let candidate = @[fixedStart] & remaining
      # Calculate cost of this permutation
      var cost = 0.0
      var valid = true

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

      if valid and cost < result.cost:
        result.cost = cost
        result.path = candidate

      # Next permutation
      if not remaining.nextPermutation():
        break

proc tsp2Opt*[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float {.closure.},
    initialPath: seq[VertexId] = @[],
    maxIterations: int = 1000
): tuple[path: seq[VertexId], cost: float] {.contractual.} =
  ## 🎯 TSP - 2-opt Heuristic
  require:
    # 2-opt only reorders an existing tour (segment reversal) -- it never
    # adds or drops vertices, so a caller-provided seed must already cover
    # every vertex exactly once.
    initialPath.len == 0 or initialPath.len == kernel.vertexCount
  ensure:
    result.path.len == 0 or result.path.len == kernel.vertexCount
  body:
    result.cost = Inf
    result.path = @[]

    let vertices = toSeq(kernel.vertices())
    if vertices.len == 0:
      return

    # Use initial path if provided, otherwise use vertex order
    if initialPath.len > 0:
      result.path = initialPath
    else:
      for v in vertices:
        result.path.add(v.id)

    # Calculate initial cost
    proc calcCost(path: seq[VertexId], knl: ListKernel[V, E], wp: proc(
        edge: Edge[E]): float {.closure.}): float =
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

      for i in 0..<result.path.len-1:
        for j in i+1..<result.path.len:
          # Try reversing segment [i, j]
          var newPath = result.path
          # Reverse segment manually
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

proc tspNearestNeighbor*[V, E](
    kernel: ListKernel[V, E],
    start: VertexId,
    weightProc: proc(edge: Edge[E]): float {.closure.}
): tuple[path: seq[VertexId], cost: float] {.contractual.} =
  ## 🎯 TSP - Nearest Neighbor Heuristic
  ensure:
    # Every vertex visited at most once, plus one closing return-to-start.
    result.path.len <= kernel.vertexCount + 1
  body:
    if kernel.getVertex(start).isNone:
      result.path = @[]
      result.cost = 0.0
      return

    result.path = @[start]
    result.cost = 0.0

    let vertices = toSeq(kernel.vertices())
    var visited = initTable[VertexId, bool]()
    visited[start] = true

    while result.path.len < vertices.len:
      let current = result.path[^1]
      var bestNext: Option[VertexId] = none(VertexId)
      var bestDist = Inf

      for vertex in vertices:
        if vertex.id notin visited:
          let edgeData = kernel.getEdge(current, vertex.id)
          if edgeData.isSome:
            let d = weightProc(newEdge(current, vertex.id, edgeData.get()))
            if d < bestDist:
              bestDist = d
              bestNext = some(vertex.id)

      if bestNext.isNone:
        break # No unvisited neighbors

      result.path.add(bestNext.get())
      result.cost += bestDist
      visited[bestNext.get()] = true

    if result.path.len != vertices.len:
      result.cost = Inf
      return

    # Return to start. A finite result always represents a closed tour.
    let edgeData = kernel.getEdge(result.path[^1], start)
    if edgeData.isNone:
      result.cost = Inf
      return
    result.cost += weightProc(newEdge(result.path[^1], start, edgeData.get()))
    result.path.add(start)

