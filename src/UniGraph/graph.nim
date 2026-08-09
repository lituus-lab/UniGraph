# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/graph.nim
## High-level Graph wrapper with immutable operations
##
## This module provides the user-facing Graph API that wraps a kernel and
## enforces immutability (returns new instances on mutation). It is generic
## over the kernel type K (ListKernel, SeqKernel, ...), so there is exactly
## one definition of the wrapper, not one copy per kernel. Uses Nim's
## ARC/ORC for efficient copy-on-write semantics.

import types, kernels/list_kernel
import std/options
import contracts

proc userEdgeCount[K](kernel: K; direction: Direction): int =
  ## Count logical edges; undirected kernels store one arc in each direction.
  mixin edges
  for edge in kernel.edges():
    if direction == Directed or edge.source.id <= edge.target.id:
      inc result

proc kernelVertexCount[K](kernel: K): int =
  mixin vertexCount
  kernel.vertexCount

# ============================================================================
# Immutable Graph Wrapper (generic over any kernel K)
# ============================================================================

type
  ImmutableGraph*[K, V, E] = object
    ## Immutable graph wrapper - all operations return new instances.
    ## Uses ARC/ORC for efficient memory management.
    kernel*: K
    vertexCount*: int
    edgeCount*: int
    direction*: Direction
    graphType*: GraphType

proc newImmutableGraph*[K, V, E](
    kernel: K;
    direction: Direction = Directed;
    graphType: GraphType = Simple
): ImmutableGraph[K, V, E] {.contractual.} =
  ## Create a new empty immutable graph over the given kernel instance.
  ensure:
    result.vertexCount == kernelVertexCount(result.kernel) and
        result.edgeCount == userEdgeCount(result.kernel, result.direction)
  body:
    result = ImmutableGraph[K, V, E](
      kernel: kernel,
      vertexCount: kernelVertexCount(kernel),
      edgeCount: userEdgeCount(kernel, direction),
      direction: direction,
      graphType: graphType
    )
    result.kernel.graphType = graphType

proc newImmutableGraph*[V, E](
    direction: Direction = Directed;
    graphType: GraphType = Simple
): ImmutableGraph[ListKernel[V, E], V, E] =
  ## Convenience constructor defaulting to ListKernel, the common case.
  newImmutableGraph[ListKernel[V, E], V, E](newListKernel[V, E](), direction,
      graphType)

proc addVertex*[K, V, E](
    graph: ImmutableGraph[K, V, E];
    data: V
): tuple[graph: ImmutableGraph[K, V, E]; id: VertexId] {.contractual.} =
  ## Add a vertex and return a NEW graph instance plus its VertexId
  ## (immutability). The id is needed to call addEdge/removeVertex next;
  ## without it, chaining would require reaching into `graph.kernel`.
  ## Original graph remains unchanged.
  ensure:
    result.graph.vertexCount == graph.vertexCount + 1
  body:
    var newGraph = graph # ARC/ORC handles efficient copying
    let vertexId = newGraph.kernel.addVertex(data)
    newGraph.vertexCount += 1
    result = (newGraph, vertexId)

proc getVertex*[K, V, E](
    graph: ImmutableGraph[K, V, E];
    id: VertexId
): Option[Vertex[V]] =
  ## Get a vertex by ID
  graph.kernel.getVertex(id)

proc removeVertex*[K, V, E](
    graph: ImmutableGraph[K, V, E];
    id: VertexId
): ImmutableGraph[K, V, E] {.contractual.} =
  ## Remove a vertex and return a NEW graph instance (immutability).
  ## ID Stability: Other vertex IDs remain valid.
  ## Original graph remains unchanged.
  ensure:
    # Either id existed and vertexCount dropped by exactly 1, or it didn't
    # and nothing changed -- kernel.removeVertex never partially succeeds.
    result.vertexCount == graph.vertexCount or
        result.vertexCount == graph.vertexCount - 1
  body:
    result = graph
    let edgesBefore = result.edgeCount
    if result.kernel.removeVertex(id):
      result.vertexCount -= 1
      result.edgeCount = userEdgeCount(result.kernel, result.direction)
      doAssert result.edgeCount <= edgesBefore

proc addEdge*[K, V, E](
    graph: ImmutableGraph[K, V, E];
    source, target: VertexId;
    data: E
): ImmutableGraph[K, V, E] {.contractual.} =
  ## Add an edge and return a NEW graph instance (immutability).
  ## Returns the new graph (edge may be rejected for SimpleGraph).
  ensure:
    result.edgeCount == graph.edgeCount or
        result.edgeCount == graph.edgeCount + 1
  body:
    result = graph
    let edgesBefore = result.kernel.edgeCount
    if result.kernel.addEdge(source, target, data):
      if result.direction == Undirected and source != target:
        discard result.kernel.addEdge(target, source, data)
      if result.kernel.edgeCount > edgesBefore:
        result.edgeCount += 1

