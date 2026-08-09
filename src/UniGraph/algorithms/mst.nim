# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/algorithms/mst.nim
## Minimum Spanning Tree algorithms
##
## This module implements:
## - Prim's algorithm
## - Kruskal's algorithm with Union-Find

import ../types, ../kernel_concept
import ../kernels/list_kernel, ../kernels/seq_kernel, ../kernels/csr_kernel,
    ../kernels/matrix_kernel
import std/sequtils, std/tables, std/heapqueue, std/algorithm
import contracts

type
  EdgeWithWeight*[E; D] = object
    ## An edge paired with its extracted weight, ordered by weight.
    edge*: Edge[E]
    weight*: D

  UnionFind = object
    parent: seq[int]
    rank: seq[int]


proc `<`*[E, D](a, b: EdgeWithWeight[E, D]): bool =
  ## Heap/sort order: by extracted weight (only `<` is required of D).
  a.weight < b.weight

proc initUnionFind(n: int): UnionFind =
  result.parent = newSeq[int](n)
  result.rank = newSeq[int](n)
  for i in 0..<n:
    result.parent[i] = i
    result.rank[i] = 0

proc find(uf: var UnionFind; x: int): int =
  if uf.parent[x] != x:
    uf.parent[x] = uf.find(uf.parent[x]) # Path compression
  result = uf.parent[x]

proc union(uf: var UnionFind; x, y: int): bool =
  ## Returns true if union was performed (not already in same set)
  let rootX = uf.find(x)
  let rootY = uf.find(y)

  if rootX == rootY:
    return false # Already in same set

  # Union by rank
  if uf.rank[rootX] < uf.rank[rootY]:
    uf.parent[rootX] = rootY
  elif uf.rank[rootX] > uf.rank[rootY]:
    uf.parent[rootY] = rootX
  else:
    uf.parent[rootY] = rootX
    inc uf.rank[rootX]

  result = true

proc prim*[K, E, D](
    kernel: K;
    weightProc: proc(edge: Edge[E]): D {.closure.}
): seq[Edge[E]] {.contractual.} =
  ## Minimum spanning tree by greedy frontier growth (priority queue of
  ## crossing edges). Works on any GraphKernel; `D` is the weight type and
  ## only needs `<` (float, Rational, Fixed, ...).
  ensure:
    # A spanning forest never has more edges than vertexCount - 1 (0 for an
    # empty or single-vertex graph).
    result.len <= max(0, kernel.vertexCount - 1)
  body:
    mixin vertices, neighbors, vertexCount
    result = @[]

    let verts = toSeq(kernel.vertices())
    if verts.len == 0:
      return

    # inMst is a dense array-by-id, not Table[VertexId, bool]: a hash table
    # costs a hash on every access, an array a direct index -- see
    # maxVertexId's doc comment in kernel_concept.nim.
    var inMst = newSeq[bool](kernel.maxVertexId() + 1)

    # The frontier queue stores (weight, index-into-stash): tuples only need
    # `<` on D, and the edge payload stays out of the comparison.
    var stash: seq[Edge[E]] = @[]
    var pq = initHeapQueue[(D, int)]()

    # Robust start: find the first vertex that actually has neighbors
    var startVertex = verts[0].id
    for v in verts:
      if kernel.neighbors(v.id).len > 0:
        startVertex = v.id
        break

    inMst[startVertex.id] = true

    for edge in kernel.neighbors(startVertex):
      stash.add(edge)
      pq.push((weightProc(edge), stash.high))

    while result.len < verts.len - 1:
      # Grow the current component's frontier as far as it reaches.
      while pq.len > 0 and result.len < verts.len - 1:
        let (_, idx) = pq.pop()
        let currentEdge = stash[idx]

        if inMst[currentEdge.target.id]:
          continue

        result.add(currentEdge)
        inMst[currentEdge.target.id] = true

        for edge in kernel.neighbors(currentEdge.target):
          if not inMst[edge.target.id]:
            stash.add(edge)
            pq.push((weightProc(edge), stash.high))

      if result.len == verts.len - 1:
        break

      # Disconnected graph: the current component's frontier is exhausted but
      # vertices remain. Restart from the next unvisited vertex that has
      # neighbors, producing a spanning forest (matching kruskal) instead of
      # only the start component's tree.
      var restarted = false
      for v in verts:
        if not inMst[v.id.id] and kernel.neighbors(v.id).len > 0:
          inMst[v.id.id] = true
          for edge in kernel.neighbors(v.id):
            if not inMst[edge.target.id]:
              stash.add(edge)
              pq.push((weightProc(edge), stash.high))
          restarted = true
          break
      if not restarted:
        break # remaining vertices are isolated; nothing more to span

proc kruskal*[K, E, D](
    kernel: K;
    weightProc: proc(edge: Edge[E]): D {.closure.}
): seq[Edge[E]] {.contractual.} =
  ## Minimum spanning tree by global edge sort + Union-Find cycle test.
  ## Works on any GraphKernel; `D` only needs `<`.
  ensure:
    result.len <= max(0, kernel.vertexCount - 1)
  body:
    mixin vertices, neighbors, vertexCount

    result = @[]

    let verts = toSeq(kernel.vertices())
    if verts.len == 0:
      return

    # Create vertex ID to index mapping: dense array-by-id, not
    # Table[VertexId, int] -- looked up twice per edge below.
    var idToIndex = newSeq[int](kernel.maxVertexId() + 1)
    for i in 0 ..< idToIndex.len:
      idToIndex[i] = -1
    for i, v in verts:
      idToIndex[v.id.id] = i

    # Collect all edges
    var allEdges: seq[EdgeWithWeight[E, D]] = @[]
    for vertex in verts:
      for edge in kernel.neighbors(vertex.id):
        allEdges.add(EdgeWithWeight[E, D](edge: edge, weight: weightProc(edge)))

    # Sort edges by weight
    sort(allEdges,
      proc(a, b: EdgeWithWeight[E, D]): int {.closure.} =
      # only `<` is required of D
      if a.weight < b.weight: return -1
      elif b.weight < a.weight: return 1
      else: return 0
    )

    # Initialize Union-Find
    var uf = initUnionFind(verts.len)

    # Add edges if they don't create a cycle
    for edgeWithWeight in allEdges:
      let edge = edgeWithWeight.edge

      let idx1 = idToIndex[edge.source.id]
      let idx2 = idToIndex[edge.target.id]

      if idx1 == -1 or idx2 == -1:
        continue

      if uf.union(idx1, idx2):
        result.add(edge)

        if result.len == verts.len - 1:
          break # MST complete





