# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph.nim
## Main module for the UniGraph library
## A generic, pedagogical graph data structure library for Nim
##
## Features:
## - Multiple kernel backends (List, Matrix, CSR)
## - Zero-cost abstractions via compile-time generics
## - Stable vertex indices (Petgraph pattern)
## - Immutability by default (ARC/ORC)
## - Pedagogical tracing via Visitor pattern

import UniGraph/types
import UniGraph/kernel_concept
import UniGraph/kernels/list_kernel
import UniGraph/kernels/matrix_kernel
import UniGraph/kernels/csr_kernel
import UniGraph/kernels/seq_kernel
import UniGraph/graph
import UniGraph/visitor
import UniGraph/algorithms/traversals
import UniGraph/algorithms/shortest_path
import UniGraph/algorithms/mst
import UniGraph/algorithms/scc
import UniGraph/algorithms/tsp
import UniGraph/visualize/graph_viz

export kernel_concept
export types, list_kernel, matrix_kernel, csr_kernel, seq_kernel, graph,
    visitor, traversals
export shortest_path, mst, scc, tsp, graph_viz

const Version* = "1.0.0"
const VersionMajor* = 1
const VersionMinor* = 0
const VersionPatch* = 0
