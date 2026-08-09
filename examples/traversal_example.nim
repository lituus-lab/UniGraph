# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## examples/traversal_example.nim
## Traversal example with Visitor pattern for pedagogical tracing
##
## This example demonstrates:
## - BFS and DFS traversal with execution tracing
## - Capturing step-by-step algorithm execution
## - Using the Visitor pattern for educational purposes

import UniGraph, sequtils, strutils

echo "=== UniGraph Traversal Example ===\n"

# Create a sample graph
var graph = newImmutableGraph[int, float]()

# Build a small tree-like structure. addVertex returns (newGraph, id): with
# an immutable graph, the id must travel alongside each new instance.
let (g1, v0) = graph.addVertex(0)
let (g2, v1) = g1.addVertex(1)
let (g3, v2) = g2.addVertex(2)
let (g4, v3) = g3.addVertex(3)
let (g5, v4) = g4.addVertex(4)

# Add edges to create branches
let g6 = g5.addEdge(v0, v1, 1.0)
let g7 = g6.addEdge(v0, v2, 2.0)
let g8 = g7.addEdge(v1, v3, 3.0)
let g9 = g8.addEdge(v2, v4, 4.0)

echo "Graph structure:"
g9.kernel.render()
echo ""

# BFS with Visitor tracing
echo "=== BFS Traversal (from vertex 0) ==="
var bfsVisitor = newVisitor[float]()
g9.kernel.bfs(v0, bfsVisitor)

echo "\nBFS Execution Trace:"
for step in bfsVisitor.trace:
  echo "  ", step

echo "\nBFS Visit Order: "
for vid in bfsVisitor.visitOrder:
  echo "  ", vid.id, " "

echo "\n\n=== DFS Traversal (from vertex 0) ==="
var dfsVisitor = newVisitor[float]()
g9.kernel.dfs(v0, dfsVisitor)

echo "\nDFS Execution Trace:"
for step in dfsVisitor.trace:
  echo "  ", step

echo "\nDFS Discovery Order: "
for vid in dfsVisitor.discovered:
  echo "  ", vid.id, " "

echo "\nDFS Finish Order: "
for vid in dfsVisitor.finished:
  echo "  ", vid.id, " "

echo "\n\n=== Comparison ==="
echo "BFS explores level by level (breadth-first)"
echo "DFS explores depth-first before backtracking"
echo "\nBFS order: ", bfsVisitor.visitOrder.mapIt($it.id).join(" -> ")
echo "DFS order: ", dfsVisitor.discovered.mapIt($it.id).join(" -> ")

echo "\n\n=== Example Complete ==="
