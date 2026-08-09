# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## tests/unit/test_kernels.nim
## Unit tests for User Story 2: Kernel implementations
## Tests MatrixKernel and CsrKernel

import unittest, options
import ../../src/UniGraph/types
import ../../src/UniGraph/kernels/list_kernel
import ../../src/UniGraph/kernels/seq_kernel
import ../../src/UniGraph/kernels/matrix_kernel
import ../../src/UniGraph/kernels/csr_kernel

suite "MatrixKernel - Vertex Operations":
  test "Add and get vertex":
    var kernel = newMatrixKernel[int, float]()
    let id = kernel.addVertex(42)

    let vertex = kernel.getVertex(id)
    let expected = none(Vertex[int])
    check vertex != expected
    check vertex.get().data == 42

  test "Add multiple vertices":
    var kernel = newMatrixKernel[int, float]()
    let id1 = kernel.addVertex(10)
    let id2 = kernel.addVertex(20)
    let id3 = kernel.addVertex(30)

    check kernel.vertexCount() == 3
    check kernel.getVertex(id1).get().data == 10
    check kernel.getVertex(id2).get().data == 20
    check kernel.getVertex(id3).get().data == 30

  test "Capacity exceeded":
    var kernel = newMatrixKernel[int, float](capacity = 2)
    discard kernel.addVertex(10)
    discard kernel.addVertex(20)

    expect(IndexDefect):
      discard kernel.addVertex(30)

  test "Requesting capacity above the fixed 256 limit is rejected, not truncated":
    # Regression check: this used to silently clamp to 256, so a caller
    # asking for e.g. 1000 got a kernel that looked fine until the 257th
    # addVertex failed with an unrelated-looking IndexDefect.
    expect(RangeDefect):
      discard newMatrixKernel[int, float](capacity = 1000)

suite "MatrixKernel - Edge Operations":
  test "Add and check edge":
    var kernel = newMatrixKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)

    let added = kernel.addEdge(v1, v2, 3.14)
    check added == true
    check kernel.hasEdge(v1, v2) == true

    let edge = kernel.getEdge(v1, v2)
    let expected = none(float)
    check edge != expected
    check edge.get() == 3.14

  test "O(1) edge lookup":
    var kernel = newMatrixKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    discard kernel.addEdge(v1, v2, 1.0)

    # Multiple lookups should all be O(1)
    check kernel.hasEdge(v1, v2) == true
    check kernel.hasEdge(v2, v1) == false

  test "Self-loop rejected":
    var kernel = newMatrixKernel[int, float]()
    let v = kernel.addVertex(10)
    check kernel.addEdge(v, v, 1.0) == false

  test "Parallel edge rejected":
    var kernel = newMatrixKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)

    check kernel.addEdge(v1, v2, 1.0) == true
    check kernel.addEdge(v1, v2, 2.0) == false

suite "MatrixKernel - Remove Vertex":
  test "Remove vertex clears edges":
    var kernel = newMatrixKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    let v3 = kernel.addVertex(30)

    discard kernel.addEdge(v1, v2, 1.0)
    discard kernel.addEdge(v2, v3, 2.0)
    discard kernel.addEdge(v3, v1, 3.0)

    discard kernel.removeVertex(v2)

    # v2 should be removed
    check kernel.getVertex(v2).isNone()

    # Edges involving v2 should be gone
    check kernel.hasEdge(v1, v2) == false
    check kernel.hasEdge(v2, v3) == false

    # Other edges remain
    check kernel.hasEdge(v3, v1) == true
    check kernel.vertexCount() == 2

suite "Multi edge removal":
  test "ListKernel removes one parallel edge":
    var kernel = newListKernel[int, float]()
    kernel.graphType = Multi
    let a = kernel.addVertex(1)
    let b = kernel.addVertex(2)
    check kernel.addEdge(a, b, 1.0)
    check kernel.addEdge(a, b, 2.0)
    check kernel.edgeCount == 2
    check kernel.removeEdge(a, b)
    check kernel.edgeCount == 1
    check kernel.hasEdge(a, b)

  test "SeqKernel removes one parallel edge":
    var kernel = newSeqKernel[int, float]()
    kernel.graphType = Multi
    let a = kernel.addVertex(1)
    let b = kernel.addVertex(2)
    check kernel.addEdge(a, b, 1.0)
    check kernel.addEdge(a, b, 2.0)
    check kernel.edgeCount == 2
    check kernel.removeEdge(a, b)
    check kernel.edgeCount == 1
    check kernel.hasEdge(a, b)

