# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## tests/unit/test_traversals.nim
## Unit tests for User Story 3: Visitor pattern and traversal algorithms
## Tests BFS, DFS with Visitor tracing

import unittest, options
import ../../src/UniGraph/types
import ../../src/UniGraph/kernels/list_kernel
import ../../src/UniGraph/visitor
import ../../src/UniGraph/algorithms/traversals

suite "Visitor - Basic Functionality":
  test "Create and use visitor":
    var visitor = newVisitor[float]()
    let v1 = newVertexId(0, 0'u16)

    visitor.onDiscover(v1, 0)

    check visitor.currentStep == 1
    check visitor.visitOrder.len == 1
    check visitor.trace.len == 1

  test "Visitor captures all events":
    var visitor = newVisitor[float]()
    let v1 = newVertexId(0, 0'u16)
    let v2 = newVertexId(1, 0'u16)

    visitor.onDiscover(v1, 0)
    visitor.onEdge(v1, v2, 1.0)
    visitor.onDiscover(v2, 1)
    visitor.onFinish(v1)

    check visitor.discovered.len == 2
    check visitor.finished.len == 1
    check visitor.edgeTraversals.len == 1
    check visitor.trace.len == 4

  test "Clear visitor state":
    var visitor = newVisitor[float]()
    let v1 = newVertexId(0, 0'u16)

    visitor.onDiscover(v1, 0)
    check visitor.currentStep == 1

    visitor.clear()
    check visitor.currentStep == 0
    check visitor.trace.len == 0
    check visitor.edgeClassifications.len == 0
    check visitor.discoveryTime.len == 0
    check visitor.finishTime.len == 0

suite "Edge Classification":
  test "Tree edge: target undiscovered":
    var visitor = newVisitor[float]()
    let v0 = newVertexId(0, 0'u16)
    let v1 = newVertexId(1, 0'u16)

    visitor.onDiscover(v0, 0)
    visitor.onEdge(v0, v1, 1.0)

    check visitor.edgeClassifications[^1].kind == ekTree
    check visitor.discoveryTime[v0] == 0

  test "Back edge: target discovered but not finished":
    var visitor = newVisitor[float]()
    let vA = newVertexId(0, 0'u16)
    let vB = newVertexId(1, 0'u16)

    visitor.onDiscover(vA, 0)
    visitor.onDiscover(vB, 1) # vB is a still-open descendant of vA
    visitor.onEdge(vB, vA, 1.0) # edge back to an ancestor still on the stack

    check visitor.edgeClassifications[^1].kind == ekBack

  test "Forward edge: target finished, discovered after source":
    var visitor = newVisitor[float]()
    let v0 = newVertexId(0, 0'u16)
    let v1 = newVertexId(1, 0'u16)

    visitor.onDiscover(v0, 0)
    visitor.onEdge(v0, v1, 1.0) # first traversal: v1 undiscovered -> tree
    visitor.onDiscover(v1, 1)
    visitor.onFinish(v1)
    visitor.onEdge(v0, v1, 1.0) # shortcut to the now-finished descendant

    check visitor.edgeClassifications[^1].kind == ekForward
    check visitor.discoveryTime[v1] > visitor.discoveryTime[v0]

  test "Cross edge: target finished, discovered before source, no ancestry":
    var visitor = newVisitor[float]()
    let vX = newVertexId(0, 0'u16)
    let vY = newVertexId(1, 0'u16)

    visitor.onDiscover(vX, 0)
    visitor.onFinish(vX) # vX's whole subtree is done before vY starts
    visitor.onDiscover(vY, 1)
    visitor.onEdge(vY, vX, 1.0)

    check visitor.edgeClassifications[^1].kind == ekCross
    check visitor.discoveryTime[vX] < visitor.discoveryTime[vY]

  test "Discovery and finish share one monotonic clock":
    var visitor = newVisitor[float]()
    let v0 = newVertexId(0, 0'u16)
    let v1 = newVertexId(1, 0'u16)

    visitor.onDiscover(v0, 0)
    visitor.onDiscover(v1, 1)
    visitor.onFinish(v1)
    visitor.onFinish(v0)

    check visitor.discoveryTime[v0] == 0
    check visitor.discoveryTime[v1] == 1
    check visitor.finishTime[v1] == 2
    check visitor.finishTime[v0] == 3

suite "BFS - Breadth-First Search":
  test "BFS visits all reachable vertices":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)
    let v3 = kernel.addVertex(3)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v0, v2, 2.0)
    discard kernel.addEdge(v1, v3, 3.0)

    var visitor = newVisitor[float]()
    kernel.bfs(v0, visitor)

    check visitor.discovered.len == 4
    check visitor.visitOrder.len == 4

  test "BFS visit order is correct":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v0, v2, 2.0)

    var visitor = newVisitor[float]()
    kernel.bfs(v0, visitor)

    # v0 should be first
    check visitor.visitOrder[0] == v0
    # v1 and v2 should be visited (order may vary)
    check v1 in visitor.visitOrder
    check v2 in visitor.visitOrder

  test "BFS captures edge traversals":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)

    discard kernel.addEdge(v0, v1, 1.0)

    var visitor = newVisitor[float]()
    kernel.bfs(v0, visitor)

    check visitor.edgeTraversals.len >= 1

suite "DFS - Depth-First Search":
  test "DFS visits all reachable vertices":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)
    let v3 = kernel.addVertex(3)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v2, 2.0)
    discard kernel.addEdge(v2, v3, 3.0)

    var visitor = newVisitor[float]()
    kernel.dfs(v0, visitor)

    check visitor.discovered.len == 4
    check visitor.finished.len == 4 # All vertices finished in DFS

  test "DFS finish order is correct":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)

    discard kernel.addEdge(v0, v1, 1.0)

    var visitor = newVisitor[float]()
    kernel.dfs(v0, visitor)

    # v1 should finish before v0 (LIFO)
    check visitor.finished[0] == v1
    check visitor.finished[^1] == v0

  test "DFS captures edge traversals":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)

    discard kernel.addEdge(v0, v1, 1.0)

    var visitor = newVisitor[float]()
    kernel.dfs(v0, visitor)

    check visitor.edgeTraversals.len >= 1

suite "Iterative Traversals":
  test "BFS iterative returns correct order":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v0, v2, 2.0)

    var visitor = newVisitor[float]()
    let order = kernel.bfsIterative(v0, visitor)
    check order.len == 3
    check v0 in order
    check v1 in order
    check v2 in order

  test "DFS iterative returns correct order":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v2, 2.0)

    var visitor = newVisitor[float]()
    let order = kernel.dfsIterative(v0, visitor)
    check order.len == 3
    check v0 in order
    check v1 in order
    check v2 in order

  test "DFS iterative emits finish events, like the recursive version":
    # Regression check: dfsIterative once never called onFinish at all.
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v2, 2.0)

    var visitor = newVisitor[float]()
    discard kernel.dfsIterative(v0, visitor)

    check visitor.finished.len == 3
    # Leaf finishes before its ancestors: v2 before v1 before v0.
    check visitor.finished[0] == v2
    check visitor.finished[^1] == v0

suite "Utility Functions":
  test "Reachable vertices":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)
    let v3 = kernel.addVertex(3)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v2, 2.0)
    # v3 is not connected

    let reachable = kernel.reachableVertices(v0)
    check reachable.len == 3
    check v0 in reachable
    check v1 in reachable
    check v2 in reachable
    check v3 notin reachable

  test "Is connected - true":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    # Create a fully connected undirected-like graph (bidirectional edges)
    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v0, 1.0)
    discard kernel.addEdge(v0, v2, 2.0)
    discard kernel.addEdge(v2, v0, 2.0)

    check kernel.isConnectedUndirected() == true

  test "Is connected - false":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    # v2 is not connected

    check kernel.isConnectedUndirected() == false

  test "Is connected - empty graph":
    let kernel = newListKernel[int, float]()
    check kernel.isConnectedUndirected() == true

suite "Pedagogical Tracing - Integration":
  test "Full BFS trace output":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v0, v2, 2.0)

    var visitor = newVisitor[float]()
    kernel.bfs(v0, visitor)

    # Verify the trace is actually interpolated, not a literal template
    # string (regression check: onDiscover/onEdge once emitted the raw
    # "{visitor.currentStep}"-style text unexpanded).
    check visitor.trace.len > 0
    check visitor.trace[0] == "Step 1: Discovered vertex " & $v0.id & " (order: 0, time: 0)"
    for line in visitor.trace:
      check '{' notin line

  test "Full DFS trace output":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v2, 2.0)

    var visitor = newVisitor[float]()
    kernel.dfs(v0, visitor)

    # Verify trace has discovery and finish events, properly interpolated
    check visitor.trace.len > 0
    check visitor.trace[0] == "Step 1: Discovered vertex " & $v0.id & " (order: 0, time: 0)"
    for line in visitor.trace:
      check '{' notin line
