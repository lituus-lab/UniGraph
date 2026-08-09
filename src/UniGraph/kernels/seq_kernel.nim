# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/kernels/seq_kernel.nim
## Adjacency Sequence kernel implementation for dense/continuous IDs (DOD pattern)
##
## Space Complexity: O(max(V_id) + E)
## Add Vertex: Amortized O(1)
## Add Edge: O(1)
## Remove Vertex: O(V + E)
## Has Edge: O(degree)
##
## Best for: Meshes, geometric structures with continuous IDs, Data-Oriented Design (DOD).
## This kernel is optimized for cache locality using flat arrays (`seq`) instead of `Table`.

import ../types
import std/options, std/sequtils

type
  SeqKernel*[V, E] = object
    ## Adjacency list implementation optimized for dense IDs.
    ## Uses `seq` for O(1) continuous vertex lookup.
    vertexData*: seq[Option[Vertex[V]]]
    adjacency*: seq[seq[Edge[E]]]
    freeList*: seq[VertexId] # Reusable vertex slots
    nextId*: int
    edgeCount*: int
    activeVertexCount*: int
    graphType*: GraphType # Edge policy: Simple rejects self-loops and
                            # parallel edges; Multi allows parallel edges;
                            # Pseudo allows both. Defaults to Simple.

proc newSeqKernel*[V, E](capacity: int = 0): SeqKernel[V, E] =
  ## Create a new empty SeqKernel
  SeqKernel[V, E](
    vertexData: newSeqOfCap[Option[Vertex[V]]](capacity),
    adjacency: newSeqOfCap[seq[Edge[E]]](capacity),
    freeList: @[],
    nextId: 0,
    edgeCount: 0,
    activeVertexCount: 0,
    graphType: GraphType.Simple
  )

proc vertexCount*[V, E](kernel: SeqKernel[V, E]): int {.inline.} =
  ## Return the number of active vertices in the kernel
  kernel.activeVertexCount

proc edgeCount*[V, E](kernel: SeqKernel[V, E]): int {.inline.} =
  ## Return the number of edges in the kernel
  kernel.edgeCount

proc slotValid[V, E](kernel: SeqKernel[V, E], id: VertexId): bool {.inline.} =
  ## Full VertexId validation: bounds, live slot, and matching generation.
  ## Rejecting negative ids here keeps every `vertexData[id]` access in range
  ## and stops stale handles (right id, wrong generation) from reaching data.
  id.id >= 0 and id.id < kernel.vertexData.len and
    kernel.vertexData[id.id].isSome and
    kernel.vertexData[id.id].get().id.generation == id.generation

proc ensureCapacity[V, E](kernel: var SeqKernel[V, E], id: int) {.inline.} =
  if id >= kernel.vertexData.len:
    let newLen = id + 1
    let oldLen = kernel.vertexData.len
    kernel.vertexData.setLen(newLen)
    kernel.adjacency.setLen(newLen)
    for i in oldLen..<newLen:
      kernel.vertexData[i] = none(Vertex[V])
      kernel.adjacency[i] = @[]

proc addVertex*[V, E](kernel: var SeqKernel[V, E], data: V): VertexId =
  ## Add a new vertex with the given data.
  ## ID Stability: Uses generation counter.
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
    vertexId = newVertexId(kernel.nextId, 0'u16)
    kernel.nextId += 1

  kernel.ensureCapacity(vertexId.id)
  let vertex = newVertex(vertexId, data)
  kernel.vertexData[vertexId.id] = some(vertex)
  kernel.adjacency[vertexId.id] = @[]
  kernel.activeVertexCount += 1
  result = vertexId

proc getVertex*[V, E](kernel: SeqKernel[V, E], id: VertexId): Option[Vertex[V]] =
  if kernel.slotValid(id):
    return some(kernel.vertexData[id.id].get())
  none(Vertex[V])

proc removeVertex*[V, E](kernel: var SeqKernel[V, E], id: VertexId): bool =
  if not kernel.slotValid(id):
    return false

  # Remove all outgoing edges
  let edges = kernel.adjacency[id.id]
  kernel.edgeCount -= edges.len
  kernel.adjacency[id.id] = @[]

  # Remove all incoming edges
  for i in 0..<kernel.adjacency.len:
    if kernel.vertexData[i].isSome():
      var sourceEdges = kernel.adjacency[i]
      let initialLen = sourceEdges.len
      sourceEdges = sourceEdges.filterIt(it.target.id != id.id)
      kernel.edgeCount -= (initialLen - sourceEdges.len)
      kernel.adjacency[i] = sourceEdges

  kernel.vertexData[id.id] = none(Vertex[V])
  kernel.freeList.add(id)
  kernel.activeVertexCount -= 1
  result = true

proc addEdge*[V, E](
    kernel: var SeqKernel[V, E],
    source, target: VertexId,
    data: E
): bool =
  # Validate both endpoints by full id (bounds + liveness + generation) before
  # touching any sequence: a negative or stale handle returns false instead of
  # raising IndexDefect.
  if not kernel.slotValid(source) or not kernel.slotValid(target):
    return false

  # Self-loops only for Pseudo graphs
  if source == target and kernel.graphType != Pseudo:
    return false

  # Parallel edges only for non-Simple graphs
  if kernel.graphType == Simple:
    let edges = kernel.adjacency[source.id]
    for edge in edges:
      if edge.target == target:
        return false

  let edge = newEdge(source, target, data)
  kernel.adjacency[source.id].add(edge)
  kernel.edgeCount += 1
  result = true

proc hasEdge*[V, E](
    kernel: SeqKernel[V, E],
    source, target: VertexId
): bool =
  if not kernel.slotValid(source):
    return false

  for edge in kernel.adjacency[source.id]:
    if edge.target == target:
      return true
  result = false

proc getEdge*[V, E](
    kernel: SeqKernel[V, E],
    source, target: VertexId
): Option[E] =
  if not kernel.slotValid(source):
    return none(E)

  for edge in kernel.adjacency[source.id]:
    if edge.target == target:
      return some(edge.data)
  result = none(E)

proc removeEdge*[V, E](
    kernel: var SeqKernel[V, E],
    source, target: VertexId
): bool =
  if not kernel.slotValid(source):
    return false

  for i, edge in kernel.adjacency[source.id]:
    if edge.target == target:
      kernel.adjacency[source.id].delete(i)
      dec kernel.edgeCount
      return true
  false

proc neighbors*[V, E](
    kernel: SeqKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  if not kernel.slotValid(id):
    return @[]
  result = kernel.adjacency[id.id]

proc inNeighbors*[V, E](
    kernel: SeqKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  result = @[]
  if not kernel.slotValid(id): return
  for i in 0..<kernel.adjacency.len:
    if kernel.vertexData[i].isSome():
      for edge in kernel.adjacency[i]:
        if edge.target == id:
          result.add(edge)

proc outNeighbors*[V, E](
    kernel: SeqKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  kernel.neighbors(id)

iterator vertices*[V, E](kernel: SeqKernel[V, E]): Vertex[V] =
  for optV in kernel.vertexData:
    if optV.isSome():
      yield optV.get()

iterator edges*[V, E](kernel: SeqKernel[V, E]): Edge[E] =
  for i in 0..<kernel.adjacency.len:
    if kernel.vertexData[i].isSome():
      for edge in kernel.adjacency[i]:
        yield edge
