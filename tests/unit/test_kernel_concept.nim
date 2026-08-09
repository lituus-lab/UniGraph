# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# UniGraph — GraphKernel concept conformance
# =============================================================================
# All checks run at compile time: this file failing to build means a kernel
# no longer satisfies the contract.

import std/unittest
import ../../src/UniGraph/types
import ../../src/UniGraph/kernel_concept
import ../../src/UniGraph/kernels/list_kernel
import ../../src/UniGraph/kernels/seq_kernel
import ../../src/UniGraph/kernels/csr_kernel
import ../../src/UniGraph/kernels/matrix_kernel

static:
  # every kernel satisfies the contract, for several payload combinations
  doAssert ListKernel[int, float] is GraphKernel[int, float]
  doAssert SeqKernel[int, float] is GraphKernel[int, float]
  doAssert CsrKernel[int, float] is GraphKernel[int, float]
  doAssert MatrixKernel[int, float] is GraphKernel[int, float]
  doAssert ListKernel[string, int] is GraphKernel[string, int]
  doAssert SeqKernel[string, int] is GraphKernel[string, int]
  # types without the kernel API must not satisfy it
  doAssert not (int is GraphKernel[int, float])
  doAssert not (seq[int] is GraphKernel[int, float])

suite "GraphKernel concept":
  test "conformance is established at compile time":
    check true

  test "capacity ignores forged start ids":
    var kernel = newListKernel[int, float]()
    discard kernel.addVertex(1)
    check kernel.capacityFor(newVertexId(-1)) == 1
    check kernel.capacityFor(newVertexId(high(int))) == 1
