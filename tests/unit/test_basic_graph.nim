# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## tests/unit/test_basic_graph.nim
## Unit tests for User Story 1: Basic graph operations
## Tests vertex/edge operations, ID stability, and immutability

import unittest, options
import ../../src/UniGraph/types
import ../../src/UniGraph/kernels/list_kernel
import ../../src/UniGraph/kernels/seq_kernel
import ../../src/UniGraph/kernels/csr_kernel
import ../../src/UniGraph/kernels/matrix_kernel
import ../../src/UniGraph/graph

suite "ListKernel - Vertex Operations":
  test "Add and get vertex":
    var kernel = newListKernel[int, float]()
    let id = kernel.addVertex(42)

    let vertex = kernel.getVertex(id)
    check vertex.isSome
    check vertex.get().data == 42
    check vertex.get().id == id

  test "Get non-existent vertex":
    let kernel = newListKernel[int, float]()
    let id = newVertexId(999, 0'u16)
    check kernel.getVertex(id).isNone

  test "Add multiple vertices":
    var kernel = newListKernel[int, float]()
    let id1 = kernel.addVertex(10)
    let id2 = kernel.addVertex(20)
    let id3 = kernel.addVertex(30)

    check kernel.vertexCount() == 3
    check kernel.getVertex(id1).get().data == 10
    check kernel.getVertex(id2).get().data == 20
    check kernel.getVertex(id3).get().data == 30

suite "ListKernel - Edge Operations":
  test "Add and check edge":
    var kernel = newListKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)

    let added = kernel.addEdge(v1, v2, 3.14)
    check added == true
    check kernel.hasEdge(v1, v2) == true

    let edge = kernel.getEdge(v1, v2)
    check edge.isSome
    check edge.get() == 3.14

  test "Add edge with non-existent vertices":
    var kernel = newListKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = newVertexId(999, 0'u16) # Not in kernel

    check kernel.addEdge(v1, v2, 1.0) == false
    check kernel.addEdge(v2, v1, 1.0) == false

  test "Self-loop rejected (SimpleGraph)":
    var kernel = newListKernel[int, float]()
    let v = kernel.addVertex(10)

    # Self-loops should be rejected
    check kernel.addEdge(v, v, 1.0) == false

  test "Parallel edge rejected (SimpleGraph)":
    var kernel = newListKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)

    check kernel.addEdge(v1, v2, 1.0) == true
    check kernel.addEdge(v1, v2, 2.0) == false # Duplicate

suite "ListKernel - ID Stability":
  test "Vertex IDs remain valid after removal":
    var kernel = newListKernel[int, float]()
    let id1 = kernel.addVertex(10)
    let id2 = kernel.addVertex(20)
    let id3 = kernel.addVertex(30)

    # Remove middle vertex
    discard kernel.removeVertex(id2)

    # Other IDs should still be valid
    check kernel.getVertex(id1).isSome
    check kernel.getVertex(id3).isSome
    check kernel.getVertex(id1).get().data == 10
    check kernel.getVertex(id3).get().data == 30

  test "Removed vertex ID can be reused with new generation":
    var kernel = newListKernel[int, float]()
    let id1 = kernel.addVertex(10)
    let id2 = kernel.addVertex(20)

    discard kernel.removeVertex(id2)

    # Add new vertex - should reuse id2's slot with new generation
    let id3 = kernel.addVertex(30)
    check id3.id == id2.id
    check id3.generation > id2.generation # Generation incremented

suite "ImmutableGraph - Immutability":
  test "Add vertex returns new instance and its id":
    let graph1 = newImmutableGraph[int, float]()
    let (graph2, id) = graph1.addVertex(42)

    # graph1 should be unchanged
    check graph1.vertexCount == 0
    check graph2.vertexCount == 1
    check graph2.getVertex(id).get().data == 42

  test "Add edge returns new instance":
    let graph1 = newImmutableGraph[int, float]()
    let (graph2, id0) = graph1.addVertex(10)
    let (graph3, id1) = graph2.addVertex(20)

    let graph4 = graph3.addEdge(id0, id1, 1.5)

    # graph3 should be unchanged
    check graph3.edgeCount == 0
    check graph4.edgeCount == 1

  test "Remove vertex returns new instance":
    let graph1 = newImmutableGraph[int, float]()
    let (graph2, id0) = graph1.addVertex(10)
    let (graph3, _) = graph2.addVertex(20)

    let graph4 = graph3.removeVertex(id0)

    # graph3 should be unchanged
    check graph3.vertexCount == 2
    check graph4.vertexCount == 1

suite "Immutability across kernels (value semantics)":
  # addVertex does `var newGraph = graph` then mutates newGraph.kernel. Nim's
  # seq and Table assignments have value semantics and can perform full copies
  # unless move elision applies. These tests verify independence, not O(1)
  # copying, for every kernel rather than only the ListKernel default.
  test "SeqKernel: original unchanged after addVertex/addEdge/removeVertex":
    let g0 = newImmutableGraph[SeqKernel[int, float], int, float](
        newSeqKernel[int, float]())
    let (g1, a) = g0.addVertex(10)
    let (g2, b) = g1.addVertex(20)
    let g3 = g2.addEdge(a, b, 1.5)
    let g4 = g3.removeVertex(a)

    check g0.vertexCount == 0 and g0.edgeCount == 0
    check g1.vertexCount == 1 and g1.edgeCount == 0
    check g2.vertexCount == 2 and g2.edgeCount == 0
    check g3.vertexCount == 2 and g3.edgeCount == 1
    check g4.vertexCount == 1 and g4.edgeCount == 0
    # original of each step untouched
    check g2.hasEdge(a, b) == false
    check g3.getVertex(a).isSome

  test "CsrKernel: original unchanged after addVertex/addEdge":
    # CsrKernel is append/build-only and does not support vertex removal.
    let g0 = newImmutableGraph[CsrKernel[int, float], int, float](
        newCsrKernel[int, float]())
    let (g1, a) = g0.addVertex(10)
    let (g2, b) = g1.addVertex(20)
    let g3 = g2.addEdge(a, b, 1.5)
    check g0.vertexCount == 0
    check g2.vertexCount == 2 and g2.edgeCount == 0
    check g3.vertexCount == 2 and g3.edgeCount == 1
    check g2.hasEdge(a, b) == false

  test "MatrixKernel: original unchanged after addVertex/addEdge/removeVertex":
    let g0 = newImmutableGraph[MatrixKernel[int, float], int, float](
        newMatrixKernel[int, float]())
    let (g1, a) = g0.addVertex(10)
    let (g2, b) = g1.addVertex(20)
    let g3 = g2.addEdge(a, b, 1.5)
    let g4 = g3.removeVertex(a)
    check g0.vertexCount == 0
    check g2.edgeCount == 0
    check g3.edgeCount == 1
    check g4.vertexCount == 1 and g4.edgeCount == 0
    check g2.hasEdge(a, b) == false

suite "Graph - Integration":
  test "Complete workflow":
    # Create graph
    let graph1 = newImmutableGraph[int, float]()

    # Add vertices — each addVertex hands back the id needed for addEdge next
    let (graph2, id0) = graph1.addVertex(10)
    let (graph3, id1) = graph2.addVertex(20)

    # Add edge
    let graph4 = graph3.addEdge(id0, id1, 3.14)

    # Verify
    check graph4.vertexCount == 2
    check graph4.edgeCount == 1
    check graph4.hasEdge(id0, id1) == true
    check graph4.getEdge(id0, id1).get() == 3.14
