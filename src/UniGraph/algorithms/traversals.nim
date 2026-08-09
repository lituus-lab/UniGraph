# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import ../types, ../visitor, ../kernel_concept
import ../kernels/list_kernel, ../kernels/seq_kernel, ../kernels/csr_kernel,
    ../kernels/matrix_kernel
import std/[sequtils, deques, options]

# ============================================================================
# Breadth-First Search (BFS)
# ============================================================================

proc bfs*[K; E](
    kernel: K;
    start: VertexId;
    visitor: Visitor[E]
) =
  ## Perform BFS traversal starting from the given vertex.
  if kernel.getVertex(start).isNone:
    return
  # visited is a dense array-by-id, not Table[VertexId, bool]: a hash table
  # costs a hash on every access, an array a direct index -- see
  # maxVertexId's doc comment in kernel_concept.nim.
  var queue = initDeque[VertexId]()
  queue.addLast(start)
  var visited = newSeq[bool](kernel.capacityFor(start))
  var order = 0

  visitor.onDiscover(start, order)
  visited[start.id] = true

  while queue.len > 0:
    let current = queue.popFirst()

    for edge in kernel.neighbors(current):
      visitor.onEdge(current, edge.target, edge.data)

      if not visited[edge.target.id]:
        visited[edge.target.id] = true
        queue.addLast(edge.target)
        order += 1
        visitor.onDiscover(edge.target, order)

# ============================================================================
# Depth-First Search (DFS)
# ============================================================================

proc dfsVisit*[K; E](
    kernel: K;
    current: VertexId;
    visited: var seq[bool];
    visitor: Visitor[E];
    order: var int
) =
  ## DFS helper using explicit frames to avoid native-stack exhaustion.
  type Frame = tuple[vertex: VertexId; nextNeighbor: int; edges: seq[Edge[E]]]
  visited[current.id] = true
  visitor.onDiscover(current, order)
  order += 1
  var stack: seq[Frame] = @[(current, 0, toSeq(kernel.neighbors(current)))]
  while stack.len > 0:
    let top = stack.high
    if stack[top].nextNeighbor >= stack[top].edges.len:
      visitor.onFinish(stack[top].vertex)
      discard stack.pop()
      continue
    let edge = stack[top].edges[stack[top].nextNeighbor]
    inc stack[top].nextNeighbor
    visitor.onEdge(stack[top].vertex, edge.target, edge.data)
    if not visited[edge.target.id]:
      visited[edge.target.id] = true
      visitor.onDiscover(edge.target, order)
      inc order
      stack.add((edge.target, 0, toSeq(kernel.neighbors(edge.target))))

proc dfs*[K; E](
    kernel: K;
    start: VertexId;
    visitor: Visitor[E]
) =
  ## Perform DFS traversal starting from the given vertex.
  if kernel.getVertex(start).isNone:
    return
  var visited = newSeq[bool](kernel.capacityFor(start))
  var order = 0
  dfsVisit(kernel, start, visited, visitor, order)

# ============================================================================
# Iterative Traversal (non-recursive)
# ============================================================================

proc bfsIterative*[K; E](
    kernel: K;
    start: VertexId;
    visitor: Visitor[E]
): seq[VertexId] =
  ## Perform BFS iteratively and return visit order.
  result = @[]

  if kernel.getVertex(start).isNone:
    return

  var queue = initDeque[VertexId]()
  queue.addLast(start)
  var visited = newSeq[bool](kernel.capacityFor(start))
  var order = 0

  visitor.onDiscover(start, order)

  visited[start.id] = true
  result.add(start)

  while queue.len > 0:
    let current = queue.popFirst()

    for edge in kernel.neighbors(current):
      visitor.onEdge(current, edge.target, edge.data)

      if not visited[edge.target.id]:
        visited[edge.target.id] = true
        queue.addLast(edge.target)
        order += 1
        result.add(edge.target)
        visitor.onDiscover(edge.target, order)

proc dfsIterative*[K; E](
    kernel: K;
    start: VertexId;
    visitor: Visitor[E]
): seq[VertexId] =
  ## Perform DFS iteratively and return visit order.
  ## Uses explicit enter/exit stack frames so `onFinish` fires for a vertex
  ## once every descendant has been processed, same as the recursive `dfs`.
  result = @[]

  if kernel.getVertex(start).isNone:
    return

  var stack = @[(start, false)] # (vertex, isExitFrame)
  var visited = newSeq[bool](kernel.capacityFor(start))
  var order = 0

  while stack.len > 0:
    let (current, isExit) = stack.pop()

    if isExit:
      visitor.onFinish(current)
      continue

    if visited[current.id]:
      continue

    visited[current.id] = true
    result.add(current)
    visitor.onDiscover(current, order)
    order += 1

    # Push the exit frame before any neighbor: LIFO order pops descendants
    # first, so this vertex only finishes after they all do.
    stack.add((current, true))

    let neighbors = toSeq(kernel.neighbors(current))
    for i in countdown(neighbors.len - 1, 0):
      let edge = neighbors[i]
      visitor.onEdge(current, edge.target, edge.data)

      if not visited[edge.target.id]:
        stack.add((edge.target, false))

# ============================================================================
# Utility Functions
# ============================================================================

proc reachableVertices*[K](
    kernel: K;
    start: VertexId
): seq[VertexId] =
  ## Get all vertices reachable from the start vertex.
  if kernel.getVertex(start).isNone:
    return

  result = @[start]

  var queue = initDeque[VertexId]()
  queue.addLast(start)
  var visited = newSeq[bool](kernel.capacityFor(start))
  visited[start.id] = true

  while queue.len > 0:
    let current = queue.popFirst()

    for edge in kernel.neighbors(current):
      if not visited[edge.target.id]:
        visited[edge.target.id] = true
        queue.addLast(edge.target)
        result.add(edge.target)

proc isConnectedUndirected*[K](kernel: K): bool =
  ## Check whether an undirected graph is connected.
  let vertices = toSeq(kernel.vertices())
  if vertices.len == 0:
    return true

  let startVertex = vertices[0].id
  let reachable = kernel.reachableVertices(startVertex)

  result = reachable.len == vertices.len
