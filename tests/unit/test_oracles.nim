# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Oracle checks for robustness: edge cases every kernel must handle the same
## way, and properties that must hold no matter which kernel backs a graph.
## These are the checks a code review can't give you — they run the actual
## code against inputs designed to break it (empty graphs, self-loops,
## out-of-range ids, repeated remove/re-add) and compare kernels against
## each other rather than against a single hand-computed expected value.

import std/[unittest, options, sequtils]
import ../../src/UniGraph/types
import ../../src/UniGraph/kernels/list_kernel
import ../../src/UniGraph/kernels/seq_kernel
import ../../src/UniGraph/kernels/csr_kernel
import ../../src/UniGraph/kernels/matrix_kernel
import ../../src/UniGraph/visitor
import ../../src/UniGraph/algorithms/traversals
import ../../src/UniGraph/algorithms/shortest_path

suite "Robustness - empty graph":
  test "every kernel answers queries on an empty graph without crashing":
    var list = newListKernel[int, float]()
    var sq = newSeqKernel[int, float]()
    var csr = newCsrKernel[int, float]()
    csr.build()
    var matrix = newMatrixKernel[int, float]()

    let bogus = newVertexId(0)
    check list.getVertex(bogus).isNone
    check sq.getVertex(bogus).isNone
    check csr.getVertex(bogus).isNone
    check matrix.getVertex(bogus).isNone

    check list.vertexCount() == 0
    check sq.vertexCount() == 0
    check csr.vertexCount() == 0
    check matrix.vertexCount() == 0

    check list.isConnectedUndirected() == true
    check sq.isConnectedUndirected() == true
    check csr.isConnectedUndirected() == true
    check matrix.isConnectedUndirected() == true

  test "removing from an empty graph returns false, never raises":
    var list = newListKernel[int, float]()
    var sq = newSeqKernel[int, float]()
    var matrix = newMatrixKernel[int, float]()
    let bogus = newVertexId(0)

    check list.removeVertex(bogus) == false
    check sq.removeVertex(bogus) == false
    check matrix.removeVertex(bogus) == false

suite "Robustness - out-of-range and negative VertexId":
  test "negative and past-the-end ids are rejected, not out-of-bounds crashes":
    var kernel = newListKernel[int, float]()
    discard kernel.addVertex(1)

    let negative = newVertexId(-1)
    let tooFar = newVertexId(9999)

    check kernel.getVertex(negative).isNone
    check kernel.getVertex(tooFar).isNone
    check kernel.hasEdge(negative, tooFar) == false
    check kernel.addEdge(negative, tooFar, 1.0) == false

  test "bfs/dfs/dijkstra/reachableVertices don't crash on a start vertex the kernel doesn't have":
    proc weight(edge: Edge[float]): float = edge.data

    var empty = newListKernel[int, float]()
    let bogus = newVertexId(0)

    var v1 = newVisitor[float]()
    empty.bfs(bogus, v1)
    check v1.getVisitOrder().len == 0

    check empty.reachableVertices(bogus).len == 0
    check empty.dijkstra(bogus, weight).distances.len == 1

    var nonEmpty = newSeqKernel[int, float]()
    let a = nonEmpty.addVertex(1)
    let b = nonEmpty.addVertex(2)
    discard nonEmpty.addEdge(a, b, 1.0)
    let outOfRange = newVertexId(99)

    var v2 = newVisitor[float]()
    nonEmpty.bfs(outOfRange, v2)
    check v2.getVisitOrder().len == 0

    for invalid in [newVertexId(-1), newVertexId(high(int))]:
      var visitor = newVisitor[float]()
      nonEmpty.bfs(invalid, visitor)
      check visitor.getVisitOrder().len == 0
      check nonEmpty.bfsIterative(invalid, newVisitor[float]()).len == 0
      check nonEmpty.dfsIterative(invalid, newVisitor[float]()).len == 0
      check nonEmpty.reachableVertices(invalid).len == 0
      check nonEmpty.dijkstra(invalid, weight).distances[invalid] == 0.0

suite "Robustness - SimpleGraph invariants under repeated mutation":
  test "self-loops are rejected on every kernel, every time":
    var list = newListKernel[int, float]()
    var sq = newSeqKernel[int, float]()
    var matrix = newMatrixKernel[int, float]()
    var csr = newCsrKernel[int, float]()

    let a1 = list.addVertex(0)
    let a2 = sq.addVertex(0)
    let a3 = matrix.addVertex(0)
    let a4 = csr.addVertex(0)

    check list.addEdge(a1, a1, 1.0) == false
    check sq.addEdge(a2, a2, 1.0) == false
    check matrix.addEdge(a3, a3, 1.0) == false
    check csr.addEdge(a4, a4, 1.0) == false

  test "duplicate edges are rejected on every kernel":
    var list = newListKernel[int, float]()
    let a = list.addVertex(0)
    let b = list.addVertex(1)
    check list.addEdge(a, b, 1.0) == true
    check list.addEdge(a, b, 2.0) == false # already present
    check list.getEdge(a, b).get() == 1.0 # first write wins, unchanged

  test "remove then re-add a vertex bumps the generation (ID stability)":
    var kernel = newListKernel[int, float]()
    let v1 = kernel.addVertex(10)
    discard kernel.removeVertex(v1)
    let v2 = kernel.addVertex(20)

    # A stale handle to the removed vertex must not resolve to the new one.
    check kernel.getVertex(v1).isNone
    check kernel.getVertex(v2).get().data == 20
    check v1.id == v2.id # slot reused...
    check v1.generation != v2.generation # ...but the generation changed

