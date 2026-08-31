# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## The preface. A Nim chapter and not the Markdown it used to be: nimibook
## builds a `.md` entry without running any Nim, so `useLituus()` never fired
## and this one page shipped without the theme -- and without a working
## light/dark switch, the classes it toggles having no rules on it.
import nimib, nimibook
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "Preface"

nbText: """
# Welcome to UniGraph

**UniGraph** is a generic, pedagogical graph data structure library for Nim.

## Key Features

- 🚀 **Multiple kernel backends**: List/Seq (sparse), Matrix (dense), CSR (static analysis)
- 🎯 **Zero-cost abstractions**: compile-time generics, no dynamic dispatch or
  boxing between an algorithm and the kernel it runs on
- 🔒 **Stable vertex indices**: Petgraph pattern for safe vertex references
- ♻️ **Immutability by default**: functional purity, backed by Nim's ARC/ORC memory management
- 📖 **Pedagogical tracing**: Visitor pattern for step-by-step algorithm visualization

## The UniGraph Constitution

This library is built on five principles:

1. **Generic, not virtual**: algorithms are written once against the
   `GraphKernel` concept and monomorphized at compile time for each kernel —
   no runtime dispatch
2. **Pedagogical Clarity**: Every algorithm can show its work step-by-step
3. **Functional Purity**: Immutability by default, mutations when needed
4. **Type Safety**: Compile-time checks where possible, explicit errors and contracts at runtime
5. **Educational Transparency**: Algorithms are meant to be understood

## Who This Book Is For

- **Students** learning graph algorithms and data structures
- **Developers** needing efficient, reliable graph data structures
- **Educators** teaching discrete mathematics or algorithms
- **Researchers** prototyping new graph algorithms
- **Anyone** interested in Nim programming

You do not need a university algorithms course first. Comfort with variables,
loops, functions, and simple collections is enough. Each chapter introduces
the mathematical vocabulary before using it, then connects the idea to a
runnable program. Proof sketches explain *why* an algorithm works without
assuming advanced notation.

## How to Use This Book

Each chapter contains:

- **Theoretical foundations**: Mathematical background and complexity analysis
- **Executable code examples**: Real Nim code you can run and modify
- **Visual diagrams**: Illustrations of data structures and algorithms
- **Step-by-step traces**: See exactly how algorithms execute
- **Practice exercises**: Test your understanding with hands-on problems

A useful study rhythm is: draw the example on paper, predict the next step,
run the trace, and only then read the complexity analysis. Complexity describes
how work grows; it is not a stopwatch measurement.

### Suggested Reading Order

1. **[Installation](installation.html)** - Get set up in 5 minutes
2. **[Core Concepts](core_concepts.html)** - Understand the fundamentals
3. **[Quickstart](quickstart.html)** - Your first graph program
4. **[Graph Kernels](kernels.html)** - Choose the right data structure
5. **[Traversals](traversals.html)** - BFS and DFS foundations
6. **[Shortest Path](shortest_path.html)** - Dijkstra, A*, Bellman-Ford
7. **[Minimum Spanning Tree](mst.html)** - Prim's and Kruskal's algorithms
8. **[Strongly Connected Components](scc.html)** - Kosaraju's and Tarjan's
9. **[Traveling Salesman Problem](tsp.html)** - NP-hard optimization
10. **[Visualization](visualization.html)** - Debug and present your graphs

## Book Conventions

### Code Examples

All code examples are complete and executable:

```nim
import UniGraph

var g = newImmutableGraph[string, float](Directed)
let (g2, v) = g.addVertex("A")  # Returns (newGraph, id); g unchanged
```

### Complexity Notation

- **O(1)**: Constant time
- **O(log n)**: Logarithmic time
- **O(n)**: Linear time
- **O(n log n)**: Linearithmic time
- **O(n²)**: Quadratic time
- **O(2ⁿ)**: Exponential time

### Graph Notation

- **G = (V, E)**: Graph with vertex set V and edge set E
- **|V|**: Number of vertices (often denoted n)
- **|E|**: Number of edges (often denoted m)
- **deg(v)**: Degree of vertex v (number of incident edges)

## Getting Help

- **Source code**: <https://github.com/lituus-lab/UniGraph>
- **API documentation**: Generated from source comments
- **Issues and bugs**: Report on GitHub

## License

UniGraph is released under the Apache License 2.0.

---

Ready to explore graphs? Turn to [Chapter 1: What is UniGraph?](what_is_unigraph.html)
"""

nbSave
