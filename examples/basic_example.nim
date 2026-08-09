# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## examples/basic_example.nim
## Basic usage example for UniGraph library
##
## This example demonstrates:
## - Creating a graph with vertices and edges
## - Querying the graph
## - Using the immutable API

import UniGraph, options

echo "=== UniGraph Basic Example ===\n"

# Create a new immutable graph
var graph = newImmutableGraph[int, float]()

# Add vertices — addVertex returns (newGraph, id): immutability means each
# call hands back a fresh graph, so the id must travel with it explicitly.
echo "Adding vertices..."
let (graph1, idA) = graph.addVertex(10)
let (graph2, idB) = graph1.addVertex(20)
let (graph3, idC) = graph2.addVertex(30)

echo "Graph now has ", graph3.vertexCount, " vertices\n"

# Add edges
echo "Adding edges..."
let graph4 = graph3.addEdge(idA, idB, 1.5)
let graph5 = graph4.addEdge(idB, idC, 2.5)
let graph6 = graph5.addEdge(idA, idC, 3.0)

echo "Graph now has ", graph6.edgeCount, " edges\n"

# Query edges
echo "Edge queries:"
echo "  Edge 0->1 exists: ", graph6.hasEdge(idA, idB)
let edgeWeight = graph6.getEdge(idA, idB)
if edgeWeight.isSome:
  echo "  Edge 0->1 weight: ", edgeWeight.get()
echo "  Edge 1->0 exists: ", graph6.hasEdge(idB, idA)
echo ""

# Demonstrate immutability
echo "Immutability demonstration:"
echo "  graph3.edgeCount = ", graph3.edgeCount
echo "  graph6.edgeCount = ", graph6.edgeCount
echo "  (graph3 unchanged after adding edges to create graph6)"
echo ""

# Render ASCII
echo "Graph structure:"
graph6.kernel.render()

echo "\n=== Example Complete ==="