suite "Robustness - graphType drives edge policy":
  test "Pseudo allows self-loops on every kernel":
    var list = newListKernel[int, float]()
    var sq = newSeqKernel[int, float]()
    var matrix = newMatrixKernel[int, float]()
    var csr = newCsrKernel[int, float]()
    list.graphType = Pseudo
    sq.graphType = Pseudo
    matrix.graphType = Pseudo
    csr.graphType = Pseudo

    let a1 = list.addVertex(0)
    let a2 = sq.addVertex(0)
    let a3 = matrix.addVertex(0)
    let a4 = csr.addVertex(0)

    check list.addEdge(a1, a1, 1.0) == true
    check sq.addEdge(a2, a2, 1.0) == true
    check matrix.addEdge(a3, a3, 1.0) == true
    check csr.addEdge(a4, a4, 1.0) == true

  test "Multi allows parallel edges on list/seq/csr, overwrites on matrix":
    var list = newListKernel[int, float]()
    var sq = newSeqKernel[int, float]()
    var matrix = newMatrixKernel[int, float]()
    var csr = newCsrKernel[int, float]()
    list.graphType = Multi
    sq.graphType = Multi
    matrix.graphType = Multi
    csr.graphType = Multi

    let a1 = list.addVertex(0); let b1 = list.addVertex(1)
    let a2 = sq.addVertex(0); let b2 = sq.addVertex(1)
    let a3 = matrix.addVertex(0); let b3 = matrix.addVertex(1)
    let a4 = csr.addVertex(0); let b4 = csr.addVertex(1)

    check list.addEdge(a1, b1, 1.0) == true
    check list.addEdge(a1, b1, 2.0) == true
    check list.edgeCount() == 2

    check sq.addEdge(a2, b2, 1.0) == true
    check sq.addEdge(a2, b2, 2.0) == true
    check sq.edgeCount() == 2

    check csr.addEdge(a4, b4, 1.0) == true
    check csr.addEdge(a4, b4, 2.0) == true
    check csr.edgeCount() == 2

    check matrix.addEdge(a3, b3, 1.0) == true
    check matrix.addEdge(a3, b3, 2.0) == true # overwrite, not parallel
    check matrix.edgeCount() == 1
    check matrix.getEdge(a3, b3).get() == 2.0

  test "Simple (default) still rejects self-loops and parallel edges":
    var list = newListKernel[int, float]()
    let a = list.addVertex(0)
    let b = list.addVertex(1)
    check list.addEdge(a, a, 1.0) == false
    check list.addEdge(a, b, 1.0) == true
    check list.addEdge(a, b, 2.0) == false
    check list.edgeCount() == 1

suite "Robustness - MatrixKernel capacity boundary":
  test "exactly 256 vertices is accepted, 257th is rejected":
    var kernel = newMatrixKernel[int, float](capacity = 256)
    for i in 0 ..< 256:
      discard kernel.addVertex(i)
    check kernel.vertexCount() == 256

    expect(IndexDefect):
      discard kernel.addVertex(256)

suite "Cross-kernel property - same graph, same answer":
  test "BFS visit order agrees across List/Seq/Csr/Matrix for a random-ish graph":
    # The property under test: which kernel stores the graph must never
    # change what an algorithm concludes about it (kernel-doctrine.md).
    let edgeList = [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4)]

    var list = newListKernel[int, float]()
    var sq = newSeqKernel[int, float]()
    var csr = newCsrKernel[int, float]()
    var matrix = newMatrixKernel[int, float]()

    var listIds, sqIds, csrIds, matrixIds: seq[VertexId]
    for i in 0 .. 4:
      listIds.add list.addVertex(i)
      sqIds.add sq.addVertex(i)
      csrIds.add csr.addVertex(i)
      matrixIds.add matrix.addVertex(i)

    for (u, v) in edgeList:
      discard list.addEdge(listIds[u], listIds[v], 1.0)
      discard sq.addEdge(sqIds[u], sqIds[v], 1.0)
      discard csr.addEdge(csrIds[u], csrIds[v], 1.0)
      discard matrix.addEdge(matrixIds[u], matrixIds[v], 1.0)
    csr.build()

    var visitorList = newVisitor[float]()
    var visitorSeq = newVisitor[float]()
    var visitorCsr = newVisitor[float]()
    var visitorMatrix = newVisitor[float]()

    list.bfs(listIds[0], visitorList)
    sq.bfs(sqIds[0], visitorSeq)
    csr.bfs(csrIds[0], visitorCsr)
    matrix.bfs(matrixIds[0], visitorMatrix)

    let listOrder = visitorList.visitOrder.mapIt(list.getVertex(it).get().data)
    let seqOrder = visitorSeq.visitOrder.mapIt(sq.getVertex(it).get().data)
    let csrOrder = visitorCsr.visitOrder.mapIt(csr.getVertex(it).get().data)
    let matrixOrder = visitorMatrix.visitOrder.mapIt(
        matrix.getVertex(it).get().data)

    check listOrder == seqOrder
    check listOrder == csrOrder
    check listOrder == matrixOrder
