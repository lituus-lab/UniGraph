# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## C ABI for UniGraph. Built --app:staticlib/--app:lib --noMain --mm:arc -d:release.
## Keep in sync with include/UniGraph.h; tests/c links the header against this lib.
##
## Monomorphized façade: the generic ImmutableGraph[K,V,E]/MutableGraph[K,V,E]
## API is not C-ABI-shaped, so this exposes exactly one concrete
## instantiation — MutableGraph[ListKernel[int64, float64], int64, float64] —
## a directed-or-undirected, simple (no self-loop/no-parallel-edge) graph
## with an int64 label per vertex and a float64 weight per edge. Vertex
## removal is intentionally NOT exposed here: VertexId's generation counter
## (see types.nim) isn't representable as a plain int64, and every vertex
## created through this API keeps generation 0 as long as nothing is ever
## removed, which is what makes exposing a bare int64 id safe.
import std/[algorithm, math, options, sequtils, tables]
import ./types
import ./kernels/list_kernel
import ./graph
import ./visitor
import ./algorithms/[mst, scc, shortest_path, traversals, tsp]
import ./visualize/graph_viz

type
  UniGraphHandle = MutableGraph[ListKernel[int64, float64], int64, float64]

  UgEdge {.bycopy.} = object
    source: clonglong
    target: clonglong
    weight: cdouble

  UgComponentEntry {.bycopy.} = object
    vertex: clonglong
    component: clonglong

  UgDegreeCount {.bycopy.} = object
    degree: clonglong
    count: clonglong

const UniGraphVersionC: cstring = "1.0.0"

var gInited = false

proc NimMain() {.importc, cdecl.}

proc edgeWeight(edge: Edge[float64]): float = edge.data

proc zeroHeuristic(a, b: VertexId): float =
  discard a
  discard b
  0.0

proc cmpVertexId(a, b: VertexId): int = cmp(a.id, b.id)

proc cmpEdge(a, b: Edge[float64]): int =
  result = cmp(a.source.id, b.source.id)
  if result == 0: result = cmp(a.target.id, b.target.id)

proc cmpEdgeTarget(a, b: Edge[float64]): int = cmp(a.target.id, b.target.id)

proc vertexId(g: UniGraphHandle; raw: clonglong): Option[VertexId] =
  if raw < clonglong(low(int)) or raw > clonglong(high(int)):
    return none(VertexId)
  let id = newVertexId(int(raw))
  if g.getVertex(id).isSome: some(id) else: none(VertexId)

proc sortedIds(ids: openArray[VertexId]): seq[VertexId] =
  result = @ids
  result.sort(cmpVertexId)

proc copyIds(ids: openArray[VertexId]; output: ptr clonglong;
    capacity: csize_t): clonglong =
  if not output.isNil:
    let outp = cast[ptr UncheckedArray[clonglong]](output)
    for i in 0 ..< min(ids.len, int(capacity)):
      outp[i] = clonglong(ids[i].id)
  clonglong(ids.len)

proc copyEdges(edges: openArray[Edge[float64]]; output: ptr UgEdge;
    capacity: csize_t): clonglong =
  if not output.isNil:
    let outp = cast[ptr UncheckedArray[UgEdge]](output)
    for i in 0 ..< min(edges.len, int(capacity)):
      outp[i] = UgEdge(source: clonglong(edges[i].source.id),
          target: clonglong(edges[i].target.id), weight: cdouble(edges[i].data))
  clonglong(edges.len)

proc copyString(value: string; output: ptr char; capacity: csize_t): clonglong =
  if not output.isNil and capacity > 0:
    let outp = cast[ptr UncheckedArray[char]](output)
    let count = min(value.len, int(capacity) - 1)
    for i in 0 ..< count: outp[i] = value[i]
    outp[count] = '\0'
  clonglong(value.len)

# Unmangled C symbols, C calling convention, exported from the shared lib.

# A shared library runs NimMain from DllMain (Windows) or an ELF constructor;
# a static one has neither, so nothing initializes the Nim runtime. The first
# entry point then enters Nim code whose globals were never set up and the
# process faults. The static-library tasks pass -d:staticNoAutoInit; shared
# builds must not, or NimMain runs twice.
when defined(staticNoAutoInit):
  # A once primitive, not a plain flag: two threads reaching an entry point
  # together would both see the flag unset, both call NimMain, and the second
  # would enter Nim code the first had not finished initializing. The platform
  # primitives block the losers until the winner returns, which a flag cannot.
  #
  # C statics, not Nim globals: module initialization would reset a Nim one and
  # NimMain would run again. NimMain is declared here too — the generated
  # prototype comes after this section.
  {.emit: """/*VARSECTION*/
void NimMain(void);
#ifdef _WIN32
#  include <windows.h>
static INIT_ONCE ug_runtime_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK ug_runtime_init(PINIT_ONCE o, PVOID p, PVOID *c) {
  (void)o; (void)p; (void)c; NimMain(); return TRUE;
}
static void ug_runtime_ensure(void) {
  InitOnceExecuteOnce(&ug_runtime_once, ug_runtime_init, NULL, NULL);
}
#else
#  include <pthread.h>
static pthread_once_t ug_runtime_once = PTHREAD_ONCE_INIT;
static void ug_runtime_init(void) { NimMain(); }
static void ug_runtime_ensure(void) {
  pthread_once(&ug_runtime_once, ug_runtime_init);
}
#endif
""".}
  template ensureRuntime() =
    {.emit: "  ug_runtime_ensure();".}
