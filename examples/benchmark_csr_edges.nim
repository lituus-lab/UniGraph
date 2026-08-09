# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## examples/benchmark_csr_edges.nim
## Performance oracle for the CsrKernel.edges() fix.
##
## The iterator used to re-scan every vertex's row for every single edge
## (O(V*E)) instead of walking each row once (O(V+E)). This benchmark builds
## the same fixed-out-degree graph at several sizes and times the FIXED
## iterator (from src/UniGraph) side by side with a literal copy of the OLD
## row-rescanning approach, so the speedup is measured, not just claimed.
##
## Run: nimble benchmark

import std/[monotimes, times, strformat]
import ../src/UniGraph/types
import ../src/UniGraph/kernels/csr_kernel

const OutDegree = 4 ## fixed out-degree per vertex, so E stays proportional to V

proc buildGraph(vertexCount: int): CsrKernel[int, float] =
  result = newCsrKernel[int, float]()
  var ids = newSeq[VertexId](vertexCount)
  for i in 0 ..< vertexCount:
    ids[i] = result.addVertex(i)
  for i in 0 ..< vertexCount:
    for k in 1 .. OutDegree:
      let j = (i + k) mod vertexCount
      if j != i:
        discard result.addEdge(ids[i], ids[j], 1.0)
  result.build()

proc oldEdgesCount(kernel: CsrKernel[int, float]): tuple[count, checksum: int] =
  ## Literal copy of the pre-fix iterator body: for every edge, re-scan
  ## every row from the start to find which vertex owns it. O(V*E).
  for i in 0 ..< kernel.colIndices.len:
    var sourceId = 0
    for j in 0 ..< kernel.vertices.len:
      if kernel.rowOffsets[j] <= i and i < kernel.rowOffsets[j + 1]:
        sourceId = j
        break
    inc result.count
    result.checksum += sourceId

proc newEdgesCount(kernel: CsrKernel[int, float]): tuple[count, checksum: int] =
  for e in kernel.edges():
    inc result.count
    result.checksum += e.source.id

proc timeIt(body: proc()): float =
  let start = getMonoTime()
  body()
  (getMonoTime() - start).inMicroseconds.float / 1000.0 # milliseconds

when isMainModule:
  echo "CsrKernel.edges(): O(V+E) fix vs the old O(V*E) row-rescan"
  echo "=========================================================="
  echo "  vertices      edges     old (ms)   fixed (ms)    speedup"

  for vertexCount in [500, 1_000, 2_000, 4_000]:
    let kernel = buildGraph(vertexCount)
    let edgeCount = kernel.edgeCount()

    var oldTotal: tuple[count, checksum: int]
    var newTotal: tuple[count, checksum: int]
    var oldMs = Inf
    var newMs = Inf
    for _ in 0 ..< 3:
      oldMs = min(oldMs, timeIt(proc() = oldTotal = kernel.oldEdgesCount()))
      newMs = min(newMs, timeIt(proc() = newTotal = kernel.newEdgesCount()))

    doAssert oldTotal == newTotal
    let speedup = if newMs > 0: oldMs / newMs else: 0.0
    echo &"{vertexCount:>10} {edgeCount:>10} {oldMs:>12.3f} {newMs:>12.3f} {speedup:>9.1f}x"

  echo ""
  echo "Expected shape: 'fixed (ms)' roughly doubles when vertices double" &
       " (linear, O(V+E)); 'old (ms)' grows much faster (quadratic, O(V*E))," &
       " so 'speedup' should climb with graph size."
