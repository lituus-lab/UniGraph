# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, tables]
import nimibook
# `from ... import` and not a plain import: the theme module re-exports nimib
# for the chapters, and nimib's NbConfig has a `favicon_escaped` field too, so
# a plain import makes `book.favicon_escaped` below ambiguous.
from lituus_theme import faviconTag

# Ensure output directory exists
createDir("__site")

var book = initBook()
book.title = "UniGraph - Graph Algorithms in Nim"
book.description = "A pedagogical guide to graph algorithms"

book.toc = initToc:
  entry("Preface", "index.nim")
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

# The two BookConfig fields that select a theme. nimibook's inline script picks
# between them with `prefers-color-scheme`, and localStorage overrides.
book.default_theme = "lituus-light"
book.preferred_dark_theme = "lituus-dark"
book.theme_option = {"lituus-light": "Light", "lituus-dark": "Dark"}.toTable

# From the theme package, not from a path beside this checkout: CI checks out
# one repository. Without it nimibook ships nimib's default, a whale emoji.
book.favicon_escaped = faviconTag()

nimibookCli(book)
