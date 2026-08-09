# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/algorithms/scc.nim
## Strongly Connected Components algorithms
##
## This module implements:
## - Kosaraju's algorithm (2-pass DFS)
## - Tarjan's algorithm (1-pass DFS)

import ../types, ../kernel_concept
import ../kernels/list_kernel, ../kernels/seq_kernel, ../kernels/csr_kernel,
    ../kernels/matrix_kernel
import std/sequtils, std/tables
import contracts

proc reverseGraph*[V, E](
    kernel: ListKernel[V, E]
): tuple[reversed: ListKernel[V, E], idMap: Table[VertexId, VertexId]] =
  ## Create the transpose of the graph (reverse all edges).
  ## addVertex allocates fresh VertexIds, so the transpose's vertex ids differ
  ## from the original's. Return the original→transpose id map alongside the
  ## transpose so callers (kosaraju's second pass) can translate between the
  ## two id namespaces instead of feeding original ids into transpose lookups.
  result.reversed = newListKernel[V, E]()
  result.idMap = initTable[VertexId, VertexId]()

  for vertex in kernel.vertices():
    let newId = result.reversed.addVertex(vertex.data)
    result.idMap[vertex.id] = newId

  # Add reversed edges
  for vertex in kernel.vertices():
    for edge in kernel.neighbors(vertex.id):
      discard result.reversed.addEdge(result.idMap[edge.target],
          result.idMap[vertex.id], edge.data)

proc dfsVisit*[V, E](
    kernel: ListKernel[V, E],
    start: VertexId,
    visited: var Table[VertexId, bool],
    finishOrder: var seq[VertexId]
) =
  ## DFS that records finish order without consuming the native call stack.
  type Frame = tuple[vertex: VertexId, nextNeighbor: int,
      edges: seq[Edge[E]]]
  visited[start] = true
  var frames: seq[Frame] = @[(start, 0, kernel.neighbors(start))]
  while frames.len > 0:
    let top = frames.high
    if frames[top].nextNeighbor >= frames[top].edges.len:
      finishOrder.add(frames[top].vertex)
      discard frames.pop()
      continue
    let target = frames[top].edges[frames[top].nextNeighbor].target
    inc frames[top].nextNeighbor
    if target notin visited:
      visited[target] = true
      frames.add((target, 0, kernel.neighbors(target)))

proc kosaraju*[V, E](kernel: ListKernel[V, E]): seq[seq[
    VertexId]] {.contractual.} =
  ## 🎯 Kosaraju's Algorithm - Strongly Connected Components
  ensure:
    # SCCs partition the vertex set: sizes sum to exactly vertexCount, every
    # vertex in exactly one component.
    result.foldl(a + b.len, 0) == kernel.vertexCount
  body:
    result = @[]

    let verts = toSeq(kernel.vertices())
    if verts.len == 0:
      return

    # First DFS pass - get finish order
    var visited = initTable[VertexId, bool]()
    var finishOrder: seq[VertexId] = @[]

    for vertex in verts:
      if vertex.id notin visited:
        dfsVisit(kernel, vertex.id, visited, finishOrder)

    # Second DFS pass on transpose. The transpose's vertices carry fresh ids
    # (reverseGraph's addVertex allocates them), so translate every original id
    # from finishOrder to its transpose id via idMap, and translate back when
    # recording the SCC. Track visited in the transpose id space during the
    # DFS, and mirror it into the original-id `visited` table so the outer loop
    # skips vertices already assigned to an SCC.
    let (reversedK, idMap) = kernel.reverseGraph()
    var tToOriginal = initTable[VertexId, VertexId]()
    for orig, transp in idMap:
      tToOriginal[transp] = orig

    visited = initTable[VertexId, bool]()
    var tVisited = initTable[VertexId, bool]()

    # Process vertices in reverse finish order
    for i in countdown(finishOrder.len - 1, 0):
      let startVertex = finishOrder[i]
      if startVertex in visited:
        continue
      if startVertex notin idMap:
        # Isolated vertex with no incident edges: it is its own SCC.
        result.add(@[startVertex])
        visited[startVertex] = true
        continue

      var scc: seq[VertexId] = @[]
      var stack = @[idMap[startVertex]]

      while stack.len > 0:
        let current = stack.pop()
        if current in tVisited:
          continue
        tVisited[current] = true
        let original = tToOriginal[current]
        visited[original] = true
        scc.add(original)

        for edge in reversedK.neighbors(current):
          if edge.target notin tVisited:
            stack.add(edge.target)

      result.add(scc)

