# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## examples/kernel_comparison.nim
## Compare different kernel backends
##
## This example demonstrates:
## - ListKernel for sparse graphs
## - MatrixKernel for dense graphs
## - CsrKernel for static analysis

import UniGraph

echo "=== UniGraph Kernel Comparison ===\n"

# ============================================================================
# ListKernel - Best for sparse graphs
# ============================================================================
echo "=== ListKernel (Sparse Graph) ==="
var listKernel = newListKernel[int, float]()

let v0 = listKernel.addVertex(0)
let v1 = listKernel.addVertex(1)
let v2 = listKernel.addVertex(2)
let v3 = listKernel.addVertex(3)

discard listKernel.addEdge(v0, v1, 1.0)
discard listKernel.addEdge(v1, v2, 2.0)
# Sparse: only 2 edges for 4 vertices

echo "Vertices: ", listKernel.vertexCount()
echo "Edges: ", listKernel.edgeCount()
echo "Structure:"
listKernel.render()
echo "Space complexity: O(V+E) = O(", listKernel.vertexCount(), "+",
    listKernel.edgeCount(), ")\n"

# ============================================================================
# MatrixKernel - Best for dense graphs
# ============================================================================
echo "=== MatrixKernel (Dense Graph) ==="
var matrixKernel = newMatrixKernel[int, float](capacity = 4)

let m0 = matrixKernel.addVertex(0)
let m1 = matrixKernel.addVertex(1)
let m2 = matrixKernel.addVertex(2)
let m3 = matrixKernel.addVertex(3)

# Dense: connect most vertices
discard matrixKernel.addEdge(m0, m1, 1.0)
discard matrixKernel.addEdge(m0, m2, 2.0)
discard matrixKernel.addEdge(m0, m3, 3.0)
discard matrixKernel.addEdge(m1, m2, 4.0)
discard matrixKernel.addEdge(m1, m3, 5.0)
discard matrixKernel.addEdge(m2, m3, 6.0)

echo "Vertices: ", matrixKernel.vertexCount()
echo "Edges: ", matrixKernel.edgeCount()
echo "Edge lookup (0->3): ", matrixKernel.hasEdge(m0, m3)
echo "Edge lookup is O(1) - constant time!\n"

# ============================================================================
# CsrKernel - Best for static graph analysis
# ============================================================================
echo "=== CsrKernel (Static Analysis) ==="
var csrKernel = newCsrKernel[int, float]()

let c0 = csrKernel.addVertex(0)
let c1 = csrKernel.addVertex(1)
let c2 = csrKernel.addVertex(2)
let c3 = csrKernel.addVertex(3)
let c4 = csrKernel.addVertex(4)

discard csrKernel.addEdge(c0, c1, 1.0)
discard csrKernel.addEdge(c0, c2, 2.0)
discard csrKernel.addEdge(c1, c3, 3.0)
discard csrKernel.addEdge(c2, c3, 4.0)
discard csrKernel.addEdge(c3, c4, 5.0)

# Build the CSR structure (required before queries)
csrKernel.build()

echo "Vertices: ", csrKernel.vertexCount()
echo "Edges: ", csrKernel.edgeCount()
echo "Built for optimal traversal (cache-local memory access)"
echo "Neighbors of vertex 0:"
for edge in csrKernel.neighbors(c0):
  echo "  -> ", edge.target.id, " (weight: ", edge.data, ")"

echo "\nNote: CsrKernel is immutable after build() - optimal for read-only analysis\n"

# ============================================================================
# Summary
# ============================================================================
echo "=== Kernel Selection Guide ==="
echo "ListKernel:  Sparse graphs, dynamic updates (add/remove vertices/edges)"
echo "MatrixKernel: Dense graphs, frequent edge lookups, small fixed size"
echo "CsrKernel:   Large static graphs, traversal-heavy workloads"

echo "\n=== Example Complete ==="
