# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import unigraph
import pytest


def test_version():
    assert unigraph.version() == "1.0.0"
    assert unigraph.__version__ == "1.0.0"


def test_directed_basic():
    g = unigraph.Graph(directed=True)
    a = g.add_vertex(10)
    b = g.add_vertex(20)

    assert g.vertex_count == 2
    assert g.get_vertex_data(a) == 10
    assert g.get_vertex_data(b) == 20

    assert g.add_edge(a, b, 3.14) is True
    assert g.edge_count == 1
    assert g.has_edge(a, b) is True
    assert g.has_edge(b, a) is False
    assert g.get_edge_weight(a, b) == 3.14


def test_undirected_mirrors_edge():
    g = unigraph.Graph(directed=False)
    a = g.add_vertex(1)
    b = g.add_vertex(2)
    g.add_edge(a, b, 1.0)

    assert g.has_edge(a, b) is True
    assert g.has_edge(b, a) is True


def test_self_loop_rejected():
    g = unigraph.Graph()
    a = g.add_vertex(1)
    assert g.add_edge(a, a, 0.0) is False


def test_duplicate_edge_rejected():
    g = unigraph.Graph()
    a = g.add_vertex(1)
    b = g.add_vertex(2)
    assert g.add_edge(a, b, 1.0) is True
    assert g.add_edge(a, b, 2.0) is False


def test_missing_vertex_and_edge_return_none():
    g = unigraph.Graph()
    assert g.get_vertex_data(999) is None
    a = g.add_vertex(1)
    b = g.add_vertex(2)
    assert g.get_edge_weight(a, b) is None


def make_weighted_graph(directed=False):
    g = unigraph.Graph(directed=directed)
    vertices = [g.add_vertex(value) for value in (10, 20, 30, 40)]
    for source, target, weight in (
        (0, 1, 1.0),
        (1, 2, 2.0),
        (2, 3, 1.0),
        (3, 0, 2.0),
        (0, 2, 5.0),
        (1, 3, 5.0),
    ):
        assert g.add_edge(vertices[source], vertices[target], weight)
    return g, vertices


def test_collections_traversals_and_removal():
    g, vertices = make_weighted_graph(directed=True)
    assert g.vertices() == vertices
    assert g.edges()[0] == (vertices[0], vertices[1], 1.0)
    assert g.neighbors(vertices[0]) == g.out_neighbors(vertices[0])
    assert g.in_neighbors(vertices[2]) == [
        (vertices[0], vertices[2], 5.0),
        (vertices[1], vertices[2], 2.0),
    ]
    assert g.bfs(vertices[0])[0] == vertices[0]
    assert g.dfs(vertices[0])[0] == vertices[0]
    assert g.reachable(vertices[0]) == vertices
    assert g.is_connected() is True
    assert g.remove_edge(vertices[0], vertices[2]) is True
    assert g.remove_edge(vertices[0], vertices[2]) is False
    assert g.edge_count == 5

    undirected, undirected_vertices = make_weighted_graph(directed=False)
    before = undirected.edge_count
    assert undirected.remove_edge(undirected_vertices[0],
                                  undirected_vertices[2]) is True
    assert not undirected.has_edge(undirected_vertices[0],
                                   undirected_vertices[2])
    assert not undirected.has_edge(undirected_vertices[2],
                                   undirected_vertices[0])
    assert undirected.edge_count == before - 1


def test_shortest_paths_and_components():
    g, vertices = make_weighted_graph(directed=False)
    expected = {vertices[0]: 0.0, vertices[1]: 1.0,
                vertices[2]: 3.0, vertices[3]: 2.0}
    assert g.dijkstra(vertices[0]) == expected
    assert g.shortest_path(vertices[0], vertices[2]) == (
        [vertices[0], vertices[1], vertices[2]], 3.0
    )
    assert g.a_star(vertices[0], vertices[2]) == [
        vertices[0], vertices[1], vertices[2]
    ]
    assert g.bellman_ford(vertices[0]) == (expected, False)
    assert {vertex for vertex, _ in g.strongly_connected_components()} == set(vertices)
    assert {vertex for vertex, _ in g.kosaraju()} == set(vertices)


def test_mst_tsp_and_visualization():
    g, vertices = make_weighted_graph(directed=False)
    assert sum(edge[2] for edge in g.prim()) == 4.0
    assert sum(edge[2] for edge in g.kruskal()) == 4.0
    assert g.articulation_points() == []
    assert g.tsp_naive()[1] == 6.0
    assert g.tsp_2opt()[1] == 6.0
    nearest_path, nearest_cost = g.tsp_nearest(vertices[0])
    assert nearest_path[0] == vertices[0]
    assert len(nearest_path) == g.vertex_count
    assert nearest_cost == 6.0
    assert sum(count for _, count in g.degree_distribution()) == g.vertex_count
    assert "[0]" in g.to_ascii()
    assert "graph G" in g.to_dot()


def test_unknown_vertices_raise_for_algorithm_inputs():
    g = unigraph.Graph()
    for operation in (g.neighbors, g.in_neighbors, g.out_neighbors, g.bfs,
                      g.dfs, g.reachable, g.dijkstra):
        with pytest.raises(ValueError):
            operation(999)


def test_undirected_algorithms_reject_directed_graphs():
    g = unigraph.Graph(directed=True)
    for operation in (g.prim, g.kruskal, g.articulation_points):
        with pytest.raises(ValueError):
            operation()
