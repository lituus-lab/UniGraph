# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Cross-library benchmark harness: UniGraph side.
##
## Reads the *.edges / tsp/*.tsp fixtures produced by
## ../generate_graphs.py (same files every language harness reads) and
## appends one CSV row per (library, algorithm, graph) run to the path
## given as the second argument. See ../README.md for the file formats,
## the digest values used to cross-check correctness, and why TSP runs a
## standalone nearest-neighbor/2-opt instead of algorithms/tsp.nim (that
## module is edge/kernel-based and quadratic per lookup -- fine for the
## small, explicitly-listed graphs it's documented for, not for a
## thousands-of-cities coordinate instance).
import UniGraph
import std/[os, times, monotimes, strutils, strformat, tables, math, algorithm,
    posix]

type
  GraphData = object
    n, m: int
    directed, weighted: bool
    start: int # precomputed max-degree vertex -- see generate_graphs.py
    edges: seq[(int, int, float)]

proc loadGraph(path: string): GraphData =
  let lines = readFile(path).splitLines()
  let header = lines[0].splitWhitespace()
  result.n = header[0].parseInt()
  result.m = header[1].parseInt()
  result.directed = header[2].parseInt() != 0
  result.weighted = header[3].parseInt() != 0
  result.start = header[4].parseInt()
  result.edges = newSeqOfCap[(int, int, float)](result.m)
  for i in 1..result.m:
    let parts = lines[i].splitWhitespace()
    result.edges.add((parts[0].parseInt(), parts[1].parseInt(), parts[
        2].parseFloat()))

proc buildKernel(g: GraphData): (SeqKernel[int, float], seq[VertexId]) =
  # SeqKernel, not ListKernel: traversals/dijkstra/mst/tarjan are generic
  # over the kernel, and SeqKernel's flat-array neighbors() (no per-lookup
  # hashing) is the fair comparison against petgraph's Vec-backed graph.
  # ListKernel's Table[VertexId, ...] storage costs a hash on every
  # neighbors() call -- see README.md's performance notes. TSP still needs
  # ListKernel specifically (tsp.nim is hard-typed to it).
  var k = newSeqKernel[int, float](g.n)
  var ids = newSeq[VertexId](g.n)
  for i in 0 ..< g.n:
    ids[i] = k.addVertex(i)
  for (u, v, w) in g.edges:
    discard k.addEdge(ids[u], ids[v], w)
    if not g.directed:
      discard k.addEdge(ids[v], ids[u], w)
  (k, ids)

proc weightOf(edge: Edge[float]): float = edge.data

var csvLines: seq[string] = @[]

proc record(lib, algo, graph: string; n, m: int; directed, weighted: bool;
    loadS, algoS: float; digest: string) =
  csvLines.add(&"nim,{lib},{algo},{graph},{n},{m},{int(directed)},{int(weighted)},{loadS:.6f},{algoS:.6f},{digest}")
  stderr.writeLine(&"  {lib}/{algo} on {graph}: load={loadS:.3f}s algo={algoS:.3f}s digest={digest}")

template timeSeconds(body: untyped): float =
  let t0 = getMonoTime()
  body
  (getMonoTime() - t0).inNanoseconds.float / 1_000_000_000.0