proc tarjan*[K](kernel: K): seq[seq[VertexId]] {.contractual.} =
  ## Strongly connected components in one DFS pass (index/lowlink).
  ## Works on any GraphKernel.
  ensure:
    result.foldl(a + b.len, 0) == kernel.vertexCount
  body:
    mixin vertices, neighbors, vertexCount

    result = @[]

    let verts = toSeq(kernel.vertices())
    if verts.len == 0:
      return

    # onStack/hasIndex/indices/lowlinks are dense arrays-by-id, not
    # Table[VertexId, _]: a hash table costs a hash on every edge visited
    # during the DFS, an array a direct index -- see maxVertexId's doc
    # comment in kernel_concept.nim.
    let capacity = kernel.maxVertexId() + 1
    var index = 0
    var stack: seq[VertexId] = @[]
    var onStack = newSeq[bool](capacity)
    var hasIndex = newSeq[bool](capacity)
    var indices = newSeq[int](capacity)
    var lowlinks = newSeq[int](capacity)

    type
      NeighborSeq = typeof(toSeq(kernel.neighbors(verts[0].id)))
      Frame = tuple[vertex: VertexId, parent: VertexId, hasParent: bool,
          nextNeighbor: int, edges: NeighborSeq]

    proc discover(u: VertexId) =
      indices[u.id] = index
      lowlinks[u.id] = index
      hasIndex[u.id] = true
      inc index
      stack.add(u)
      onStack[u.id] = true

    for vertex in verts:
      if hasIndex[vertex.id.id]:
        continue
      discover(vertex.id)
      var frames: seq[Frame] = @[(vertex.id, default(VertexId), false, 0,
          toSeq(kernel.neighbors(vertex.id)))]
      while frames.len > 0:
        let top = frames.high
        if frames[top].nextNeighbor < frames[top].edges.len:
          let v = frames[top].edges[frames[top].nextNeighbor].target
          inc frames[top].nextNeighbor
          if not hasIndex[v.id]:
            discover(v)
            frames.add((v, frames[top].vertex, true, 0,
                toSeq(kernel.neighbors(v))))
          elif onStack[v.id]:
            lowlinks[frames[top].vertex.id] = min(
                lowlinks[frames[top].vertex.id], indices[v.id])
          continue

        let frame = frames.pop()
        if frame.hasParent:
          lowlinks[frame.parent.id] = min(lowlinks[frame.parent.id],
              lowlinks[frame.vertex.id])
        if lowlinks[frame.vertex.id] == indices[frame.vertex.id]:
          var component: seq[VertexId] = @[]
          while true:
            let w = stack.pop()
            onStack[w.id] = false
            component.add(w)
            if w == frame.vertex:
              break
          result.add(component)

proc findArticulationPoints*[K](kernel: K): seq[VertexId] =
  ## Cut vertices in an undirected Simple graph (Tarjan low-link DFS).
  ## Parallel edges are outside this procedure's contract.

  result = @[]

  let verts = toSeq(kernel.vertices())
  if verts.len == 0:
    return

  var disc = initTable[VertexId, int]()
  var low = initTable[VertexId, int]()
  var parent = initTable[VertexId, VertexId]()
  var ap = initTable[VertexId, bool]()
  var time = 0
  type
    NeighborSeq = typeof(toSeq(kernel.neighbors(verts[0].id)))
    Frame = tuple[vertex: VertexId, nextNeighbor: int,
        children: int, edges: NeighborSeq]

  for vertex in verts:
    if vertex.id in disc:
      continue
    disc[vertex.id] = time
    low[vertex.id] = time
    inc time
    var frames: seq[Frame] = @[(vertex.id, 0, 0,
        toSeq(kernel.neighbors(vertex.id)))]
    while frames.len > 0:
      let top = frames.high
      if frames[top].nextNeighbor < frames[top].edges.len:
        let v = frames[top].edges[frames[top].nextNeighbor].target
        inc frames[top].nextNeighbor
        if v notin disc:
          inc frames[top].children
          parent[v] = frames[top].vertex
          disc[v] = time
          low[v] = time
          inc time
          frames.add((v, 0, 0, toSeq(kernel.neighbors(v))))
        elif v != parent.getOrDefault(frames[top].vertex,
            VertexId(id: -1, generation: 0)):
          low[frames[top].vertex] = min(low[frames[top].vertex], disc[v])
        continue

      let frame = frames.pop()
      if frame.vertex notin parent:
        if frame.children > 1:
          ap[frame.vertex] = true
      else:
        let p = parent[frame.vertex]
        low[p] = min(low[p], low[frame.vertex])
        if p in parent and low[frame.vertex] >= disc[p]:
          ap[p] = true

  for vertex in verts:
    if ap.getOrDefault(vertex.id, false):
      result.add(vertex.id)