suite "CsrKernel - Construction":
  test "Build vertices and edges":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    let v3 = kernel.addVertex(30)

    discard kernel.addEdge(v1, v2, 1.0)
    discard kernel.addEdge(v2, v3, 2.0)
    discard kernel.addEdge(v1, v3, 3.0)

    kernel.build()

    check kernel.vertexCount() == 3
    check kernel.edgeCount == 3
    check kernel.isBuilt == true

  test "Cannot modify after build":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    kernel.build()

    expect(ValueError):
      discard kernel.addVertex(30)

    check kernel.addEdge(v1, v2, 1.0) == false

  test "removeVertex/removeEdge return false, never raise (GraphKernel contract)":
    # Regression check: these used to raise ValueError, which type-checks as
    # `is bool` under the concept but breaks any generic caller expecting a
    # graceful false like every other kernel gives.
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    discard kernel.addEdge(v1, v2, 1.0)
    kernel.build()

    check kernel.removeVertex(v1) == false
    check kernel.removeEdge(v1, v2) == false
    # And the structure is genuinely untouched by the rejected call.
    check kernel.hasEdge(v1, v2) == true

  test "edges iterator visits every row exactly once (O(V+E), not O(V*E))":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    let v3 = kernel.addVertex(30)
    let v4 = kernel.addVertex(40) # no outgoing edges: exercises an empty row

    discard kernel.addEdge(v1, v2, 1.0)
    discard kernel.addEdge(v1, v3, 2.0)
    discard kernel.addEdge(v3, v4, 3.0)
    kernel.build()

    var seen: seq[tuple[src, dst: int]] = @[]
    for e in kernel.edges():
      seen.add((e.source.id, e.target.id))

    check seen.len == 3
    check (v1.id, v2.id) in seen
    check (v1.id, v3.id) in seen
    check (v3.id, v4.id) in seen

suite "CsrKernel - Query Operations":
  test "Get vertex":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    kernel.build()

    let vertex = kernel.getVertex(v1)
    let expected = none(Vertex[int])
    check vertex != expected
    check vertex.get().data == 10

  test "Has edge with binary search":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    let v3 = kernel.addVertex(30)

    discard kernel.addEdge(v1, v2, 1.0)
    discard kernel.addEdge(v1, v3, 2.0)
    kernel.build()

    check kernel.hasEdge(v1, v2) == true
    check kernel.hasEdge(v1, v3) == true
    check kernel.hasEdge(v2, v1) == false

  test "Get edge":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)

    discard kernel.addEdge(v1, v2, 3.14)
    kernel.build()

    let edge = kernel.getEdge(v1, v2)
    let expected = none(float)
    check edge != expected
    check edge.get() == 3.14

suite "CsrKernel - Neighbors":
  test "Get neighbors":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    let v3 = kernel.addVertex(30)

    discard kernel.addEdge(v1, v2, 1.0)
    discard kernel.addEdge(v1, v3, 2.0)
    kernel.build()

    let neighbors = kernel.neighbors(v1)
    check neighbors.len == 2

  test "Empty neighbors":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    kernel.build()

    let neighbors = kernel.neighbors(v1)
    check neighbors.len == 0

suite "Kernel Contract - All Kernels":
  test "ListKernel basic operations":
    var kernel = newListKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)

    check kernel.addEdge(v1, v2, 1.0) == true
    check kernel.hasEdge(v1, v2) == true
    check kernel.vertexCount() == 2

  test "MatrixKernel basic operations":
    var kernel = newMatrixKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)

    check kernel.addEdge(v1, v2, 1.0) == true
    check kernel.hasEdge(v1, v2) == true
    check kernel.vertexCount() == 2

  test "CsrKernel basic operations":
    var kernel = newCsrKernel[int, float]()
    let v1 = kernel.addVertex(10)
    let v2 = kernel.addVertex(20)
    discard kernel.addEdge(v1, v2, 1.0)
    kernel.build()

    check kernel.hasEdge(v1, v2) == true
    check kernel.vertexCount() == 2