proc runGraphBenchmarks(path, name: string) =
  stderr.writeLine("Graph: " & name)
  var g: GraphData
  let loadS = timeSeconds:
    g = loadGraph(path)
  var kernel: SeqKernel[int, float]
  var ids: seq[VertexId]
  let buildS = timeSeconds:
    (kernel, ids) = buildKernel(g)
  let totalLoadS = loadS + buildS
  let start = ids[g.start]

  block:
    # trace = false: the benchmark reads getVisitOrder().len, not the
    # formatted step-by-step trace or edge classifications, so there's no
    # reason to pay for building them (see newVisitor's doc comment).
    var visitor = newVisitor[float](trace = false)
    let algoS = timeSeconds:
      kernel.bfs(start, visitor)
    record("unigraph", "bfs", name, g.n, g.m, g.directed, g.weighted,
        totalLoadS, algoS, $visitor.getVisitOrder().len)

  block:
    # dfsIterative, not dfs: the recursive dfs()/dfsVisit() call-stack depth
    # tracks the DFS tree's depth, which can approach the vertex count on a
    # long chain -- a real stack overflow on these fixtures at n=1e6, not a
    # hypothetical one. dfsIterative uses an explicit stack instead and
    # drives the same visitor callbacks, so the digest is unaffected.
    var visitor = newVisitor[float](trace = false)
    let algoS = timeSeconds:
      discard kernel.dfsIterative(start, visitor)
    record("unigraph", "dfs", name, g.n, g.m, g.directed, g.weighted,
        totalLoadS, algoS, $visitor.getVisitOrder().len)

  if g.weighted:
    var distances: Table[VertexId, float]
    let algoS = timeSeconds:
      let r = kernel.dijkstra(start, weightOf)
      distances = r.distances
    var total = 0.0
    for _, d in distances:
      total += d
    record("unigraph", "dijkstra", name, g.n, g.m, g.directed, g.weighted,
        totalLoadS, algoS, formatFloat(total, ffDecimal, 2))

  if not g.directed:
    block:
      var mstEdges: seq[Edge[float]]
      let algoS = timeSeconds:
        mstEdges = kernel.prim(weightOf)
      var total = 0.0
      for e in mstEdges: total += weightOf(e)
      record("unigraph", "mst_prim", name, g.n, g.m, g.directed, g.weighted,
          totalLoadS, algoS, formatFloat(total, ffDecimal, 2))
    block:
      var mstEdges: seq[Edge[float]]
      let algoS = timeSeconds:
        mstEdges = kernel.kruskal(weightOf)
      var total = 0.0
      for e in mstEdges: total += weightOf(e)
      record("unigraph", "mst_kruskal", name, g.n, g.m, g.directed, g.weighted,
          totalLoadS, algoS, formatFloat(total, ffDecimal, 2))

  if g.directed:
    block:
      var comps: seq[seq[VertexId]]
      let algoS = timeSeconds:
        comps = kernel.tarjan()
      record("unigraph", "scc_tarjan", name, g.n, g.m, g.directed, g.weighted,
          totalLoadS, algoS, $comps.len)

# ============================================================================
# TSP: standalone nearest-neighbor / 2-opt on a coordinate distance function.
# Mirrors algorithms/tsp.nim's tspNearestNeighbor / tsp2Opt exactly (same
# candidate scan order, same first-improvement 2-opt loop) so digests are
# directly comparable to the other languages -- see README.md.
# ============================================================================

proc loadCoords(path: string): seq[(float, float)] =
  let lines = readFile(path).splitLines()
  let n = lines[0].strip().parseInt()
  result = newSeqOfCap[(float, float)](n)
  for i in 1..n:
    let parts = lines[i].splitWhitespace()
    result.add((parts[0].parseFloat(), parts[1].parseFloat()))

proc dist(coords: seq[(float, float)]; i, j: int): float =
  let (xi, yi) = coords[i]
  let (xj, yj) = coords[j]
  sqrt((xi - xj) ^ 2 + (yi - yj) ^ 2)

proc tourCost(coords: seq[(float, float)]; path: seq[int]): float =
  for i in 0 ..< path.len - 1:
    result += dist(coords, path[i], path[i + 1])
  result += dist(coords, path[^1], path[0])

proc nearestNeighbor(coords: seq[(float, float)]; start: int): (seq[int], float) =
  let n = coords.len
  var path = @[start]
  var visited = newSeq[bool](n)
  visited[start] = true
  while path.len < n:
    let current = path[^1]
    var best = -1
    var bestDist = Inf
    for v in 0 ..< n:
      if not visited[v]:
        let d = dist(coords, current, v)
        if d < bestDist:
          bestDist = d
          best = v
    visited[best] = true
    path.add(best)
  (path, tourCost(coords, path))

proc twoOpt(coords: seq[(float, float)]; initial: seq[int];
    maxIterations: int): (seq[int], float) =
  var path = initial
  var cost = tourCost(coords, path)
  var improved = true
  var iterations = 0
  while improved and iterations < maxIterations:
    improved = false
    inc iterations
    for i in 0 ..< path.len - 1:
      for j in i + 1 ..< path.len:
        var newPath = path
        var left = i
        var right = j
        while left < right:
          swap(newPath[left], newPath[right])
          inc left
          dec right
        let newCost = tourCost(coords, newPath)
        if newCost < cost:
          cost = newCost
          path = newPath
          improved = true
  (path, cost)

