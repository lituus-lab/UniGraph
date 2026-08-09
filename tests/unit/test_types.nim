# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## tests/unit/test_types.nim
## Unit tests for core type definitions

import unittest
import ../../src/UniGraph/types

suite "VertexId Tests":
  test "VertexId creation":
    let vid = newVertexId(42, 0'u16)
    check vid.id == 42
    check vid.generation == 0'u16

  test "VertexId equality":
    let v1 = newVertexId(1, 0'u16)
    let v2 = newVertexId(1, 0'u16)
    let v3 = newVertexId(1, 1'u16)
    let v4 = newVertexId(2, 0'u16)

    check v1 == v2
    check v1 != v3 # Different generation
    check v1 != v4 # Different id

  test "VertexId with generation":
    let v1 = newVertexId(0, 0'u16)
    let v2 = newVertexId(0, 1'u16)
    check v1 != v2 # Same id, different generation

suite "Vertex Tests":
  test "Vertex creation with int data":
    let vid = newVertexId(1, 0'u16)
    let vertex = newVertex(vid, 42)
    check vertex.id == vid
    check vertex.data == 42

  test "Vertex creation with float data":
    let vid = newVertexId(1, 0'u16)
    let vertex = newVertex(vid, 3.14)
    check vertex.data == 3.14

suite "Edge Tests":
  test "Edge creation":
    let source = newVertexId(1, 0'u16)
    let target = newVertexId(2, 0'u16)
    let edge = newEdge(source, target, 1.5)

    check edge.source == source
    check edge.target == target
    check edge.data == 1.5

suite "Direction and GraphType Tests":
  test "Direction enum values":
    check ord(Directed) == 0
    check ord(Undirected) == 1
    check Directed != Undirected

  test "GraphType enum values":
    check ord(Simple) == 0
    check ord(Multi) == 1
    check ord(Pseudo) == 2
    check Simple != Multi
    check Simple != Pseudo
