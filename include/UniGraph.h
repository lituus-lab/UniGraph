// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNIGRAPH_H
#define UNIGRAPH_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNIGRAPH_VERSION_MAJOR 1
#define UNIGRAPH_VERSION_MINOR 0
#define UNIGRAPH_VERSION_PATCH 1
#define UNIGRAPH_VERSION "1.0.1"

#define UNIGRAPH_VERSION_AT_LEAST(ma, mi, pa) \
  ((UNIGRAPH_VERSION_MAJOR > (ma)) || \
   (UNIGRAPH_VERSION_MAJOR == (ma) && UNIGRAPH_VERSION_MINOR > (mi)) || \
   (UNIGRAPH_VERSION_MAJOR == (ma) && UNIGRAPH_VERSION_MINOR == (mi) && \
    UNIGRAPH_VERSION_PATCH >= (pa)))

/* This C ABI exposes exactly one concrete graph instantiation:
 * MutableGraph[ListKernel[int64, float64], int64, float64] — a directed-or-
 * undirected, simple (no self-loops, no parallel edges) graph with an
 * int64 label per vertex and a float64 weight per edge. The full generic
 * Nim API (any vertex/edge type, any kernel) is not C-ABI-shaped; see
 * src/UniGraph/c_api.nim for why. There is no vertex removal here: exposing
 * it would require representing VertexId's generation counter, not just its
 * raw integer id, at the C boundary. */

/* Opaque handle. Always check for NULL from ug_graph_new; never dereference. */
typedef void *UniGraphHandle;

typedef struct UgEdge {
  long long source;
  long long target;
  double weight;
} UgEdge;

typedef struct UgComponentEntry {
  long long vertex;
  long long component;
} UgComponentEntry;

typedef struct UgDegreeCount {
  long long degree;
  long long count;
} UgDegreeCount;

/* Initialize the Nim runtime. Call exactly once before any other function.
 * Repeated calls are harmless. Returns 1 on success. */
int ug_init(void);

/* Static version string; do not free. */
const char *ug_version(void);

/* Create a new graph. directed != 0 -> Directed, else Undirected. Always
 * Simple (no self-loops, no parallel edges). Returns NULL on allocation
 * failure. Free with ug_graph_free exactly once. */
UniGraphHandle ug_graph_new(int directed);

/* Release a graph created by ug_graph_new. Safe to call with NULL (no-op).
 * Never call twice on the same handle, never use the handle afterwards. */
void ug_graph_free(UniGraphHandle handle);

/* Counts return -1 for a NULL handle. */
long long ug_graph_vertex_count(UniGraphHandle handle);
long long ug_graph_edge_count(UniGraphHandle handle);

/* Add a vertex carrying `data` as its label. Returns the new vertex's id
 * (stable for the lifetime of this handle — no removal is exposed). */
long long ug_graph_add_vertex(UniGraphHandle handle, long long data);

/* Write the vertex's label into *out_data and return 1, or return 0
 * (leaving *out_data untouched) if the vertex doesn't exist. */
int ug_graph_get_vertex_data(UniGraphHandle handle, long long vertex_id,
                              long long *out_data);

/* Add an edge. Returns 0 for a self-loop, a duplicate edge, or a
 * non-existent endpoint — never aborts the process. */
int ug_graph_add_edge(UniGraphHandle handle, long long source,
                       long long target, double weight);

int ug_graph_has_edge(UniGraphHandle handle, long long source,
                       long long target);

/* Write the edge's weight into *out_weight and return 1, or return 0
 * (leaving *out_weight untouched) if the edge doesn't exist. */
int ug_graph_get_edge_weight(UniGraphHandle handle, long long source,
                              long long target, double *out_weight);
int ug_graph_remove_edge(UniGraphHandle handle, long long source,
                         long long target);

/* Buffer-returning functions return the required element count. Pass NULL and
 * capacity 0 to measure, allocate that many elements, then call again. They
 * copy at most capacity elements and return -1 for an invalid argument. */
long long ug_graph_vertices(UniGraphHandle handle, long long *output,
                            size_t capacity);
long long ug_graph_edges(UniGraphHandle handle, UgEdge *output,
                         size_t capacity);
/* Undirected graphs store both arcs, so this returns two UgEdge records per
 * user-visible edge while ug_graph_edge_count counts it once. */
long long ug_graph_neighbors(UniGraphHandle handle, long long vertex,
                             UgEdge *output, size_t capacity);
long long ug_graph_in_neighbors(UniGraphHandle handle, long long vertex,
                                UgEdge *output, size_t capacity);
long long ug_graph_out_neighbors(UniGraphHandle handle, long long vertex,
                                 UgEdge *output, size_t capacity);
long long ug_graph_bfs(UniGraphHandle handle, long long start,
                       long long *output, size_t capacity);
long long ug_graph_dfs(UniGraphHandle handle, long long start,
                       long long *output, size_t capacity);
/* Undirected: ordinary connectivity. Directed: strong connectivity. */
int ug_graph_is_connected(UniGraphHandle handle);
long long ug_graph_reachable(UniGraphHandle handle, long long start,
                             long long *output, size_t capacity);

long long ug_graph_dijkstra(UniGraphHandle handle, long long start,
                            long long *out_vertices, double *out_distances,
                            size_t capacity);
/* Returns 0 when goal is unreachable and leaves out_cost unchanged; callers
 * must not read out_cost in that case. */
long long ug_graph_shortest_path(UniGraphHandle handle, long long start,
                                 long long goal, long long *output,
                                 size_t capacity, double *out_cost);
/* This uses the admissible zero heuristic: it exposes A* without accepting an
 * unsafe foreign callback. */
long long ug_graph_a_star(UniGraphHandle handle, long long start,
                          long long goal, long long *output, size_t capacity);
long long ug_graph_bellman_ford(UniGraphHandle handle, long long start,
                                long long *out_vertices,
                                double *out_distances, size_t capacity,
                                int *out_negative_cycle);

/* MST operations require an undirected graph and return -1 for a directed
 * handle. */
long long ug_graph_prim(UniGraphHandle handle, UgEdge *output,
                        size_t capacity);
long long ug_graph_kruskal(UniGraphHandle handle, UgEdge *output,
                           size_t capacity);
long long ug_graph_scc(UniGraphHandle handle, UgComponentEntry *output,
                       size_t capacity);
long long ug_graph_kosaraju(UniGraphHandle handle, UgComponentEntry *output,
                            size_t capacity);
/* Articulation points require an undirected graph; directed returns -1. */
long long ug_graph_articulation_points(UniGraphHandle handle,
                                       long long *output, size_t capacity);

long long ug_graph_tsp_naive(UniGraphHandle handle, long long *output,
                             size_t capacity, double *out_cost);
long long ug_graph_tsp_2opt(UniGraphHandle handle, long long max_iterations,
                            long long *output, size_t capacity,
                            double *out_cost);
long long ug_graph_tsp_nearest(UniGraphHandle handle, long long start,
                               long long *output, size_t capacity,
                               double *out_cost);

/* String functions return the byte length excluding NUL. Pass NULL/0 to
 * measure. A non-NULL buffer with positive capacity is always NUL-terminated. */
long long ug_graph_to_ascii(UniGraphHandle handle, char *output,
                            size_t capacity);
long long ug_graph_to_dot(UniGraphHandle handle, char *output,
                          size_t capacity);
long long ug_graph_degree_distribution(UniGraphHandle handle,
                                       UgDegreeCount *output,
                                       size_t capacity);

#ifdef __cplusplus
}
#endif

#endif /* UNIGRAPH_H */
