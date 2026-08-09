# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# UniGraph — GraphKernel concept
# =============================================================================
#
# Explicit contract for graph storage kernels. A type satisfies
# `GraphKernel[V, E]` when it provides the full vertex/edge/adjacency API
# below; satisfaction is checkable at compile time:
#
#   static: doAssert ListKernel[int, float] is GraphKernel[int, float]
#
# Algorithms written against this contract run unchanged on any kernel;
# kernels trade memory layout and complexity (adjacency list, flat seq,
# CSR, dense matrix) without touching the algorithms.

import std/options
import ./types

type
  GraphKernel*[V, E] = concept k, var mk
    ## `k` is an immutable kernel value, `mk` a mutable one;
    ## `V` is the vertex payload type, `E` the edge payload type.
    # --- size ---
    vertexCount(k) is int
    edgeCount(k) is int
    # --- vertices ---
    addVertex(mk, V) is VertexId
    getVertex(k, VertexId) is Option[Vertex[V]]
    removeVertex(mk, VertexId) is bool
    for vertex in vertices(k):
      vertex is Vertex[V]
    # --- edges ---
    addEdge(mk, VertexId, VertexId, E) is bool
    hasEdge(k, VertexId, VertexId) is bool
    getEdge(k, VertexId, VertexId) is Option[E]
    removeEdge(mk, VertexId, VertexId) is bool
    # --- adjacency ---
    neighbors(k, VertexId) is seq[Edge[E]]

proc maxVertexId*[K](kernel: K): int =
  ## Highest VertexId.id currently in use by `kernel`, or -1 if empty.
  ## GraphKernel exposes no capacity/max-id query, so this is an O(V) scan;
  ## algorithms use it to size a dense array-by-id lookup as an alternative
  ## to `Table[VertexId, _]`, which costs a hash on every access.
  mixin vertices
  result = -1
  for v in kernel.vertices():
    if v.id.id > result:
      result = v.id.id

proc capacityFor*[K](kernel: K, start: VertexId): int =
  ## Array size for every live kernel id. Algorithms validate `start` before
  ## allocating; it remains in the signature to make that call-site intent
  ## explicit without letting a forged id inflate or overflow the allocation.
  discard start
  kernel.maxVertexId() + 1