proc runTspBenchmarks(path, name: string) =
  stderr.writeLine("TSP: " & name)
  var coords: seq[(float, float)]
  let loadS = timeSeconds:
    coords = loadCoords(path)
  let n = coords.len

  var nnPath: seq[int]
  var nnCost: float
  let nnS = timeSeconds:
    (nnPath, nnCost) = nearestNeighbor(coords, 0)
  record("unigraph", "tsp_nn", name, n, 0, false, true, loadS, nnS,
      formatFloat(nnCost, ffDecimal, 2))

  var optCost: float
  let optS = timeSeconds:
    (_, optCost) = twoOpt(coords, nnPath, 1000)
  record("unigraph", "tsp_2opt", name, n, 0, false, true, loadS, optS,
      formatFloat(optCost, ffDecimal, 2))

  # Cross-check against the shipped, kernel-based algorithms/tsp.nim on a
  # materialized complete graph -- only for small n: that module scans
  # every vertex per step via kernel.getEdge, so it's cubic here (fine
  # for a few hundred cities, not for thousands).
  if n <= 200:
    var k = newListKernel[int, float]()
    var ids = newSeq[VertexId](n)
    for i in 0 ..< n:
      ids[i] = k.addVertex(i)
    for i in 0 ..< n:
      for j in 0 ..< n:
        if i != j:
          discard k.addEdge(ids[i], ids[j], dist(coords, i, j))
    var kernelR: tuple[path: seq[VertexId]; cost: float]
    let kernelS = timeSeconds:
      kernelR = k.tspNearestNeighbor(ids[0], weightOf)
    record("unigraph-kernel-api", "tsp_nn", name, n, n * (n - 1), false, true,
        loadS, kernelS, formatFloat(kernelR.cost, ffDecimal, 2))

proc runAll() =
  if paramCount() < 2:
    stderr.writeLine("usage: bench_unigraph <data_dir> <output_csv>")
    quit(1)
  let dataDir = paramStr(1)
  let outputCsv = paramStr(2)

  var graphFiles: seq[string] = @[]
  var tspFiles: seq[string] = @[]
  for kind, path in walkDir(dataDir):
    if kind == pcFile and path.endsWith(".edges"):
      graphFiles.add(path)
  for kind, path in walkDir(dataDir / "tsp"):
    if kind == pcFile and path.endsWith(".tsp"):
      tspFiles.add(path)
  graphFiles.sort()
  tspFiles.sort()

  for path in graphFiles:
    runGraphBenchmarks(path, path.extractFilename.changeFileExt(""))
  for path in tspFiles:
    runTspBenchmarks(path, path.extractFilename.changeFileExt(""))

  let writeHeader = not fileExists(outputCsv)
  var f = open(outputCsv, fmAppend)
  defer: f.close()
  if writeHeader:
    f.writeLine("lang,library,algorithm,graph,n,m,directed,weighted,load_seconds,algo_seconds,digest")
  for line in csvLines:
    f.writeLine(line)

proc threadEntryRaw(arg: pointer): pointer {.noconv.} =
  # runAll only ever runs on this one worker thread -- the cast is safe
  # because there's no concurrent access to its global CSV buffer, just a
  # single-threaded run happening to execute off the main thread so it can
  # have a bigger stack than the OS gives that one.
  {.cast(gcsafe).}:
    runAll()
  result = nil

when isMainModule:
  # kernel.tarjan()'s strongconnect recurses per DFS-tree edge; on a
  # directed million-vertex graph the recursion depth can exceed even a
  # 64MB OS stack. std/typedthreads' Thread stack size is a fixed ~2MB
  # constant on desktop targets, so this uses pthread directly for an
  # arbitrary stack size. POSIX only (macOS/Linux).
  var attr: Pthread_attr
  discard pthread_attr_init(addr attr)
  discard pthread_attr_setstacksize(addr attr, 1 shl 30) # 1 GiB
  var tid: Pthread
  if pthread_create(addr tid, addr attr, threadEntryRaw, nil) != 0:
    stderr.writeLine("pthread_create failed -- running on the main thread instead")
    runAll()
  else:
    var res: pointer
    discard pthread_join(tid, addr res)