proc hasEdge*[K, V, E](
    graph: ImmutableGraph[K, V, E];
    source, target: VertexId
): bool =
  ## Check if an edge exists
  graph.kernel.hasEdge(source, target)

proc getEdge*[K, V, E](
    graph: ImmutableGraph[K, V, E];
    source, target: VertexId
): Option[E] =
  ## Get edge data
  graph.kernel.getEdge(source, target)

proc vertexCount*[K, V, E](
    graph: ImmutableGraph[K, V, E]
): int =
  ## Get the number of vertices
  graph.vertexCount

proc edgeCount*[K, V, E](
    graph: ImmutableGraph[K, V, E]
): int =
  ## Get the number of edges
  graph.edgeCount

# ============================================================================
# Mutable Graph (escape hatch for performance, generic over any kernel K)
# ============================================================================

type
  MutableGraph*[K, V, E] = ref object
    ## Mutable graph for performance-critical code.
    ## Use sparingly - breaks immutability guarantee.
    kernel*: K
    vertexCount*: int
    edgeCount*: int
    direction*: Direction
    graphType*: GraphType

proc newMutableGraph*[K, V, E](
    kernel: K;
    direction: Direction = Directed;
    graphType: GraphType = Simple
): MutableGraph[K, V, E] {.contractual.} =
  ## Create a new mutable graph over the given kernel instance.
  ensure:
    (not result.isNil) and
        (result.vertexCount == kernelVertexCount(result.kernel)) and
        (result.edgeCount == userEdgeCount(result.kernel, result.direction))
  body:
    result = MutableGraph[K, V, E](
      kernel: kernel,
      vertexCount: kernelVertexCount(kernel),
      edgeCount: userEdgeCount(kernel, direction),
      direction: direction,
      graphType: graphType
    )
    result.kernel.graphType = graphType

proc newMutableGraph*[V, E](
    direction: Direction = Directed;
    graphType: GraphType = Simple
): MutableGraph[ListKernel[V, E], V, E] =
  ## Convenience constructor defaulting to ListKernel, the common case.
  newMutableGraph[ListKernel[V, E], V, E](newListKernel[V, E](), direction,
      graphType)

proc addVertex*[K, V, E](
    graph: MutableGraph[K, V, E];
    data: V
): VertexId {.contractual.} =
  ## Add a vertex in-place (mutable)
  require:
    not graph.isNil
  ensure:
    graph.vertexCount == graph.kernel.vertexCount and
        graph.getVertex(result).isSome
  body:
    result = graph.kernel.addVertex(data)
    graph.vertexCount += 1

proc getVertex*[K, V, E](
    graph: MutableGraph[K, V, E];
    id: VertexId
): Option[Vertex[V]] =
  ## Get a vertex by ID
  graph.kernel.getVertex(id)

proc removeVertex*[K, V, E](
    graph: MutableGraph[K, V, E];
    id: VertexId
): bool {.contractual.} =
  ## Remove a vertex in-place (mutable)
  require:
    not graph.isNil
  ensure:
    graph.vertexCount == graph.kernel.vertexCount
  body:
    let edgesBefore = graph.edgeCount
    if graph.kernel.removeVertex(id):
      graph.vertexCount -= 1
      graph.edgeCount = userEdgeCount(graph.kernel, graph.direction)
      doAssert graph.edgeCount <= edgesBefore
      result = true
    else:
      result = false

proc addEdge*[K, V, E](
    graph: MutableGraph[K, V, E];
    source, target: VertexId;
    data: E
): bool {.contractual.} =
  ## Add an edge in-place (mutable)
  require:
    not graph.isNil
  ensure:
    not result or graph.hasEdge(source, target)
  body:
    let edgesBefore = graph.kernel.edgeCount
    if graph.kernel.addEdge(source, target, data):
      if graph.direction == Undirected and source != target:
        discard graph.kernel.addEdge(target, source, data)
      if graph.kernel.edgeCount > edgesBefore:
        graph.edgeCount += 1
      result = true
    else:
      result = false

proc hasEdge*[K, V, E](
    graph: MutableGraph[K, V, E];
    source, target: VertexId
): bool =
  ## Check if an edge exists
  graph.kernel.hasEdge(source, target)

proc getEdge*[K, V, E](
    graph: MutableGraph[K, V, E];
    source, target: VertexId
): Option[E] =
  ## Get edge data
  graph.kernel.getEdge(source, target)

proc removeEdge*[K, V, E](
    graph: MutableGraph[K, V, E]; source, target: VertexId
): bool {.contractual.} =
  ## Remove one logical edge in-place.
  require:
    not graph.isNil
  ensure:
    graph.edgeCount >= 0
  body:
    if graph.kernel.removeEdge(source, target):
      if graph.direction == Undirected and source != target:
        discard graph.kernel.removeEdge(target, source)
      dec graph.edgeCount
      result = true
