# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/kernels/list_kernel.nim
## Adjacency List kernel implementation for sparse graphs
##
## Space Complexity: O(V + E)
## Add Vertex: Amortized O(1)
## Add Edge: O(1)
## Remove Vertex: O(V + E)
## Has Edge: O(degree)
##
## Best for: Social networks, dependency graphs, and other sparse graphs

import ../types
import std/tables, std/sequtils, std/options

type
  ListKernel*[V, E] = object
    ## Adjacency list implementation for sparse graphs.
    ## Uses Table for O(1) vertex lookup and seq for neighbor lists.
    vertices*: Table[VertexId, Vertex[V]]
    adjacency*: Table[VertexId, seq[Edge[E]]]
    freeList*: seq[VertexId] # Reusable vertex slots
    nextId*: int
    edgeCount*: int
    graphType*: GraphType # Edge policy: Simple rejects self-loops and
                            # parallel edges; Multi allows parallel edges;
                            # Pseudo allows both. Defaults to Simple.

proc newListKernel*[V, E](): ListKernel[V, E] =
  ## Create a new empty ListKernel
  ListKernel[V, E](
    vertices: initTable[VertexId, Vertex[V]](),
    adjacency: initTable[VertexId, seq[Edge[E]]](),
    freeList: @[],
    nextId: 0,
    edgeCount: 0
  )

proc vertexCount*[V, E](kernel: ListKernel[V, E]): int {.inline.} =
  ## Return the number of vertices in the kernel
  kernel.vertices.len

proc edgeCount*[V, E](kernel: ListKernel[V, E]): int {.inline.} =
  ## Return the number of edges in the kernel
  kernel.edgeCount

proc addVertex*[V, E](kernel: var ListKernel[V, E], data: V): VertexId =
  ## Add a new vertex with the given data.
  ## Returns the VertexId for the new vertex.
  ## ID Stability: Uses generation counter to prevent dangling references.
  ## A slot whose generation saturated at uint16.max is retired (dropped from
  ## the free list, never reused) so the counter cannot wrap and revalidate a
  ## stale handle.
  var vertexId: VertexId
  var reused = false

  # Pop freed slots until one is not generation-saturated; saturated slots
  # are discarded, retiring their id permanently.
  while kernel.freeList.len > 0:
    let oldId = kernel.freeList.pop()
    if oldId.generation < high(uint16):
      vertexId = newVertexId(oldId.id, oldId.generation + 1)
      reused = true
      break

  if not reused:
    # Allocate new ID
    vertexId = newVertexId(kernel.nextId, 0'u16)
    kernel.nextId += 1

  let vertex = newVertex(vertexId, data)
  kernel.vertices[vertexId] = vertex
  kernel.adjacency[vertexId] = @[]
  result = vertexId

proc getVertex*[V, E](kernel: ListKernel[V, E], id: VertexId): Option[Vertex[V]] =
  ## Get a vertex by its ID.
  ## Returns Some(vertex) if exists, None otherwise.
  if id in kernel.vertices:
    result = some(kernel.vertices[id])
  else:
    result = none(Vertex[V])

proc removeVertex*[V, E](kernel: var ListKernel[V, E], id: VertexId): bool =
  ## Remove a vertex and all its incident edges.
  ## ID Stability: Other vertex IDs remain valid.
  ## Returns true if vertex was removed, false if not found.
  if id notin kernel.vertices:
    return false

  # Remove all outgoing edges
  if id in kernel.adjacency:
    let edges = kernel.adjacency[id]
    kernel.edgeCount -= edges.len
    kernel.adjacency.del(id)

  # Remove all incoming edges (O(V) operation)
  for _, edges in kernel.adjacency.mpairs:
    let initialLen = edges.len
    edges.keepItIf(it.target != id)
    kernel.edgeCount -= (initialLen - edges.len)

  # Remove vertex and add to free list for ID stability
  kernel.vertices.del(id)
  kernel.freeList.add(id)

  result = true

proc addEdge*[V, E](
    kernel: var ListKernel[V, E],
    source, target: VertexId,
    data: E
): bool =
  ## Add an edge from source to target with the given data.
  ## Returns false if either endpoint doesn't exist.
  ## Self-loops are rejected unless `graphType == Pseudo`; parallel edges are
  ## rejected unless `graphType != Simple` (Multi or Pseudo allow them).
  if source notin kernel.vertices or target notin kernel.vertices:
    return false

  # Self-loops only for Pseudo graphs
  if source == target and kernel.graphType != Pseudo:
    return false

  # Parallel edges only for non-Simple graphs
  if kernel.graphType == Simple:
    let edges = kernel.adjacency[source]
    for edge in edges:
      if edge.target == target:
        return false

  let edge = newEdge(source, target, data)
  kernel.adjacency[source].add(edge)
  kernel.edgeCount += 1
  result = true

proc hasEdge*[V, E](
    kernel: ListKernel[V, E],
    source, target: VertexId
): bool =
  ## Check if an edge exists from source to target.
  ## Returns false if either vertex doesn't exist.
  if source notin kernel.vertices or source notin kernel.adjacency:
    return false

  for edge in kernel.adjacency[source]:
    if edge.target == target:
      return true
  result = false

proc getEdge*[V, E](
    kernel: ListKernel[V, E],
    source, target: VertexId
): Option[E] =
  ## Get the data of an edge from source to target.
  ## Returns None if edge doesn't exist.
  if source notin kernel.adjacency:
    return none(E)

  for edge in kernel.adjacency[source]:
    if edge.target == target:
      return some(edge.data)
  result = none(E)

proc removeEdge*[V, E](
    kernel: var ListKernel[V, E],
    source, target: VertexId
): bool =
  ## Remove an edge from source to target.
  ## Returns true if edge was removed, false if not found.
  if source notin kernel.adjacency:
    return false

  for i, edge in kernel.adjacency[source]:
    if edge.target == target:
      kernel.adjacency[source].delete(i)
      dec kernel.edgeCount
      return true
  false

proc neighbors*[V, E](
    kernel: ListKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  ## Get all outgoing edges from a vertex.
  ## Returns empty sequence if vertex doesn't exist.
  if id notin kernel.adjacency:
    result = @[]
  else:
    result = kernel.adjacency[id]

proc inNeighbors*[V, E](
    kernel: ListKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  ## Get all incoming edges to a vertex (for directed graphs).
  ## Returns empty sequence if vertex doesn't exist.
  result = @[]
  for sourceId in kernel.adjacency.keys:
    for edge in kernel.adjacency[sourceId]:
      if edge.target == id:
        result.add(edge)

proc outNeighbors*[V, E](
    kernel: ListKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  ## Get all outgoing edges from a vertex (alias for neighbors).
  kernel.neighbors(id)

iterator vertices*[V, E](kernel: ListKernel[V, E]): Vertex[V] =
  ## Iterate over all vertices in the kernel
  for vertex in kernel.vertices.values:
    yield vertex

iterator edges*[V, E](kernel: ListKernel[V, E]): Edge[E] =
  ## Iterate over all edges in the kernel
  for edgeList in kernel.adjacency.values:
    for edge in edgeList:
      yield edge
