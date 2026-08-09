# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## tests/unit/test_algorithms.nim
## Unit tests for advanced algorithms
## Compatible with Nim 2.2

import unittest, std/tables, std/sequtils, std/sets
import ../../src/UniGraph/types
import ../../src/UniGraph/kernels/list_kernel
import ../../src/UniGraph/algorithms/shortest_path
import ../../src/UniGraph/algorithms/mst
import ../../src/UniGraph/algorithms/scc
import ../../src/UniGraph/algorithms/tsp
import ../../src/UniGraph/algorithms/traversals
import ../../src/UniGraph/visitor
import ../../src/UniGraph/graph

suite "Dijkstra - Shortest Path":
  test "Computes shortest paths":
    var graph = newImmutableGraph[int, float](Directed)
    let v0 = newVertexId(0)
    let v1 = newVertexId(1)
    let v2 = newVertexId(2)

    (graph, _) = graph.addVertex(0) # v0
    (graph, _) = graph.addVertex(1) # v1
    (graph, _) = graph.addVertex(2) # v2

    graph = graph.addEdge(v0, v1, 1.0)
    graph = graph.addEdge(v1, v2, 2.0)
    graph = graph.addEdge(v0, v2, 10.0)

    let weightProc = proc(e: Edge[float]): float = e.data
    let (dist, parents) = dijkstra(graph.kernel, v0, weightProc)

    check dist[v0] == 0.0
    check dist[v1] == 1.0
    check dist[v2] == 3.0
    check parents[v2] == v1

suite "Prim - MST":
  test "Creates spanning tree":
    var graph = newImmutableGraph[int, float](Undirected)
    let v0 = newVertexId(0)
    let v1 = newVertexId(1)
    let v2 = newVertexId(2)

    (graph, _) = graph.addVertex(0)
    (graph, _) = graph.addVertex(1)
    (graph, _) = graph.addVertex(2)

    graph = graph.addEdge(v0, v1, 1.0)
    graph = graph.addEdge(v1, v2, 2.0)

    let weightProc = proc(e: Edge[float]): float = e.data
    let mst = prim(graph.kernel, weightProc)

    # MST should have V-1 edges (2 edges for 3 vertices)
    check mst.len == 2

  test "Returns a spanning forest for a disconnected graph":
    var graph = newImmutableGraph[int, float](Undirected)
    let v0 = newVertexId(0)
    let v1 = newVertexId(1)
    let v2 = newVertexId(2)
    let v3 = newVertexId(3)

    (graph, _) = graph.addVertex(0)
    (graph, _) = graph.addVertex(1)
    (graph, _) = graph.addVertex(2)
    (graph, _) = graph.addVertex(3)

    # Two disconnected components: {0,1} and {2,3}.
    graph = graph.addEdge(v0, v1, 1.0)
    graph = graph.addEdge(v2, v3, 2.0)

    let weightProc = proc(e: Edge[float]): float = e.data
    let forest = prim(graph.kernel, weightProc)

    # A spanning forest of 4 vertices in 2 components has V - c = 2 edges.
    # The old prim only grew the start component and returned 1 edge.
    check forest.len == 2

suite "Kruskal - MST":
  test "Creates spanning tree":
    var graph = newImmutableGraph[int, float](Undirected)
    let v0 = newVertexId(0)
    let v1 = newVertexId(1)
    let v2 = newVertexId(2)

    (graph, _) = graph.addVertex(0)
    (graph, _) = graph.addVertex(1)
    (graph, _) = graph.addVertex(2)

    graph = graph.addEdge(v0, v1, 1.0)
    graph = graph.addEdge(v1, v2, 2.0)

    let weightProc = proc(e: Edge[float]): float = e.data
    let mst = kruskal(graph.kernel, weightProc)

    check mst.len == 2

