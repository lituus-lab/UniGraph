# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGraph/visitor.nim
## Visitor pattern for observing graph traversal execution
##
## This module defines the Visitor interface that receives notifications
## during algorithm traversal, enabling pedagogical step-by-step tracing.
##
## Constitution Principle V: Pedagogy Through Transparency
## Every algorithm MUST expose its execution steps for education.

import types
import std/[strformat, tables]
export tables # Table[VertexId, int] appears in Visitor's public fields;
              # re-exporting avoids a late-bound-symbol lookup failure in
              # any caller that doesn't `import std/tables` itself.

type
  EdgeKind* = enum
    ## Classic DFS edge classification (CLRS). Computed from the visitor's
    ## own discovery/finish bookkeeping, so it needs no help from the
    ## traversal algorithm itself.
    ##
    ## - `ekTree`: target was undiscovered when the edge was traversed.
    ## - `ekBack`: target is discovered but not yet finished, i.e. an
    ##   ancestor still on the current traversal stack.
    ## - `ekForward`: target is already finished and was discovered *after*
    ##   the source (a descendant reached again via a shortcut edge).
    ## - `ekCross`: target is already finished and was discovered *before*
    ##   the source (no ancestor/descendant relationship).
    ##
    ## `bfs`/`bfsIterative` never call `onFinish`, so `finished`/`finishTime`
    ## stay empty for them: every non-tree edge they report classifies as
    ## `ekBack` here, since "finished" is undefined without it. Only
    ## `dfs`/`dfsIterative` (which do call `onFinish`) can produce
    ## `ekForward`/`ekCross`.
    ekTree, ekBack, ekForward, ekCross

  Visitor*[E] = ref object
    ## Visitor for observing traversal execution.
    ## Captures vertex visits, edge traversals, and state changes.
    trace*: seq[string] # Execution trace log
    visitOrder*: seq[VertexId] # Order of vertex visits
    currentStep*: int # Current step number
    discovered*: seq[VertexId] # Discovery order
    finished*: seq[VertexId] # Finish order (for DFS)
    edgeTraversals*: seq[tuple[source: VertexId, target: VertexId, edgeData: E]]
    edgeClassifications*: seq[tuple[source: VertexId, target: VertexId,
        kind: EdgeKind]]
    discoveryTime*: Table[VertexId, int] # CLRS d[v]
    finishTime*: Table[VertexId, int] # CLRS f[v]
    clock: int # Shared counter behind discoveryTime/finishTime
    traceEnabled: bool # See newVisitor's `trace` parameter.

proc newVisitor*[E](trace: bool = true): Visitor[E] =
  ## Create a new visitor for capturing execution traces.
  ##
  ## `trace = false` skips the formatted `trace` log, `edgeClassifications`,
  ## and the discoveryTime/finishTime bookkeeping they're computed from --
  ## `visitOrder`/`discovered`/`finished`/`edgeTraversals` are still filled
  ## in either way. Formatting a trace line and updating two tables on
  ## every single edge is the right default for the small graphs the
  ## pedagogical tracing feature exists for, but it dominates runtime on a
  ## large one; pass `false` when only the traversal result is needed.
  Visitor[E](
    trace: @[],
    visitOrder: @[],
    currentStep: 0,
    discovered: @[],
    finished: @[],
    edgeTraversals: @[],
    edgeClassifications: @[],
    discoveryTime: initTable[VertexId, int](),
    finishTime: initTable[VertexId, int](),
    clock: 0,
    traceEnabled: trace
  )

proc onDiscover*[E](visitor: Visitor[E], vertex: VertexId, order: int) =
  ## Called when a vertex is first discovered during traversal.
  visitor.currentStep += 1
  visitor.visitOrder.add(vertex)
  visitor.discovered.add(vertex)
  if visitor.traceEnabled:
    visitor.discoveryTime[vertex] = visitor.clock
    visitor.clock += 1
    visitor.trace.add(fmt"Step {visitor.currentStep}: Discovered vertex {vertex.id} (order: {order}, time: {visitor.discoveryTime[vertex]})")

proc onFinish*[E](visitor: Visitor[E], vertex: VertexId) =
  ## Called when processing of a vertex is complete (DFS only).
  visitor.currentStep += 1
  visitor.finished.add(vertex)
  if visitor.traceEnabled:
    visitor.finishTime[vertex] = visitor.clock
    visitor.clock += 1
    visitor.trace.add(fmt"Step {visitor.currentStep}: Finished vertex {vertex.id} (time: {visitor.finishTime[vertex]})")

proc classifyEdge[E](visitor: Visitor[E], source, target: VertexId): EdgeKind =
  if target notin visitor.discoveryTime:
    ekTree
  elif target notin visitor.finishTime:
    ekBack
  elif source in visitor.discoveryTime and
      visitor.discoveryTime[target] > visitor.discoveryTime[source]:
    ekForward
  else:
    ekCross

proc onEdge*[E](visitor: Visitor[E], source, target: VertexId, edgeData: E) =
  ## Called when traversing an edge. Classifies the edge (see `EdgeKind`)
  ## using the visitor's own discovery/finish state at the time of the call.
  visitor.currentStep += 1
  visitor.edgeTraversals.add((source: source, target: target,
      edgeData: edgeData))
  if visitor.traceEnabled:
    let kind = classifyEdge(visitor, source, target)
    visitor.edgeClassifications.add((source: source, target: target, kind: kind))
    visitor.trace.add(fmt"Step {visitor.currentStep}: Traversed edge {source.id} -> {target.id} ({kind})")

proc getTrace*[E](visitor: Visitor[E]): seq[string] =
  ## Get the execution trace as a sequence of strings.
  visitor.trace

proc getVisitOrder*[E](visitor: Visitor[E]): seq[VertexId] =
  ## Get the order of vertex visits.
  visitor.visitOrder

proc printTrace*[E](visitor: Visitor[E]) =
  ## Print the execution trace to stdout.
  for line in visitor.trace:
    echo line

proc clear*[E](visitor: Visitor[E]) =
  ## Clear the visitor state for reuse.
  visitor.trace = @[]
  visitor.visitOrder = @[]
  visitor.currentStep = 0
  visitor.discovered = @[]
  visitor.finished = @[]
  visitor.edgeTraversals = @[]
  visitor.edgeClassifications = @[]
  visitor.discoveryTime.clear()
  visitor.finishTime.clear()
  visitor.clock = 0
