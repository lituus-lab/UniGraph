# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/kernels/matrix_kernel.nim
## Adjacency Matrix kernel implementation for dense graphs
##
## Space Complexity: O(N²)
## Add Vertex: O(1)
## Add Edge: O(1)
## Remove Vertex: O(N)
## Has Edge: O(1)
##
## Best for: Dense graphs, complete graphs, small fixed-size graphs
## Fixed maximum capacity: construction rejects requests above 256. Storage is
## allocated for the requested capacity, rather than the maximum.

import ../types
import std/options

type
  MatrixKernel*[V, E] = object
    ## Adjacency matrix implementation for dense graphs.
    ## Uses arrays for O(1) edge lookup.
    ## When N is known at compile-time, entire structure allocated on stack.
    vertices*: seq[Option[Vertex[V]]]
    matrix*: seq[Option[E]] # Flat capacity × capacity edge matrix
    size*: int # Slot high-water mark
    activeVertexCount*: int
    edgeCount*: int
    capacity*: int
    graphType*: GraphType # Edge policy: Simple rejects self-loops and
                            # parallel edges; Multi allows parallel edges;
                            # Pseudo allows both. A single matrix cell holds one
                            # edge, so MatrixKernel cannot store parallel edges —
                            # a duplicate addEdge under Multi/Pseudo overwrites the
                            # existing data instead of adding a second edge.

proc newMatrixKernel*[V, E](capacity: int = 256): MatrixKernel[V, E] =
  ## Create a new empty MatrixKernel with given capacity.
  ## Raises if `capacity` exceeds the fixed 256 backing array size — this
  ## used to be silently clamped to 256, which let a graph past 256
  ## vertices fail later with a confusing IndexDefect from addVertex.
  if capacity > 256:
    raise newException(RangeDefect,
        "MatrixKernel capacity " & $capacity & " exceeds the fixed limit of 256")

  result = MatrixKernel[V, E]()
  result.vertices = newSeq[Option[Vertex[V]]](capacity)
  result.matrix = newSeq[Option[E]](capacity * capacity)
  result.size = 0
  result.activeVertexCount = 0
  result.edgeCount = 0
  result.capacity = capacity

template cell[V, E](kernel: MatrixKernel[V, E]; row, col: int): untyped =
  kernel.matrix[row * kernel.capacity + col]

template cell[V, E](kernel: var MatrixKernel[V, E]; row, col: int): untyped =
  kernel.matrix[row * kernel.capacity + col]

proc vertexCount*[V, E](kernel: MatrixKernel[V, E]): int {.inline.} =
  ## Return the number of vertices in the kernel
  kernel.activeVertexCount

proc edgeCount*[V, E](kernel: MatrixKernel[V, E]): int {.inline.} =
  ## Return the number of edges in the kernel
  kernel.edgeCount

proc slotValid[V, E](kernel: MatrixKernel[V, E];
    id: VertexId): bool {.inline.} =
  ## Full VertexId validation: bounds, live slot, and matching generation.
  ## A forged generation on a live slot could otherwise bypass the self-loop
  ## and duplicate-edge checks and mutate another vertex's edge state.
  id.id >= 0 and id.id < kernel.size and kernel.vertices[id.id].isSome and
    kernel.vertices[id.id].get().id == id