suite "Kosaraju - SCCs":
  test "Finds strongly connected components":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    # Create SCC: 0 <-> 1, and 2 separate
    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v0, 1.0)
    discard kernel.addEdge(v1, v2, 1.0)

    let sccs = kosaraju(kernel)

    check sccs.len == 2 # {0, 1} and {2}

  test "Handles non-contiguous vertex ids (transpose id-map regression)":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)
    # Remove v0 and re-add: the reused slot carries generation 1, so the
    # live ids are {1, 2, 0(gen1)} — not the 0,1,2 the transpose rebuilds to.
    # The old kosaraju fed these original ids straight into transpose lookups
    # and produced wrong SCCs.
    discard kernel.removeVertex(v0)
    let v3 = kernel.addVertex(3) # reuses slot 0 with generation 1

    # One 2-cycle {1,2}, plus an isolated vertex v3.
    discard kernel.addEdge(v1, v2, 1.0)
    discard kernel.addEdge(v2, v1, 1.0)

    let sccs = kosaraju(kernel)

    check sccs.len == 2 # {1,2} and {v3}
    let cycle = sccs.filterIt(it.len == 2)
    check cycle.len == 1
    let cycleMembers = cycle[0].toHashSet()
    check v1 in cycleMembers and v2 in cycleMembers

suite "Tarjan - SCCs":
  test "Algorithm correctly finds SCCs":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v0, 1.0)
    discard kernel.addEdge(v1, v2, 1.0)

    let sccs = tarjan(kernel)
    check sccs.len == 2

suite "Articulation Points":
  test "Finds articulation points in a line":
    var graph = newImmutableGraph[int, float](Undirected)
    let v0 = newVertexId(0)
    let v1 = newVertexId(1)
    let v2 = newVertexId(2)

    (graph, _) = graph.addVertex(0)
    (graph, _) = graph.addVertex(1)
    (graph, _) = graph.addVertex(2)

    graph = graph.addEdge(v0, v1, 1.0)
    graph = graph.addEdge(v1, v2, 1.0)

    let pts = findArticulationPoints(graph.kernel)
    # In 0-1-2, 1 is the articulation point
    check pts.len == 1
    check pts[0] == v1

suite "TSP - Nearest Neighbor":
  test "Creates tour":
    var kernel = newListKernel[int, float]()
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)

    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v2, 2.0)
    discard kernel.addEdge(v2, v0, 3.0)

    let weightProc = proc(e: Edge[float]): float = e.data
    let (path, cost) = tspNearestNeighbor(kernel, v0, weightProc)

    check path.len == 4 # v0 -> v1 -> v2 -> v0
    check cost == 6.0

suite "TSP - 2-opt":
  test "Improves a suboptimal tour":
    var kernel = newListKernel[int, float]()
    # Create a simple square with diagonals
    let v0 = kernel.addVertex(0)
    let v1 = kernel.addVertex(1)
    let v2 = kernel.addVertex(2)
    let v3 = kernel.addVertex(3)

    # Square edges (weight 1)
    discard kernel.addEdge(v0, v1, 1.0)
    discard kernel.addEdge(v1, v2, 1.0)
    discard kernel.addEdge(v2, v3, 1.0)
    discard kernel.addEdge(v3, v0, 1.0)
    # Diagonal edges (weight 2)
    discard kernel.addEdge(v0, v2, 2.0)
    discard kernel.addEdge(v1, v3, 2.0)

    let weightProc = proc(e: Edge[float]): float = e.data
    # Suboptimal path: 0-2-1-3 (costs 2 + 1 + 2 + 1 = 6)
    let initialPath = @[v0, v2, v1, v3]
    let (path, cost) = tsp2Opt(kernel, weightProc, initialPath)

    # Should improve to cost 4.0
    check path.len == initialPath.len
    check cost == 4.0

suite "Deep traversal robustness":
  test "DFS and SCC algorithms use explicit stacks":
    const vertexCount = 20_000
    var kernel = newListKernel[int, float]()
    var ids = newSeq[VertexId](vertexCount)
    for i in 0 ..< vertexCount:
      ids[i] = kernel.addVertex(i)
      if i > 0:
        discard kernel.addEdge(ids[i - 1], ids[i], 1.0)

    let visitor = newVisitor[float](trace = false)
    kernel.dfs(ids[0], visitor)
    check visitor.visitOrder.len == vertexCount
    check kernel.tarjan().len == vertexCount
    check kernel.kosaraju().len == vertexCount
