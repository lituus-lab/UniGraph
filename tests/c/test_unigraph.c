// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
// Drift detector: links the header against the built lib. A renamed or
// retyped symbol fails here at compile/link time, not silently at runtime.
#include "UniGraph.h"
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void check_ll(const char *label, long long got, long long want) {
  if (got != want) {
    printf("FAIL %s: got %lld, want %lld\n", label, got, want);
    failures++;
  }
}

static void check_int(const char *label, int got, int want) {
  if (got != want) {
    printf("FAIL %s: got %d, want %d\n", label, got, want);
    failures++;
  }
}

static void check_double(const char *label, double got, double want) {
  if (got != want) {
    printf("FAIL %s: got %f, want %f\n", label, got, want);
    failures++;
  }
}

static void check_str(const char *label, const char *got, const char *want) {
  if (strcmp(got, want) != 0) {
    printf("FAIL %s: got \"%s\", want \"%s\"\n", label, got, want);
    failures++;
  }
}

int main(void) {
  int initialized = ug_init();
  check_int("init", initialized, 1);
  if (initialized != 1) return 1;
  check_str("version", ug_version(), UNIGRAPH_VERSION);

  UniGraphHandle g = ug_graph_new(1 /* directed */);
  check_int("graph_new not null", g != NULL, 1);
  if (g == NULL) return 1;

  long long a = ug_graph_add_vertex(g, 10);
  long long b = ug_graph_add_vertex(g, 20);
  long long c = ug_graph_add_vertex(g, 30);
  check_ll("3 vertices", ug_graph_vertex_count(g), 3);

  long long data = -1;
  check_int("get_vertex_data(a) found", ug_graph_get_vertex_data(g, a, &data), 1);
  check_ll("get_vertex_data(a) value", data, 10);
  check_int("get_vertex_data(bogus) not found",
            ug_graph_get_vertex_data(g, 9999, &data), 0);
  check_ll("failed get_vertex_data preserves output", data, 10);

  check_int("add_edge a->b", ug_graph_add_edge(g, a, b, 1.5), 1);
  check_int("add_edge a->c", ug_graph_add_edge(g, a, c, 2.5), 1);
  check_ll("2 edges", ug_graph_edge_count(g), 2);

  check_int("has_edge a->b", ug_graph_has_edge(g, a, b), 1);
  check_int("directed: no b->a", ug_graph_has_edge(g, b, a), 0);

  double weight = -1.0;
  check_int("get_edge_weight(a,b) found", ug_graph_get_edge_weight(g, a, b, &weight), 1);
  check_double("get_edge_weight(a,b) value", weight, 1.5);
  check_int("get_edge_weight(bogus) not found",
            ug_graph_get_edge_weight(g, a, 9999, &weight), 0);

  check_int("self-loop rejected", ug_graph_add_edge(g, a, a, 0.0), 0);
  check_int("duplicate edge rejected", ug_graph_add_edge(g, a, b, 9.0), 0);

  long long ids[4] = {-1, -1, -1, -1};
  UgEdge edges[4];
  double distances[4];
  int negative_cycle = -1;
  double cost = -1.0;
  char rendered[1024];
  UgComponentEntry components[4];
  UgDegreeCount degrees[4];
  check_ll("vertices required", ug_graph_vertices(g, NULL, 0), 3);
  ids[0] = -1;
  ids[1] = -2;
  check_ll("vertices short buffer required", ug_graph_vertices(g, ids, 1), 3);
  check_ll("vertices short buffer copied first", ids[0], a);
  check_ll("vertices short buffer preserves next slot", ids[1], -2);
  check_ll("vertices copied", ug_graph_vertices(g, ids, 4), 3);
  check_ll("first vertex", ids[0], a);
  check_ll("edges required", ug_graph_edges(g, NULL, 0), 2);
  check_ll("neighbors", ug_graph_neighbors(g, a, edges, 4), 2);
  check_ll("in neighbors", ug_graph_in_neighbors(g, b, edges, 4), 1);
  check_ll("out neighbors", ug_graph_out_neighbors(g, a, edges, 4), 2);
  check_ll("bfs", ug_graph_bfs(g, a, ids, 4), 3);
  check_ll("dfs", ug_graph_dfs(g, a, ids, 4), 3);
  check_ll("reachable", ug_graph_reachable(g, a, ids, 4), 3);
  check_int("directed graph not strongly connected", ug_graph_is_connected(g), 0);
  check_ll("dijkstra", ug_graph_dijkstra(g, a, ids, distances, 4), 3);
  check_ll("shortest path", ug_graph_shortest_path(g, a, b, ids, 4, &cost), 2);
  check_double("shortest cost", cost, 1.5);
  check_ll("a star", ug_graph_a_star(g, a, b, ids, 4), 2);
  check_ll("bellman ford",
           ug_graph_bellman_ford(g, a, ids, distances, 4, &negative_cycle), 3);
  check_int("no negative cycle", negative_cycle, 0);
  check_ll("tarjan entries", ug_graph_scc(g, components, 4), 3);
  check_ll("kosaraju entries", ug_graph_kosaraju(g, components, 4), 3);
  check_ll("directed articulation rejected",
           ug_graph_articulation_points(g, ids, 4), -1);
  check_int("ascii rendered", ug_graph_to_ascii(g, rendered, sizeof rendered) > 0, 1);
  check_int("dot rendered", ug_graph_to_dot(g, rendered, sizeof rendered) > 0, 1);
  check_int("degree distribution",
            ug_graph_degree_distribution(g, degrees, 4) > 0, 1);
  check_int("remove edge", ug_graph_remove_edge(g, a, c), 1);
  check_int("removed edge absent", ug_graph_has_edge(g, a, c), 0);
  check_ll("remove updates edge count", ug_graph_edge_count(g), 1);

  ug_graph_free(g);
  ug_graph_free(NULL); // must be a safe no-op

  UniGraphHandle undirected = ug_graph_new(0);
  check_int("allocate undirected graph", undirected != NULL, 1);
  if (undirected == NULL) return 1;
  long long x = ug_graph_add_vertex(undirected, 1);
  long long y = ug_graph_add_vertex(undirected, 2);
  check_int("add_edge x->y", ug_graph_add_edge(undirected, x, y, 1.0), 1);
  check_int("undirected: y->x mirrored", ug_graph_has_edge(undirected, y, x), 1);
  check_ll("prim", ug_graph_prim(undirected, edges, 4), 1);
  check_ll("kruskal", ug_graph_kruskal(undirected, edges, 4), 1);
  check_ll("undirected articulation points",
           ug_graph_articulation_points(undirected, ids, 4), 0);
  check_ll("tsp naive", ug_graph_tsp_naive(undirected, ids, 4, &cost), 2);
  check_double("tsp naive cost", cost, 2.0);
  check_ll("tsp 2-opt", ug_graph_tsp_2opt(undirected, 10, ids, 4, &cost), 2);
  check_double("tsp 2-opt cost", cost, 2.0);
  check_ll("tsp nearest", ug_graph_tsp_nearest(undirected, x, ids, 4, &cost), 2);
  check_double("tsp nearest cost", cost, 2.0);
  check_int("remove undirected edge", ug_graph_remove_edge(undirected, x, y), 1);
  check_int("reverse mirror removed", ug_graph_has_edge(undirected, y, x), 0);
  check_ll("undirected edge count updated", ug_graph_edge_count(undirected), 0);
  ug_graph_free(undirected);

  if (failures == 0) {
    printf("All C ABI tests passed.\n");
    return 0;
  }
  printf("%d C ABI test(s) failed.\n", failures);
  return 1;
}