else:
  template ensureRuntime() = discard


{.push exportc, cdecl, dynlib.}

proc ug_init(): cint =
  ensureRuntime()
  if not gInited:
    NimMain()
    gInited = true
  1

proc ug_version(): cstring =
  ## Static version string; do not free.
  ensureRuntime()
  UniGraphVersionC

proc ug_graph_new(directed: cint): pointer =
  ## Create a new graph. directed != 0 -> Directed, else Undirected.
  ## The foreign instantiation is always Simple: no self-loops or parallel
  ## edges.
  ensureRuntime()
  try:
    let dir = if directed != 0: Directed else: Undirected
    let g = newMutableGraph[int64, float64](direction = dir)
    GC_ref(g)
    cast[pointer](g)
  except Exception, Defect:
    nil

proc ug_graph_free(handle: pointer) =
  ## Release a graph created by ug_graph_new. Never call twice on the same
  ## handle, and never use the handle again afterwards.
  ensureRuntime()
  if handle.isNil:
    return
  var g = cast[UniGraphHandle](handle)
  GC_unref(g)

proc ug_graph_vertex_count(handle: pointer): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    clonglong(g.vertexCount)
  except Exception, Defect:
    -1

proc ug_graph_edge_count(handle: pointer): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    clonglong(g.edgeCount)
  except Exception, Defect:
    -1

proc ug_graph_add_vertex(handle: pointer; data: clonglong): clonglong =
  ## Add a vertex carrying `data` as its label. Returns the new vertex's id
  ## (stable for the lifetime of this handle — no removal is exposed).
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.addVertex(int64(data))
    clonglong(id.id)
  except Exception, Defect:
    -1

proc ug_graph_get_vertex_data(
    handle: pointer; vertexId: clonglong; outData: ptr clonglong
): cint =
  ## Write the vertex's label into outData and return 1, or return 0 (leaving
  ## outData untouched) if the vertex doesn't exist. Returns int (not Nim bool)
  ## to match the C ABI in include/UniGraph.h — a one-byte bool return would
  ## leave three bytes of the int return register undefined for C callers.
  ensureRuntime()
  if handle.isNil or outData.isNil: return 0
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(vertexId)
    if id.isNone: return 0
    let v = g.getVertex(id.get())
    outData[] = clonglong(v.get().data)
    1
  except Exception, Defect:
    0

proc ug_graph_add_edge(
    handle: pointer; source, target: clonglong; weight: cdouble
): cint =
  ## Add an edge. Returns 0 for a self-loop, a duplicate edge, or a
  ## non-existent endpoint — never raises. Returns int to match the C ABI.
  ensureRuntime()
  if handle.isNil: return 0
  try:
    let g = cast[UniGraphHandle](handle)
    let s = g.vertexId(source)
    let t = g.vertexId(target)
    if s.isNone or t.isNone: return 0
    if g.addEdge(s.get(), t.get(), float64(weight)): 1 else: 0
  except Exception, Defect:
    0

proc ug_graph_has_edge(handle: pointer; source, target: clonglong): cint =
  ensureRuntime()
  if handle.isNil: return 0
  try:
    let g = cast[UniGraphHandle](handle)
    let s = g.vertexId(source)
    let t = g.vertexId(target)
    if s.isNone or t.isNone: return 0
    if g.hasEdge(s.get(), t.get()): 1 else: 0
  except Exception, Defect:
    0

proc ug_graph_get_edge_weight(
    handle: pointer; source, target: clonglong; outWeight: ptr cdouble
): cint =
  ## Write the edge's weight into outWeight and return 1, or return 0 (leaving
  ## outWeight untouched) if the edge doesn't exist. Returns int per the C ABI.
  ensureRuntime()
  if handle.isNil or outWeight.isNil: return 0
  try:
    let g = cast[UniGraphHandle](handle)
    let s = g.vertexId(source)
    let t = g.vertexId(target)
    if s.isNone or t.isNone: return 0
    let e = g.getEdge(s.get(), t.get())
    if e.isNone: return 0
    outWeight[] = cdouble(e.get())
    1
  except Exception, Defect:
    0

