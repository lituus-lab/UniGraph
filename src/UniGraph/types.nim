# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/types.nim
## Core type definitions for the UniGraph library
##
## This module defines the fundamental types:
## - VertexId: Unique vertex identifier with generation counter for stability
## - `Vertex[V]`: A vertex carrying generic data of type V
## - `Edge[E]`: An edge carrying generic data/weight of type E
## - `Graph[K, V, E]`: The main graph structure
## - Direction: Enum for Directed/Undirected graphs
## - GraphType: Enum for Simple/Multi/Pseudo graphs

import std/hashes

# ============================================================================
# VertexId: Stable vertex identifier
# ============================================================================

type
  VertexId* = object
    ## Unique identifier for a vertex within a graph.
    ## Uses a generation counter to prevent dangling references after vertex removal
    ## (StableGraph pattern from Petgraph).
    id*: int
    generation*: uint16

proc `==`*(a, b: VertexId): bool {.inline.} =
  ## Check if two VertexIds are equal
  a.id == b.id and a.generation == b.generation

proc `<`*(a, b: VertexId): bool {.inline.} =
  ## Compare two VertexIds (useful for sorting or tie-breaking)
  if a.id == b.id:
    a.generation < b.generation
  else:
    a.id < b.id

proc `<=`*(a, b: VertexId): bool {.inline.} =
  a == b or a < b

proc `>=`*(a, b: VertexId): bool {.inline.} =
  b <= a

proc hash*(v: VertexId): Hash =
  ## Hash function for VertexId (enables use in tables/sets)
  hash((v.id, v.generation))

proc newVertexId*(id: int, generation: uint16 = 0'u16): VertexId {.inline.} =
  ## Create a new VertexId with the given id and generation
  VertexId(id: id, generation: generation)

# ============================================================================
# Vertex[V]: Generic vertex type
# ============================================================================

type
  Vertex*[V] = object
    ## A vertex in the graph carrying user-defined data of type V.
    ## V is unconstrained: any type, not just numeric ones.
    id*: VertexId
    data*: V

proc newVertex*[V](id: VertexId, data: V): Vertex[V] {.inline.} =
  ## Create a new vertex with the given id and data
  Vertex[V](id: id, data: data)

# ============================================================================
# Edge[E]: Generic edge type
# ============================================================================

type
  Edge*[E] = object
    ## A connection between two vertices carrying user-defined data/weight of type E.
    ## For SimpleGraph: source != target (no self-loops) and no duplicate edges.
    source*: VertexId
    target*: VertexId
    data*: E

proc newEdge*[E](source, target: VertexId, data: E): Edge[E] {.inline.} =
  ## Create a new edge with the given source, target, and data
  Edge[E](source: source, target: target, data: data)

# ============================================================================
# Direction: Graph direction enum
# ============================================================================

type
  Direction* = enum
    Directed = 0,  ## Edge from source to target only
    Undirected = 1 ## Edge mirrored (both directions)

# ============================================================================
# GraphType: Graph type variants enum
# ============================================================================

type
  GraphType* = enum
    Simple = 0, ## No self-loops, no parallel edges (default, safest)
    Multi = 1,  ## Allows parallel edges between same vertices
    Pseudo = 2  ## Allows both self-loops and parallel edges

# The user-facing Graph[K, V, E] wrapper (generic over any kernel K) lives in
# graph.nim, next to the kernel constructors it depends on. It carries no
# separate `metadata` table: the kernel is already the single source of truth
# for vertex/edge data.
