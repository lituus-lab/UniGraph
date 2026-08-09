# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Regression tests for graph_viz DOT emission: undirected edges must emit
## exactly one statement per edge (no dangling label/terminator fragments for
## the reverse mirror), and labels must be DOT-escaped.

import std/[unittest, strutils, sequtils]
import ../../src/UniGraph/types
import ../../src/UniGraph/kernels/list_kernel
import ../../src/UniGraph/visualize/graph_viz

suite "toDot - undirected edge emission":
  test "reverse mirror emits nothing (no dangling label/semicolon)":
    var k = newListKernel[string, float]()
    let a = k.addVertex("A")
    let b = k.addVertex("B")
    discard k.addEdge(a, b, 5.0)

    let dot = k.toDot(directed = false, labelVertices = false)

    # Exactly one undirected edge statement for the single edge.
    check dot.count("--") == 1
    # No dangling label fragment without a preceding edge statement.
    check dot.contains("0 -- 1") or dot.contains("1 -- 0")
    # Each edge statement ends with its own terminator; no stray lines.
    let edgeLines = dot.splitLines().filterIt(it.contains("--"))
    check edgeLines.len == 1
    check edgeLines[0].strip().endsWith(";")

  test "directed edges both emit (no mirror skipping)":
    var k = newListKernel[string, float]()
    let a = k.addVertex("A")
    let b = k.addVertex("B")
    discard k.addEdge(a, b, 5.0)
    discard k.addEdge(b, a, 5.0)

    let dot = k.toDot(directed = true, labelVertices = false)
    check dot.count("->") == 2

  test "undirected self-loop is emitted once":
    var k = newListKernel[string, float]()
    k.graphType = Pseudo
    let a = k.addVertex("A")
    check k.addEdge(a, a, 5.0)

    let dot = k.toDot(directed = false, labelVertices = false)
    check dot.count("0 -- 0") == 1

suite "toDot - label escaping":
  test "vertex data with quote and backslash is escaped":
    var k = newListKernel[string, float]()
    discard k.addVertex("he said \"hi\"\\n")
    let dot = k.toDot(directed = true, labelVertices = true)
    # The raw quote/backslash must not appear unescaped inside the label.
    check dot.contains("\\\"hi\\\"")
    check dot.contains("\\\\")

  test "edge label is escaped":
    var k = newListKernel[string, string]()
    let a = k.addVertex("A")
    let b = k.addVertex("B")
    discard k.addEdge(a, b, "w\"x")
    let dot = k.toDot(directed = true, labelVertices = false)
    check dot.contains("label=\"w\\\"x\"")
