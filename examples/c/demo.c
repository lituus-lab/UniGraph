// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include "UniGraph.h"
#include <stdio.h>

int main(void) {
  if (!ug_init()) {
    return 1;
  }
  printf("UniGraph %s\n", ug_version());

  UniGraphHandle g = ug_graph_new(1 /* directed */);
  long long paris = ug_graph_add_vertex(g, 0);
  long long lyon = ug_graph_add_vertex(g, 1);
  long long marseille = ug_graph_add_vertex(g, 2);

  ug_graph_add_edge(g, paris, lyon, 450.0);
  ug_graph_add_edge(g, lyon, marseille, 310.0);

  printf("vertices=%lld edges=%lld\n", ug_graph_vertex_count(g),
         ug_graph_edge_count(g));

  double weight = 0.0;
  if (ug_graph_get_edge_weight(g, paris, lyon, &weight)) {
    printf("Paris -> Lyon: %.1f km\n", weight);
  }

  ug_graph_free(g);
  return 0;
}
