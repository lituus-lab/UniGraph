# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/kernels/csr_kernel.nim
## Compressed Sparse Row (CSR) kernel implementation for static graph analysis
##
## Space Complexity: O(V + E)
## Construction: O(V + E)
## Traversal: O(V + E) with excellent cache locality
## Mutation: Not supported (immutable after construction)
##
## Best for: Large static graphs (social networks, web graphs, road networks)
## Use Case: Build once, traverse many times

import ../types
import std/options, std/algorithm

type
  CsrKernel*[V, E] = object
    ## Compressed Sparse Row implementation for static graphs.
    ## Optimized for traversal operations with cache-local memory access.
    ## Once built, the graph is immutable (no add/remove operations).
    vertices*: seq[Vertex[V]]
    rowOffsets*: seq[int] # CSR row pointers (size V+1)
    colIndices*: seq[VertexId] # Column indices (size E)
    values*: seq[E] # Edge values (size E)
    edgeCount*: int
    isBuilt*: bool # True after build() is called
                     # Temporary storage for edges before build
    tempEdges*: seq[seq[tuple[target: VertexId, data: E]]]
    graphType*: GraphType # Edge policy: Simple rejects self-loops and
                            # parallel edges; Multi allows parallel edges;
                            # Pseudo allows both. Defaults to Simple.

proc newCsrKernel*[V, E](): CsrKernel[V, E] =
  ## Create a new empty CsrKernel
  CsrKernel[V, E](
    vertices: @[],
    rowOffsets: @[],
    colIndices: @[],
    values: @[],
    edgeCount: 0,
    isBuilt: false,
    tempEdges: @[]
  )

proc vertexCount*[V, E](kernel: CsrKernel[V, E]): int {.inline.} =
  ## Return the number of vertices in the kernel
  kernel.vertices.len

proc edgeCount*[V, E](kernel: CsrKernel[V, E]): int {.inline.} =
  ## Return the number of edges in the kernel
  kernel.edgeCount

proc slotValid[V, E](kernel: CsrKernel[V, E], id: VertexId): bool {.inline.} =
  ## Full VertexId validation: bounds and matching generation. CSR never
  ## removes vertices, so comparing against the stored vertex's full id is
  ## what stops a handle with a valid id but wrong generation from creating
  ## edges whose endpoints do not exist.
  id.id >= 0 and id.id < kernel.vertices.len and kernel.vertices[id.id].id == id

