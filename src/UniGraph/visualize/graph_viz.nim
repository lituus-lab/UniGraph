# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/visualize/graph_viz.nim
## Graph visualization utilities
##
## This module provides:
## - ASCII rendering for quick debugging
## - DOT/Graphviz export for professional visualization
##
## Constitution Principle V: Pedagogy Through Transparency

import ../types, ../kernels/list_kernel
import std/strutils, std/os

proc escapeDot(s: string): string =
  ## Escape a string for safe inclusion inside a DOT double-quoted label.
  ## Backslashes first (so later escapes are not double-escaped), then quotes,
  ## then newlines turned into the DOT line-continuation escape.
  result = s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

# ============================================================================
# ASCII Rendering
# ============================================================================

proc toAscii*[V, E](kernel: ListKernel[V, E], maxVertices: int = 20): string =
  ## Render the graph as ASCII art for quick debugging.
  ## Only renders up to maxVertices to avoid huge output.
  result = ""

  var count = 0
  for vertex in kernel.vertices():
    if count >= maxVertices:
      result.add("  ... (truncated)\n")
      break

    let neighbors = kernel.neighbors(vertex.id)
    if neighbors.len == 0:
      result.add("  [" & $vertex.id.id & "] (isolated)\n")
    else:
      var neighborIds: seq[string] = @[]
      for edge in neighbors:
        neighborIds.add($edge.target.id)
      result.add("  [" & $vertex.id.id & "] -> " & neighborIds.join(", ") & "\n")

    count += 1

  if kernel.vertexCount() == 0:
    result = "  (empty graph)\n"

proc render*[V, E](kernel: ListKernel[V, E], maxVertices: int = 20) =
  ## Print ASCII representation to stdout.
  echo kernel.toAscii(maxVertices)

# ============================================================================
# DOT/Graphviz Export
# ============================================================================

proc toDot*[V, E](
    kernel: ListKernel[V, E],
    directed: bool = true,
    labelVertices: bool = true
): string =
  ## Export the graph to DOT format for Graphviz visualization.
  ##
  ## Parameters:
  ## - directed: If true, creates a digraph; otherwise a graph
  ## - labelVertices: If true, includes vertex data as labels
  ##
  ## Example usage:
  ## ```
  ## let dot = kernel.toDot()
  ## writeFile("graph.dot", dot)
  ## # Then run: dot -Tpng graph.dot -o graph.png
  ## ```

  result = ""

  if directed:
    result.add("digraph G {\n")
  else:
    result.add("graph G {\n")

  # Add vertices
  for vertex in kernel.vertices():
    if labelVertices:
      result.add("  " & $vertex.id.id & " [label=\"" & $vertex.id.id & ": " &
          escapeDot($vertex.data) & "\"];\n")
    else:
      result.add("  " & $vertex.id.id & ";\n")

  # Add edges
  for vertex in kernel.vertices():
    let neighbors = kernel.neighbors(vertex.id)
    for edge in neighbors:
      # Stringify both endpoint ids once, before concatenation. edge.target
      # is already a VertexId (Edge stores the id directly, unlike Vertex), so
      # its integer id is edge.target.id — not edge.target.id.id.
      let src = $vertex.id.id
      let dst = $edge.target.id

      if not directed and vertex.id.id > edge.target.id:
        # Undirected reverse mirror: the forward statement was already
        # emitted from the other endpoint. Skip the label and terminator too
        # so no dangling `[label=...];` fragment is written for an edge
        # statement that was not actually added.
        continue

      if directed:
        result.add("  " & src & " -> " & dst)
      else:
        result.add("  " & src & " -- " & dst)

      result.add(" [label=\"" & escapeDot($edge.data) & "\"]")

      result.add(";\n")

  result.add("}\n")

proc saveDot*[V, E](
    kernel: ListKernel[V, E],
    filename: string,
    directed: bool = true,
    labelVertices: bool = true
) =
  ## Save the graph to a DOT file.
  ##
  ## Example:
  ## ```
  ## kernel.saveDot("mygraph.dot")
  ## # Then: dot -Tpng mygraph.dot -o mygraph.png
  ## ```
  let dot = kernel.toDot(directed, labelVertices)
  writeFile(filename, dot)

# ============================================================================
# Simple Graph Statistics
# ============================================================================

proc degreeDistribution*[V, E](kernel: ListKernel[V, E]): seq[tuple[degree: int, count: int]] =
  ## Calculate the degree distribution of the graph.
  ## Returns a sequence of (degree, count) tuples.
  var degreeCount: seq[int] = @[]

  for vertex in kernel.vertices():
    let degree = kernel.neighbors(vertex.id).len
    while degreeCount.len <= degree:
      degreeCount.add(0)
    degreeCount[degree] += 1

  result = @[]
  for degree, count in degreeCount:
    if count > 0:
      result.add((degree: degree, count: count))

proc printStats*[V, E](kernel: ListKernel[V, E]) =
  ## Print basic graph statistics to stdout.
  echo "Graph Statistics:"
  echo "  Vertices: ", kernel.vertexCount()
  echo "  Edges: ", kernel.edgeCount()

  if kernel.vertexCount() > 1:
    let density = float(kernel.edgeCount()) / float(kernel.vertexCount() * (
        kernel.vertexCount() - 1))
    echo "  Density: ", formatFloat(density, ffDecimal, 4)

  echo "  Degree distribution:"
  for deg in kernel.degreeDistribution():
    echo "    Degree ", deg.degree, ": ", deg.count, " vertices"
