# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimibook
import std/os

# Ensure output directory exists
createDir("__site")

var book = initBook()
book.title = "UniGraph - Graph Algorithms in Nim"
book.description = "A pedagogical guide to graph algorithms"

book.toc = initToc:
  entry("Preface", "preface.md")
  entry("What is UniGraph?", "what_is_unigraph.nim")
  entry("Installation", "installation.nim")
  entry("Core Concepts", "core_concepts.nim")
  entry("Quickstart", "quickstart.nim")
  entry("Graph Kernels", "kernels.nim")
  entry("Traversals", "traversals.nim")
  entry("Shortest Path", "shortest_path.nim")
  entry("Minimum Spanning Tree", "mst.nim")
  entry("Strongly Connected Components", "scc.nim")
  entry("Traveling Salesman Problem", "tsp.nim")
  entry("Visualization", "visualization.nim")

nimibookCli(book)