proc addVertex*[V, E](kernel: var CsrKernel[V, E], data: V): VertexId =
  ## Add a new vertex with the given data.
  ## Only valid before build() is called.
  ## Returns the VertexId for the new vertex.
  if kernel.isBuilt:
    raise newException(ValueError, "CsrKernel is immutable after build()")

  let vertexId = newVertexId(kernel.vertices.len, 0'u16)
  let vertex = newVertex(vertexId, data)
  kernel.vertices.add(vertex)
  kernel.tempEdges.add(@[]) # Add empty edge list for this vertex
  result = vertexId

proc getVertex*[V, E](kernel: CsrKernel[V, E], id: VertexId): Option[Vertex[V]] =
  ## Get a vertex by its ID.
  ## Returns Some(vertex) if exists, None otherwise.
  if kernel.slotValid(id):
    return some(kernel.vertices[id.id])
  none(Vertex[V])

proc removeVertex*[V, E](kernel: var CsrKernel[V, E], id: VertexId): bool =
  ## Remove a vertex - NOT SUPPORTED in CSR.
  ## CSR is optimized for static graphs: mutation requires a rebuild, so this
  ## always returns false rather than raising — generic algorithms that swap
  ## kernels rely on the GraphKernel `bool` contract, not an exception.
  false

proc addEdge*[V, E](
    kernel: var CsrKernel[V, E],
    source, target: VertexId,
    data: E
): bool =
  ## Add an edge from source to target with the given data.
  ## Only valid before build() is called.
  ## Returns false if either endpoint doesn't exist.
  if kernel.isBuilt:
    return false

  # Validate both endpoints by full id (bounds + generation) before indexing
  # tempEdges.
  if not kernel.slotValid(source) or not kernel.slotValid(target):
    return false

  # Self-loops only for Pseudo graphs
  if source == target and kernel.graphType != Pseudo:
    return false

  # Parallel edges only for non-Simple graphs
  if kernel.graphType == Simple:
    for edge in kernel.tempEdges[source.id]:
      if edge.target == target:
        return false

  kernel.tempEdges[source.id].add((target: target, data: data))
  kernel.edgeCount += 1
  result = true

proc hasEdge*[V, E](
    kernel: CsrKernel[V, E],
    source, target: VertexId
): bool =
  ## Check if an edge exists from source to target.
  ## Uses binary search within the row - O(log(degree)).
  if not kernel.slotValid(source) or not kernel.slotValid(target):
    return false

  if not kernel.isBuilt:
    for (t, _) in kernel.tempEdges[source.id]:
      if t == target:
        return true
    return false

  let rowStart = kernel.rowOffsets[source.id]
  let rowEnd = kernel.rowOffsets[source.id + 1]

  # Binary search for target in sorted column indices
  var low = rowStart
  var high = rowEnd - 1

  while low <= high:
    let mid = low + (high - low) div 2
    if kernel.colIndices[mid].id == target.id:
      return true
    elif kernel.colIndices[mid].id < target.id:
      low = mid + 1
    else:
      high = mid - 1

  result = false

proc getEdge*[V, E](
    kernel: CsrKernel[V, E],
    source, target: VertexId
): Option[E] =
  ## Get the data of an edge from source to target.
  ## Uses binary search within the row - O(log(degree)).
  if not kernel.slotValid(source) or not kernel.slotValid(target):
    return none(E)

  if not kernel.isBuilt:
    for (t, data) in kernel.tempEdges[source.id]:
      if t == target:
        return some(data)
    return none(E)

  let rowStart = kernel.rowOffsets[source.id]
  let rowEnd = kernel.rowOffsets[source.id + 1]

  # Binary search for target in sorted column indices
  var low = rowStart
  var high = rowEnd - 1

  while low <= high:
    let mid = low + (high - low) div 2
    if kernel.colIndices[mid].id == target.id:
      return some(kernel.values[mid])
    elif kernel.colIndices[mid].id < target.id:
      low = mid + 1
    else:
      high = mid - 1

  result = none(E)

proc removeEdge*[V, E](
    kernel: var CsrKernel[V, E],
    source, target: VertexId
): bool =
  ## Remove an edge - NOT SUPPORTED in CSR.
  ## Same reasoning as removeVertex: always returns false, never raises.
  false

proc build*[V, E](kernel: var CsrKernel[V, E]) =
  ## Finalize the CSR structure for optimal traversal.
  ## Sorts column indices within each row for binary search.
  ## After calling build(), the kernel becomes immutable.
  if kernel.isBuilt:
    return

  # Calculate row offsets
  kernel.rowOffsets = newSeq[int](kernel.vertices.len + 1)
  kernel.rowOffsets[0] = 0

  for i in 0..<kernel.vertices.len:
    kernel.rowOffsets[i + 1] = kernel.rowOffsets[i] + kernel.tempEdges[i].len

  # Allocate column indices and values arrays
  kernel.colIndices = newSeq[VertexId](kernel.edgeCount)
  kernel.values = newSeq[E](kernel.edgeCount)

  # Copy edges from temporary storage to CSR format
  var offset = 0
  for i in 0..<kernel.vertices.len:
    for edge in kernel.tempEdges[i]:
      kernel.colIndices[offset] = edge.target
      kernel.values[offset] = edge.data
      offset += 1

  # Sort edges within each row by column index for binary search
  for i in 0..<kernel.vertices.len:
    let rowStart = kernel.rowOffsets[i]
    let rowEnd = kernel.rowOffsets[i + 1]

    if rowEnd > rowStart:
      # Sort column indices and values together
      var edges: seq[tuple[col: VertexId, val: E]] = @[]
      for j in rowStart..<rowEnd:
        edges.add((kernel.colIndices[j], kernel.values[j]))

      edges.sort(proc (a, b: tuple[col: VertexId, val: E]): int =
        cmp(a.col.id, b.col.id)
      )

      for j in 0..<edges.len:
        kernel.colIndices[rowStart + j] = edges[j].col
        kernel.values[rowStart + j] = edges[j].val

  # Clear temporary storage
  kernel.tempEdges = @[]
  kernel.isBuilt = true

proc neighbors*[V, E](
    kernel: CsrKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  ## Get all outgoing edges from a vertex.
  ## O(degree) with cache-local memory access.
  result = @[]

  if not kernel.slotValid(id):
    return

  if not kernel.isBuilt:
    # before build(), edges still live in the staging area
    for (target, data) in kernel.tempEdges[id.id]:
      result.add(newEdge(id, target, data))
    return

  let rowStart = kernel.rowOffsets[id.id]
  let rowEnd = kernel.rowOffsets[id.id + 1]

  for i in rowStart..<rowEnd:
    let edge = newEdge(id, kernel.colIndices[i], kernel.values[i])
    result.add(edge)

proc inNeighbors*[V, E](
    kernel: CsrKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  ## Get all incoming edges to a vertex.
  ## O(E) operation - requires scanning all edges.
  result = @[]

  if not kernel.slotValid(id):
    return

  if not kernel.isBuilt:
    # Before build(), rowOffsets is empty: scan the staging area for edges
    # whose destination matches id, mirroring neighbors()/edges().
    for sourceId in 0..<kernel.tempEdges.len:
      for (target, data) in kernel.tempEdges[sourceId]:
        if target == id:
          result.add(newEdge(newVertexId(sourceId, 0'u16), target, data))
    return

  for sourceId in 0..<kernel.vertices.len:
    let rowStart = kernel.rowOffsets[sourceId]
    let rowEnd = kernel.rowOffsets[sourceId + 1]

    for i in rowStart..<rowEnd:
      if kernel.colIndices[i].id == id.id:
        let edge = newEdge(newVertexId(sourceId, 0'u16), id, kernel.values[i])
        result.add(edge)

proc outNeighbors*[V, E](
    kernel: CsrKernel[V, E],
    id: VertexId
): seq[Edge[E]] =
  ## Get all outgoing edges from a vertex (alias for neighbors).
  kernel.neighbors(id)

iterator vertices*[V, E](kernel: CsrKernel[V, E]): Vertex[V] =
  ## Iterate over all vertices in the kernel
  for vertex in kernel.vertices:
    yield vertex

iterator edges*[V, E](kernel: CsrKernel[V, E]): Edge[E] =
  ## Iterate over all edges in the kernel, O(V+E): each vertex's row is
  ## visited once and its edges read off directly from rowOffsets, instead
  ## of re-scanning every row for every single edge (O(V times E)).
  if not kernel.isBuilt:
    for i in 0 ..< kernel.tempEdges.len:
      for (target, data) in kernel.tempEdges[i]:
        yield newEdge(newVertexId(i, 0'u16), target, data)
  else:
    for sourceId in 0..<kernel.vertices.len:
      for i in kernel.rowOffsets[sourceId]..<kernel.rowOffsets[sourceId + 1]:
        yield newEdge(newVertexId(sourceId, 0'u16), kernel.colIndices[i],
            kernel.values[i])