proc addVertex*[V, E](kernel: var MatrixKernel[V, E]; data: V): VertexId =
  ## Add a new vertex with the given data.
  ## Returns the VertexId for the new vertex.
  ## O(1) operation.
  if kernel.size >= kernel.capacity:
    raise newException(IndexDefect, "MatrixKernel capacity exceeded")

  let vertexId = newVertexId(kernel.size, 0'u16)
  let vertex = newVertex(vertexId, data)
  kernel.vertices[kernel.size] = some(vertex)
  kernel.size += 1
  kernel.activeVertexCount += 1
  result = vertexId

proc getVertex*[V, E](kernel: MatrixKernel[V, E]; id: VertexId): Option[Vertex[V]] =
  ## Get a vertex by its ID.
  ## Returns Some(vertex) if exists, None otherwise.
  ## O(1) operation.
  if kernel.slotValid(id):
    return some(kernel.vertices[id.id].get())
  none(Vertex[V])

proc removeVertex*[V, E](kernel: var MatrixKernel[V, E]; id: VertexId): bool =
  ## Remove a vertex and all its incident edges.
  ## Note: This creates a "hole" in the matrix - ID stability maintained but space not reclaimed.
  ## O(N) operation.
  if not kernel.slotValid(id):
    return false

  # Remove all outgoing edges
  for j in 0..<kernel.size:
    if kernel.cell(id.id, j).isSome:
      kernel.edgeCount -= 1
    kernel.cell(id.id, j) = none(E)

  # Remove all incoming edges
  for i in 0..<kernel.size:
    if i != id.id and kernel.cell(i, id.id).isSome:
      kernel.edgeCount -= 1
    kernel.cell(i, id.id) = none(E)

  # Mark vertex as removed (but keep slot for ID stability)
  kernel.vertices[id.id] = none(Vertex[V])
  kernel.activeVertexCount -= 1
  result = true

proc addEdge*[V, E](
    kernel: var MatrixKernel[V, E];
    source, target: VertexId;
    data: E
): bool =
  ## Add an edge from source to target with the given data.
  ## Returns false if either endpoint doesn't exist or is removed.
  ## For SimpleGraph: Returns false for self-loops or duplicate edges.
  ## O(1) operation.
  if not kernel.slotValid(source) or not kernel.slotValid(target):
    return false

  # Self-loops only for Pseudo graphs
  if source == target and kernel.graphType != Pseudo:
    return false

  if kernel.cell(source.id, target.id).isSome:
    # A single cell cannot hold parallel edges: under Simple, reject; under
    # Multi/Pseudo, overwrite the existing edge's data without double-counting.
    if kernel.graphType == Simple:
      return false
    kernel.cell(source.id, target.id) = some(data)
    result = true
    return

  kernel.cell(source.id, target.id) = some(data)
  kernel.edgeCount += 1
  result = true

proc hasEdge*[V, E](
    kernel: MatrixKernel[V, E];
    source, target: VertexId
): bool =
  ## Check if an edge exists from source to target.
  ## Returns false if either vertex doesn't exist.
  ## O(1) operation.
  if not kernel.slotValid(source) or not kernel.slotValid(target):
    return false

  result = kernel.cell(source.id, target.id).isSome

proc getEdge*[V, E](
    kernel: MatrixKernel[V, E];
    source, target: VertexId
): Option[E] =
  ## Get the data of an edge from source to target.
  ## Returns None if edge doesn't exist.
  ## O(1) operation.
  if not kernel.slotValid(source) or not kernel.slotValid(target):
    return none(E)

  result = kernel.cell(source.id, target.id)

proc removeEdge*[V, E](
    kernel: var MatrixKernel[V, E];
    source, target: VertexId
): bool =
  ## Remove an edge from source to target.
  ## Returns true if edge was removed, false if not found.
  ## O(1) operation.
  if not kernel.slotValid(source) or not kernel.slotValid(target):
    return false

  if kernel.cell(source.id, target.id).isNone:
    return false

  kernel.cell(source.id, target.id) = none(E)
  kernel.edgeCount -= 1
  result = true

proc neighbors*[V, E](
    kernel: MatrixKernel[V, E];
    id: VertexId
): seq[Edge[E]] =
  ## Get all outgoing edges from a vertex.
  ## Returns empty sequence if vertex doesn't exist.
  ## O(N) operation.
  result = @[]

  if not kernel.slotValid(id):
    return

  for j in 0..<kernel.size:
    if kernel.cell(id.id, j).isSome:
      let edge = newEdge(id, newVertexId(j, 0'u16), kernel.cell(id.id, j).get())
      result.add(edge)

proc inNeighbors*[V, E](
    kernel: MatrixKernel[V, E];
    id: VertexId
): seq[Edge[E]] =
  ## Get all incoming edges to a vertex.
  ## O(N) operation.
  result = @[]

  if not kernel.slotValid(id):
    return

  for i in 0..<kernel.size:
    if kernel.cell(i, id.id).isSome:
      let edge = newEdge(newVertexId(i, 0'u16), id, kernel.cell(i, id.id).get())
      result.add(edge)

proc outNeighbors*[V, E](
    kernel: MatrixKernel[V, E];
    id: VertexId
): seq[Edge[E]] =
  ## Get all outgoing edges from a vertex (alias for neighbors).
  kernel.neighbors(id)

iterator vertices*[V, E](kernel: MatrixKernel[V, E]): Vertex[V] =
  ## Iterate over all vertices in the kernel
  for i in 0..<kernel.size:
    if kernel.vertices[i].isSome:
      yield kernel.vertices[i].get()

iterator edges*[V, E](kernel: MatrixKernel[V, E]): Edge[E] =
  ## Iterate over all edges in the kernel
  for i in 0..<kernel.size:
    for j in 0..<kernel.size:
      if kernel.cell(i, j).isSome:
        let edge = newEdge(newVertexId(i, 0'u16), newVertexId(j, 0'u16),
            kernel.cell(i, j).get())
        yield edge
