# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nbText: "# Visualization"
nbText: """
**UniGraph** provides visualization tools to help you understand and debug graph structures.

## ASCII Rendering

Quick visualization for debugging directly in the terminal.

### Basic Usage

```nim
import UniGraph

var g = newImmutableGraph[string, float](Directed)

# addVertex on the wrapper returns (newGraph, id) -- use it, not g.kernel
# directly, or g.vertexCount won't reflect what you just added.
var v0, v1, v2, v3: VertexId
(g, v0) = g.addVertex("A")
(g, v1) = g.addVertex("B")
(g, v2) = g.addVertex("C")
(g, v3) = g.addVertex("D")

g = g.addEdge(v0, v1, 1.0)
g = g.addEdge(v0, v2, 2.0)
g = g.addEdge(v1, v3, 3.0)
g = g.addEdge(v2, v3, 4.0)

# Print ASCII representation
g.kernel.render()
```

**Verified output** (`render` is `echo kernel.toAscii(...)`, and `toAscii`'s
result already ends in `\n` — `echo` adds one more, so there's a trailing
blank line after the last vertex; `kernel.vertices()` also iterates in
`Table` hash order, not insertion order, same caveat as Shortest Path's
Dijkstra example — order below is what a real run actually printed, not
`0,1,2,3`):
```
  [1] -> 3
  [3] (isolated)
  [0] -> 1, 2
  [2] -> 3

```

### Custom Formatting

```nim
let asciiArt = g.kernel.toAscii(maxVertices = 50)
echo "Graph structure:\n", asciiArt
```

## DOT/Graphviz Export

For professional-quality visualizations, export to DOT format.

### Basic Export

```nim
import UniGraph

var g = newImmutableGraph[string, float](Undirected)

let cities = ["Paris", "Lyon", "Marseille", "Toulouse", "Bordeaux"]
var cityIds: seq[VertexId] = @[]

for city in cities:
  var id: VertexId
  (g, id) = g.addVertex(city)
  cityIds.add(id)

# Add connections
g = g.addEdge(cityIds[0], cityIds[1], 450.0)  # Paris-Lyon
g = g.addEdge(cityIds[1], cityIds[2], 310.0)  # Lyon-Marseille
g = g.addEdge(cityIds[2], cityIds[3], 400.0)  # Marseille-Toulouse
g = g.addEdge(cityIds[3], cityIds[4], 240.0)  # Toulouse-Bordeaux
g = g.addEdge(cityIds[4], cityIds[0], 550.0)  # Bordeaux-Paris

# Export to DOT
g.kernel.saveDot("france.dot", directed = false)
```

**Generate image:**
```bash
dot -Tpng france.dot -o france.png
neato -Tpng france.dot -o france_layout.png  # Better layout
circo -Tpng france.dot -o france_circular.png  # Circular layout
```

### DOT Format Explanation

```dot
graph G {
  0 [label="0: Paris"];
  1 [label="1: Lyon"];
  0 -- 1 [label="450.0"];
  ...
}
```

**Parameters:**
- `directed`: Use `digraph` for directed graphs
- `labelVertices`: Include vertex data in labels

### Advanced DOT Options

```nim
proc toDotWithStyle[V, E](
    kernel: ListKernel[V, E],
    directed: bool = true
): string =
  result = ""
  
  if directed:
    result.add("digraph G {\n")
    result.add("  rankdir=LR;\n")  # Left to right
    result.add("  node [shape=box, style=filled, fillcolor=lightblue];\n")
    result.add("  edge [color=gray50];\n")
  else:
    result.add("graph G {\n")
    result.add("  node [shape=circle, style=filled, fillcolor=lightgreen];\n")
  
  # Add vertices
  for vertex in kernel.vertices():
    result.add("  " & $vertex.id.id & ";\n")
  
  # Add edges
  for vertex in kernel.vertices():
    for edge in kernel.neighbors(vertex.id):
      if directed:
        result.add("  " & $vertex.id.id & " -> " & $edge.target.id & ";\n")
      else:
        if vertex.id.id < edge.target.id:
          result.add("  " & $vertex.id.id & " -- " & $edge.target.id & ";\n")
  
  result.add("}\n")
```

## Graph Statistics

Built-in analysis tools.

### Basic Statistics

```nim
import UniGraph

var g = newImmutableGraph[string, float](Directed)
var vs: seq[VertexId] = @[]
for name in ["A", "B", "C", "D", "E", "F"]:
  var id: VertexId
  (g, id) = g.addVertex(name)
  vs.add id

g = g.addEdge(vs[0], vs[1], 1.0)
g = g.addEdge(vs[0], vs[2], 1.0)
g = g.addEdge(vs[1], vs[3], 1.0)
g = g.addEdge(vs[2], vs[3], 1.0)
g = g.addEdge(vs[3], vs[4], 1.0)
g = g.addEdge(vs[4], vs[5], 1.0)
g = g.addEdge(vs[5], vs[0], 1.0)
g = g.addEdge(vs[1], vs[4], 1.0)

g.kernel.printStats()
```

**Verified output** (`degreeDistribution` counts *out*-degree per vertex on
this directed graph, so the distribution's `degree × count` sum always
equals the edge count — `1×4 + 2×2 = 8` here):
```
Graph Statistics:
  Vertices: 6
  Edges: 8
  Density: 0.2667
  Degree distribution:
    Degree 1: 4 vertices
    Degree 2: 2 vertices
```

### Custom Analysis

```nim
proc analyzeGraph[V, E](kernel: ListKernel[V, E]) =
  let vCount = kernel.vertexCount()
  let eCount = kernel.edgeCount()
  
  echo "=== Graph Analysis ==="
  echo "Vertices: ", vCount
  echo "Edges: ", eCount
  let averageOutDegree = if vCount == 0: 0.0 else: float(eCount) / float(vCount)
  echo "Average out-degree: ", averageOutDegree
  
  # Degree distribution
  var degreeHist = initTable[int, int]()
  for vertex in kernel.vertices():
    let deg = kernel.neighbors(vertex.id).len
    degreeHist[deg] = degreeHist.getOrDefault(deg, 0) + 1
  
  echo "Degree distribution:"
  for deg, count in degreeHist:
    echo "  Degree ", deg, ": ", count, " vertices"
  
  # Check connectivity
  if kernel.isConnectedUndirected():
    echo "Graph is connected"
  else:
    echo "Graph is NOT connected"
```

## Visualization During Traversal

Combine visualization with the Visitor pattern for step-by-step animation.

### BFS Visualization

```nim
var traversalGraph = newListKernel[string, float]()
let traversalStart = traversalGraph.addVertex("A")
let traversalEnd = traversalGraph.addVertex("B")
discard traversalGraph.addEdge(traversalStart, traversalEnd, 1.0)
var visitor = newVisitor[float]()
traversalGraph.bfs(traversalStart, visitor)

echo "BFS Execution Trace:"
echo "===================="
for step in visitor.trace:
  echo step

echo ""
echo "Visit order: ", visitor.visitOrder
echo "Discovery order: ", visitor.discovered
```

### Post-Processing a Visitor's Trace

`bfs`/`dfs` take the concrete `Visitor[E]` type — there is no pluggable
visitor concept/interface to swap in a custom type. To build your own
visualization, run a real `Visitor[E]` and reshape *its* `trace`,
`edgeClassifications`, or `discoveryTime`/`finishTime` afterward:

```nim
var realVisitor = newVisitor[float]()
traversalGraph.dfs(traversalStart, realVisitor)

for i, line in realVisitor.trace:
  echo "[", i + 1, "/", realVisitor.trace.len, "] ", line

echo ""
echo "Edge kinds seen:"
for entry in realVisitor.edgeClassifications:
  echo "  ", entry.source.id, " -> ", entry.target.id, ": ", entry.kind
```

**Verified output** (2-vertex graph, single edge `A -> B`):
```
[1/5] Step 1: Discovered vertex 0 (order: 0, time: 0)
[2/5] Step 2: Traversed edge 0 -> 1 (ekTree)
[3/5] Step 3: Discovered vertex 1 (order: 1, time: 1)
[4/5] Step 4: Finished vertex 1 (time: 2)
[5/5] Step 5: Finished vertex 0 (time: 3)

Edge kinds seen:
  0 -> 1: ekTree
```

## Integration with External Tools

### Export to JSON

```nim
import std/json
import UniGraph

var g = newImmutableGraph[string, float](Directed)
var a, b: VertexId
(g, a) = g.addVertex("A")
(g, b) = g.addVertex("B")
g = g.addEdge(a, b, 1.0)

proc toJson[V, E](kernel: ListKernel[V, E]): JsonNode =
  result = newJObject()
  
  var nodes = newJArray()
  for vertex in kernel.vertices():
    nodes.add(%*{
      "id": $vertex.id.id,
      "label": $vertex.data
    })
  
  var edges = newJArray()
  for vertex in kernel.vertices():
    for edge in kernel.neighbors(vertex.id):
      edges.add(%*{
        "source": $vertex.id.id,
        "target": $edge.target.id,
        "weight": $edge.data
      })
  
  result["nodes"] = nodes
  result["edges"] = edges

# Export and use with D3.js, Cytoscape.js, etc.
let jsonData = g.kernel.toJson().pretty()
writeFile("graph.json", jsonData)
```

### Export to GEXF (Gephi)

```nim
import std/[xmltree, sugar]
import UniGraph

var g = newImmutableGraph[string, float](Directed)
var a, b: VertexId
(g, a) = g.addVertex("A")
(g, b) = g.addVertex("B")
g = g.addEdge(a, b, 1.0)

proc toGexf[V, E](kernel: ListKernel[V, E]): string =
  ## newXmlTree's signature is (tag, children, attributes) -- attributes are
  ## built with `.toXmlAttributes` on a table literal, not passed as the
  ## children slot. `edge.target` is already a VertexId (unlike `vertex.id`,
  ## which is a Vertex[V]'s VertexId field), so its int id is `edge.target.id`
  ## -- not `edge.target.id.id`.
  let nodes = collect:
    for vertex in kernel.vertices():
      newXmlTree("node", [],
        {"id": $vertex.id.id, "label": $vertex.data}.toXmlAttributes)

  let edges = collect:
    for vertex in kernel.vertices():
      for edge in kernel.neighbors(vertex.id):
        newXmlTree("edge", [], {
          "source": $vertex.id.id,
          "target": $edge.target.id,
          "weight": $edge.data
        }.toXmlAttributes)

  let gexf = newXmlTree("gexf", [
    newXmlTree("graph", [
      newXmlTree("nodes", nodes),
      newXmlTree("edges", edges)
    ], {"defaultedgetype": "directed"}.toXmlAttributes)
  ], {"version": "1.2", "xmlns": "http://www.gexf.net/1.2draft"}.toXmlAttributes)

  $gexf

# Import into Gephi (https://gephi.org) for advanced visualization
writeFile("graph.gexf", g.kernel.toGexf())
```

**Verified output** (2-vertex graph, single edge `A -> B` weight `1.0`):
```xml
<gexf version="1.2" xmlns="http://www.gexf.net/1.2draft">
  <graph defaultedgetype="directed">
    <nodes>
      <node label="A" id="0" />
      <node label="B" id="1" />
    </nodes>
    <edges>
      <edge source="0" weight="1.0" target="1" />
    </edges>
  </graph>
</gexf>
```

## Practice Exercises

### Exercise 1: Graph Animator
Create an HTML/JavaScript visualization that animates BFS traversal.

```nim
proc toHtmlAnimation[V, E](
    kernel: ListKernel[V, E],
    traversal: seq[VertexId]
): string =
  # Generate HTML with D3.js animation
  discard
```

### Exercise 2: Community Detection Visualization
Color vertices by their SCC membership.

```nim
proc toColoredDot[V, E](
    kernel: ListKernel[V, E],
    sccs: seq[seq[VertexId]]
): string =
  # Each SCC gets a different color
  discard
```

### Exercise 3: Weight Heatmap
Color edges by weight (red = high, blue = low).

```nim
proc toHeatmapDot[V, E](
    kernel: ListKernel[V, E],
    weightProc: proc(edge: Edge[E]): float
): string =
  # Gradient from blue to red based on weight
  discard
```

### Exercise 4: Interactive Web Viewer
Create a web-based graph explorer.

```nim
# Use jester (web framework) to serve interactive graph
# Features:
# - Zoom and pan
# - Click to see vertex/edge details
# - Run algorithms and animate results
discard
```

## Tips for Effective Visualization

1. **Choose the right layout**:
   - `dot`: Hierarchical (directed graphs)
   - `neato`: Spring model (undirected)
   - `circo`: Circular (cycles)
   - `fdp`: Force-directed (clusters)

2. **Limit graph size**: For large graphs, use sampling or aggregation

3. **Use colors meaningfully**: Highlight important structures

4. **Label selectively**: Too many labels clutter the view

5. **Animate algorithms**: Step-by-step visualization aids understanding

## References

- Wikipedia: [Graphviz](https://en.wikipedia.org/wiki/Graphviz)
- Wikipedia: [DOT (graph description language)](https://en.wikipedia.org/wiki/DOT_(graph_description_language))
- Wikipedia: [Gephi](https://en.wikipedia.org/wiki/Gephi) — the GEXF export target
- Wikipedia: [Graph drawing](https://en.wikipedia.org/wiki/Graph_drawing)
"""
nbSave