proc ug_graph_remove_edge(handle: pointer; source, target: clonglong): cint =
  ensureRuntime()
  if handle.isNil: return 0
  try:
    let g = cast[UniGraphHandle](handle)
    let s = g.vertexId(source)
    let t = g.vertexId(target)
    if s.isNone or t.isNone: return 0
    if g.removeEdge(s.get(), t.get()): 1 else: 0
  except Exception, Defect:
    0

proc ug_graph_vertices(handle: pointer; output: ptr clonglong;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    var ids: seq[VertexId]
    for vertex in g.kernel.vertices(): ids.add vertex.id
    copyIds(sortedIds(ids), output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_edges(handle: pointer; output: ptr UgEdge;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    var edges = toSeq(g.kernel.edges())
    edges.sort(cmpEdge)
    copyEdges(edges, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_neighbors(handle: pointer; vertex: clonglong; output: ptr UgEdge;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(vertex)
    if id.isNone: return -1
    var edges = g.kernel.neighbors(id.get)
    edges.sort(cmpEdgeTarget)
    copyEdges(edges, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_in_neighbors(handle: pointer; vertex: clonglong;
    output: ptr UgEdge; capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(vertex)
    if id.isNone: return -1
    var edges = g.kernel.inNeighbors(id.get)
    edges.sort(cmpEdge)
    copyEdges(edges, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_out_neighbors(handle: pointer; vertex: clonglong;
    output: ptr UgEdge; capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(vertex)
    if id.isNone: return -1
    var edges = g.kernel.outNeighbors(id.get)
    edges.sort(cmpEdge)
    copyEdges(edges, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_bfs(handle: pointer; start: clonglong; output: ptr clonglong;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(start)
    if id.isNone: return -1
    let order = bfsIterative(g.kernel, id.get, newVisitor[float64](false))
    copyIds(order, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_dfs(handle: pointer; start: clonglong; output: ptr clonglong;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(start)
    if id.isNone: return -1
    let order = dfsIterative(g.kernel, id.get, newVisitor[float64](false))
    copyIds(order, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_is_connected(handle: pointer): cint =
  ensureRuntime()
  if handle.isNil: return 0
  try:
    let g = cast[UniGraphHandle](handle)
    let connected = if g.direction == Directed:
      g.kernel.tarjan.len <= 1
    else:
      g.kernel.isConnectedUndirected
    if connected: 1 else: 0
  except Exception, Defect:
    0

proc ug_graph_reachable(handle: pointer; start: clonglong;
    output: ptr clonglong; capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(start)
    if id.isNone: return -1
    copyIds(sortedIds(reachableVertices(g.kernel, id.get)), output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_dijkstra(handle: pointer; start: clonglong;
    outVertices: ptr clonglong; outDistances: ptr cdouble;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(start)
    if id.isNone: return -1
    let (distances, _) = dijkstra(g.kernel, id.get, edgeWeight)
    var ids: seq[VertexId]
    for vertex in distances.keys: ids.add vertex
    ids = sortedIds(ids)
    if not outVertices.isNil and not outDistances.isNil:
      let vp = cast[ptr UncheckedArray[clonglong]](outVertices)
      let dp = cast[ptr UncheckedArray[cdouble]](outDistances)
      for i in 0 ..< min(ids.len, int(capacity)):
        vp[i] = clonglong(ids[i].id)
        dp[i] = cdouble(distances[ids[i]])
    clonglong(ids.len)
  except Exception, Defect:
    -1

proc ug_graph_shortest_path(handle: pointer; start, goal: clonglong;
    output: ptr clonglong; capacity: csize_t; outCost: ptr cdouble): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let s = g.vertexId(start)
    let t = g.vertexId(goal)
    if s.isNone or t.isNone: return -1
    let (distances, parents) = dijkstra(g.kernel, s.get, edgeWeight)
    if t.get notin distances: return 0
    if not outCost.isNil: outCost[] = cdouble(distances[t.get])
    copyIds(reconstructPath(parents, t.get), output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_a_star(handle: pointer; start, goal: clonglong;
    output: ptr clonglong; capacity: csize_t): clonglong =
  ## Zero-heuristic A* exposes the algorithm without an unsafe foreign callback.
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let s = g.vertexId(start)
    let t = g.vertexId(goal)
    if s.isNone or t.isNone: return -1
    let path = aStar(g.kernel, s.get, t.get, edgeWeight, zeroHeuristic)
    copyIds(path, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_bellman_ford(handle: pointer; start: clonglong;
    outVertices: ptr clonglong; outDistances: ptr cdouble; capacity: csize_t;
    outNegativeCycle: ptr cint): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(start)
    if id.isNone: return -1
    let found = bellmanFord(g.kernel, id.get, edgeWeight)
    if not outNegativeCycle.isNil:
      outNegativeCycle[] = if found.hasNegativeCycle: 1 else: 0
    var ids: seq[VertexId]
    for vertex, distance in found.distances:
      if distance != Inf: ids.add vertex
    ids = sortedIds(ids)
    if not outVertices.isNil and not outDistances.isNil:
      let vp = cast[ptr UncheckedArray[clonglong]](outVertices)
      let dp = cast[ptr UncheckedArray[cdouble]](outDistances)
      for i in 0 ..< min(ids.len, int(capacity)):
        vp[i] = clonglong(ids[i].id)
        dp[i] = cdouble(found.distances[ids[i]])
    clonglong(ids.len)
  except Exception, Defect:
    -1

proc ug_graph_prim(handle: pointer; output: ptr UgEdge;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    if g.direction != Undirected: return -1
    copyEdges(prim(g.kernel, edgeWeight), output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_kruskal(handle: pointer; output: ptr UgEdge;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    if g.direction != Undirected: return -1
    copyEdges(kruskal(g.kernel, edgeWeight), output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_scc(handle: pointer; output: ptr UgComponentEntry;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    var entries: seq[UgComponentEntry]
    for component, vertices in tarjan(g.kernel):
      for vertex in sortedIds(vertices):
        entries.add UgComponentEntry(vertex: clonglong(vertex.id),
            component: clonglong(component))
    if not output.isNil:
      let outp = cast[ptr UncheckedArray[UgComponentEntry]](output)
      for i in 0 ..< min(entries.len, int(capacity)): outp[i] = entries[i]
    clonglong(entries.len)
  except Exception, Defect:
    -1

proc ug_graph_kosaraju(handle: pointer; output: ptr UgComponentEntry;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    var entries: seq[UgComponentEntry]
    for component, vertices in kosaraju(g.kernel):
      for vertex in sortedIds(vertices):
        entries.add UgComponentEntry(vertex: clonglong(vertex.id),
            component: clonglong(component))
    if not output.isNil:
      let outp = cast[ptr UncheckedArray[UgComponentEntry]](output)
      for i in 0 ..< min(entries.len, int(capacity)): outp[i] = entries[i]
    clonglong(entries.len)
  except Exception, Defect:
    -1

proc ug_graph_articulation_points(handle: pointer; output: ptr clonglong;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    if g.direction != Undirected: return -1
    copyIds(sortedIds(findArticulationPoints(g.kernel)), output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_tsp_naive(handle: pointer; output: ptr clonglong;
    capacity: csize_t; outCost: ptr cdouble): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let tour = tspNaive(g.kernel, edgeWeight)
    if not outCost.isNil: outCost[] = cdouble(tour.cost)
    copyIds(tour.path, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_tsp_2opt(handle: pointer; maxIterations: clonglong;
    output: ptr clonglong; capacity: csize_t;
    outCost: ptr cdouble): clonglong =
  ensureRuntime()
  if handle.isNil or maxIterations < 0: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    if maxIterations < 0 or maxIterations > clonglong(high(int)): return -1
    let tour = tsp2Opt(g.kernel, edgeWeight, maxIterations = int(maxIterations))
    if not outCost.isNil: outCost[] = cdouble(tour.cost)
    copyIds(tour.path, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_tsp_nearest(handle: pointer; start: clonglong;
    output: ptr clonglong; capacity: csize_t;
    outCost: ptr cdouble): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let id = g.vertexId(start)
    if id.isNone: return -1
    let tour = tspNearestNeighbor(g.kernel, id.get, edgeWeight)
    if not outCost.isNil: outCost[] = cdouble(tour.cost)
    var path = tour.path
    if path.len > 1 and path[0] == path[^1]:
      path.setLen(path.len - 1)
    copyIds(path, output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_to_ascii(handle: pointer; output: ptr char;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    copyString(toAscii(g.kernel), output, capacity)
  except Exception, Defect:
    -1

proc ug_graph_to_dot(handle: pointer; output: ptr char;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    copyString(toDot(g.kernel, directed = g.direction == Directed), output,
        capacity)
  except Exception, Defect:
    -1

proc ug_graph_degree_distribution(handle: pointer; output: ptr UgDegreeCount;
    capacity: csize_t): clonglong =
  ensureRuntime()
  if handle.isNil: return -1
  try:
    let g = cast[UniGraphHandle](handle)
    let distribution = degreeDistribution(g.kernel)
    if not output.isNil:
      let outp = cast[ptr UncheckedArray[UgDegreeCount]](output)
      for i in 0 ..< min(distribution.len, int(capacity)):
        outp[i] = UgDegreeCount(degree: clonglong(distribution[i].degree),
            count: clonglong(distribution[i].count))
    clonglong(distribution.len)
  except Exception, Defect:
    -1

{.pop.}
