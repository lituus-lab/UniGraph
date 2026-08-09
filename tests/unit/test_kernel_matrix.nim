# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# UniGraph — same algorithms, all four kernels
# =============================================================================
# The kernel doctrine in one test file: an identical graph is built on each
# storage kernel and every kernel-generic algorithm must return identical
# results. Storage changes; answers do not.
#
# Graph under test (each edge added in both directions):
#
#        a --1.0-- b --2.0-- c
#        a ------4.0-------- c

import std/[unittest, tables]
import ../../src/UniGraph/types
import ../../src/UniGraph/kernels/list_kernel
import ../../src/UniGraph/kernels/seq_kernel
import ../../src/UniGraph/kernels/csr_kernel
import ../../src/UniGraph/kernels/matrix_kernel
import ../../src/UniGraph/algorithms/traversals
import ../../src/UniGraph/algorithms/shortest_path
import ../../src/UniGraph/algorithms/mst
import ../../src/UniGraph/algorithms/scc

# Builds the reference graph on the given kernel and runs the battery.
template runBattery(makeKernel: untyped) =
  block:
    var k = makeKernel
    let a = k.addVertex(0)
    let b = k.addVertex(1)
    let c = k.addVertex(2)
    for (u, v, w) in [(a, b, 1.0), (b, c, 2.0), (a, c, 4.0)]:
      discard k.addEdge(u, v, w)
      discard k.addEdge(v, u, w)

    let weight = proc(e: Edge[float]): float = e.data

    # dijkstra: a->c goes through b (1 + 2 = 3 < 4)
    let (dist, parents) = dijkstra(k, a, weight)
    check dist[b] == 1.0
    check dist[c] == 3.0
    check parents[c] == b

    # MST: both algorithms pick {1.0, 2.0}
    var primTotal = 0.0
    for e in prim(k, weight): primTotal += e.data
    var kruskalTotal = 0.0
    for e in kruskal(k, weight): kruskalTotal += e.data
    check primTotal == 3.0
    check kruskalTotal == 3.0

    # traversals: every vertex reachable from a
    check reachableVertices(k, a).len == 3
    check isConnectedUndirected(k)

    # SCC: symmetric edges form a single component of 3
    let comps = tarjan(k)
    check comps.len == 1
    check comps[0].len == 3

suite "Kernel matrix - identical results on every kernel":
  test "ListKernel":
    runBattery(newListKernel[int, float]())
  test "SeqKernel":
    runBattery(newSeqKernel[int, float]())
  test "CsrKernel":
    runBattery(newCsrKernel[int, float]())
  test "MatrixKernel":
    runBattery(newMatrixKernel[int, float]())
