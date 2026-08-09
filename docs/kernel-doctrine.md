# The Interchangeable-Kernels Doctrine

> **Algorithms are written once against an explicit concept. Kernels
> implement the concept. Swapping a kernel changes performance and
> guarantees — never the algorithm.**

## The contract in UniGraph

`src/UniGraph/kernel_concept.nim` defines `GraphKernel[V, E]`: vertex and
edge counts, add/get/remove for vertices and edges, `hasEdge`, and
`neighbors` returning the adjacency. Conformance is a compile-time fact:

```nim
static: doAssert CsrKernel[int, float] is GraphKernel[int, float]
```

`tests/unit/test_kernel_concept.nim` asserts this for all four kernels and
several payload types, and asserts that non-kernel types do *not* satisfy
the concept. A kernel that drifts from the contract breaks that file's
build — the error names the contract instead of surfacing as a generic
instantiation failure inside an algorithm.

## Choosing a kernel

| Kernel | Strengths | Costs |
|---|---|---|
| `ListKernel` | cheap insertion/removal, sparse graphs | pointer-chasing on traversal |
| `SeqKernel` | simple, cache-friendly for small graphs | O(n) removals |
| `CsrKernel` | contiguous, cache-friendly traversal of static graphs | mutation requires rebuilds |
| `MatrixKernel` | O(1) `hasEdge`, dense graphs | O(V^2) memory |

`traversals`, `shortest_path`, and `mst` are generic over `K` and never
inspect which kernel they receive. `scc.kosaraju`, all of `tsp`, and
`visualize/graph_viz` accept `ListKernel[V, E]`. `scc.tarjan` and
`scc.findArticulationPoints` are generic.

## Writing a new kernel

1. Provide the procs listed in `GraphKernel` for your type.
2. Add `static: doAssert YourKernel[int, float] is GraphKernel[int, float]`
   to `tests/unit/test_kernel_concept.nim`.
3. Run the algorithm suites against it — they are the behavioral contract;
   the concept is only the structural one.
