# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Thin Cython wrapper over include/UniGraph.h. One concrete instantiation
only: int64 vertex labels, float64 edge weights — see c_api.nim for why."""

from libc.stddef cimport size_t
from libc.stdlib cimport free, malloc
from cpython.bytes cimport PyBytes_FromStringAndSize

cdef extern from "UniGraph.h":
    ctypedef void *UniGraphHandle
    ctypedef struct UgEdge:
        long long source
        long long target
        double weight
    ctypedef struct UgComponentEntry:
        long long vertex
        long long component
    ctypedef struct UgDegreeCount:
        long long degree
        long long count
    int ug_init()
    const char *ug_version()
    UniGraphHandle ug_graph_new(int directed)
    void ug_graph_free(UniGraphHandle handle)
    long long ug_graph_vertex_count(UniGraphHandle handle)
    long long ug_graph_edge_count(UniGraphHandle handle)
    long long ug_graph_add_vertex(UniGraphHandle handle, long long data)
    int ug_graph_get_vertex_data(UniGraphHandle handle, long long vertex_id,
                                  long long *out_data)
    int ug_graph_add_edge(UniGraphHandle handle, long long source,
                           long long target, double weight)
    int ug_graph_has_edge(UniGraphHandle handle, long long source,
                           long long target)
    int ug_graph_get_edge_weight(UniGraphHandle handle, long long source,
                                  long long target, double *out_weight)
    int ug_graph_remove_edge(UniGraphHandle, long long, long long)
    long long ug_graph_vertices(UniGraphHandle, long long *, size_t)
    long long ug_graph_edges(UniGraphHandle, UgEdge *, size_t)
    long long ug_graph_neighbors(UniGraphHandle, long long, UgEdge *, size_t)
    long long ug_graph_in_neighbors(UniGraphHandle, long long, UgEdge *, size_t)
    long long ug_graph_out_neighbors(UniGraphHandle, long long, UgEdge *, size_t)
    long long ug_graph_bfs(UniGraphHandle, long long, long long *, size_t)
    long long ug_graph_dfs(UniGraphHandle, long long, long long *, size_t)
    int ug_graph_is_connected(UniGraphHandle)
    long long ug_graph_reachable(UniGraphHandle, long long, long long *, size_t)
    long long ug_graph_dijkstra(UniGraphHandle, long long, long long *,
                                double *, size_t)
    long long ug_graph_shortest_path(UniGraphHandle, long long, long long,
                                     long long *, size_t, double *)
    long long ug_graph_a_star(UniGraphHandle, long long, long long,
                              long long *, size_t)
    long long ug_graph_bellman_ford(UniGraphHandle, long long, long long *,
                                    double *, size_t, int *)
    long long ug_graph_prim(UniGraphHandle, UgEdge *, size_t)
    long long ug_graph_kruskal(UniGraphHandle, UgEdge *, size_t)
    long long ug_graph_scc(UniGraphHandle, UgComponentEntry *, size_t)
    long long ug_graph_kosaraju(UniGraphHandle, UgComponentEntry *, size_t)
    long long ug_graph_articulation_points(UniGraphHandle, long long *, size_t)
    long long ug_graph_tsp_naive(UniGraphHandle, long long *, size_t, double *)
    long long ug_graph_tsp_2opt(UniGraphHandle, long long, long long *, size_t,
                                double *)
    long long ug_graph_tsp_nearest(UniGraphHandle, long long, long long *,
                                   size_t, double *)
    long long ug_graph_to_ascii(UniGraphHandle, char *, size_t)
    long long ug_graph_to_dot(UniGraphHandle, char *, size_t)
    long long ug_graph_degree_distribution(UniGraphHandle, UgDegreeCount *, size_t)


if ug_init() != 1:
    raise RuntimeError("ug_init failed")


def version():
    return ug_version()


cdef class Graph:
    """A directed-or-undirected, simple graph: int label per vertex, float
    weight per edge. Wraps the ug_graph_* C ABI; frees itself on GC."""
    cdef UniGraphHandle _handle

    def __cinit__(self, bint directed=True):
        self._handle = ug_graph_new(1 if directed else 0)
        if self._handle is NULL:
            raise MemoryError("ug_graph_new failed")

    def __dealloc__(self):
        if self._handle is not NULL:
            ug_graph_free(self._handle)
            self._handle = NULL

    def add_vertex(self, long long data):
        return ug_graph_add_vertex(self._handle, data)

    def get_vertex_data(self, long long vertex_id):
        cdef long long out_data
        if ug_graph_get_vertex_data(self._handle, vertex_id, &out_data):
            return out_data
        return None

    def add_edge(self, long long source, long long target, double weight):
        return bool(ug_graph_add_edge(self._handle, source, target, weight))

    def has_edge(self, long long source, long long target):
        return bool(ug_graph_has_edge(self._handle, source, target))

    def get_edge_weight(self, long long source, long long target):
        cdef double out_weight
        if ug_graph_get_edge_weight(self._handle, source, target, &out_weight):
            return out_weight
        return None

    def remove_edge(self, long long source, long long target):
        return bool(ug_graph_remove_edge(self._handle, source, target))

    cdef list _ids(self, long long (*fn)(UniGraphHandle, long long *, size_t)):
        cdef long long count = fn(self._handle, NULL, 0)
        cdef long long *items = NULL
        cdef long long i
        if count < 0:
            raise ValueError("invalid graph operation")
        if count == 0:
            return []
        items = <long long *>malloc(<size_t>count * sizeof(long long))
        if items is NULL:
            raise MemoryError()
        try:
            if fn(self._handle, items, <size_t>count) != count:
                raise RuntimeError("graph changed while reading")
            return [items[i] for i in range(count)]
        finally:
            free(items)

    cdef list _walk(self, long long start,
                    long long (*fn)(UniGraphHandle, long long, long long *, size_t)):
        cdef long long count = fn(self._handle, start, NULL, 0)
        cdef long long *items = NULL
        cdef long long i
        if count < 0:
            raise ValueError("unknown start vertex")
        if count == 0:
            return []
        items = <long long *>malloc(<size_t>count * sizeof(long long))
        if items is NULL:
            raise MemoryError()
        try:
            if fn(self._handle, start, items, <size_t>count) != count:
                raise RuntimeError("graph changed while reading")
            return [items[i] for i in range(count)]
        finally:
            free(items)

    cdef list _edges(self, long long vertex, int mode):
        cdef long long count
        cdef long long required
        cdef UgEdge *items = NULL
        cdef long long i
        if mode == 1:
            count = ug_graph_neighbors(self._handle, vertex, NULL, 0)
        elif mode == 2:
            count = ug_graph_in_neighbors(self._handle, vertex, NULL, 0)
        elif mode == 3:
            count = ug_graph_out_neighbors(self._handle, vertex, NULL, 0)
        else:
            count = ug_graph_edges(self._handle, NULL, 0)
        if count < 0:
            raise ValueError("unknown vertex" if mode else "invalid graph")
        if count == 0:
            return []
        items = <UgEdge *>malloc(<size_t>count * sizeof(UgEdge))
        if items is NULL:
            raise MemoryError()
        try:
            if mode == 1:
                required = ug_graph_neighbors(self._handle, vertex, items,
                                              <size_t>count)
            elif mode == 2:
                required = ug_graph_in_neighbors(self._handle, vertex, items,
                                                 <size_t>count)
            elif mode == 3:
                required = ug_graph_out_neighbors(self._handle, vertex, items,
                                                  <size_t>count)
            else:
                required = ug_graph_edges(self._handle, items, <size_t>count)
            if required != count:
                raise RuntimeError("graph changed while reading")
            return [(items[i].source, items[i].target, items[i].weight)
                    for i in range(count)]
        finally:
            free(items)

    def vertices(self):
        return self._ids(ug_graph_vertices)

    def edges(self):
        return self._edges(0, 0)

    def neighbors(self, long long vertex):
        return self._edges(vertex, 1)

    def in_neighbors(self, long long vertex):
        return self._edges(vertex, 2)

    def out_neighbors(self, long long vertex):
        return self._edges(vertex, 3)

    def bfs(self, long long start):
        return self._walk(start, ug_graph_bfs)

    def dfs(self, long long start):
        return self._walk(start, ug_graph_dfs)

    def is_connected(self):
        return bool(ug_graph_is_connected(self._handle))

    def reachable(self, long long start):
        return self._walk(start, ug_graph_reachable)

    def dijkstra(self, long long start):
        cdef long long count = ug_graph_dijkstra(self._handle, start, NULL, NULL, 0)
        cdef long long *vertices = NULL
        cdef double *distances = NULL
        cdef long long i
        if count < 0:
            raise ValueError("unknown start vertex")
        if count == 0:
            return {}
        vertices = <long long *>malloc(<size_t>count * sizeof(long long))
        distances = <double *>malloc(<size_t>count * sizeof(double))
        if vertices is NULL or distances is NULL:
            free(vertices)
            free(distances)
            raise MemoryError()
        try:
            if ug_graph_dijkstra(self._handle, start, vertices, distances,
                                 <size_t>count) != count:
                raise RuntimeError("graph changed while reading")
            return {vertices[i]: distances[i] for i in range(count)}
        finally:
            free(vertices)
            free(distances)

    cdef object _path(self, long long start, long long goal, bint astar):
        cdef long long count
        cdef long long required
        cdef long long *items = NULL
        cdef long long i
        cdef double cost = 0.0
        if astar:
            count = ug_graph_a_star(self._handle, start, goal, NULL, 0)
        else:
            count = ug_graph_shortest_path(self._handle, start, goal, NULL, 0,
                                           &cost)
        if count < 0:
            raise ValueError("unknown endpoint")
        if count == 0:
            return None
        items = <long long *>malloc(<size_t>count * sizeof(long long))
        if items is NULL:
            raise MemoryError()
        try:
            if astar:
                required = ug_graph_a_star(self._handle, start, goal, items,
                                           <size_t>count)
                if required != count:
                    raise RuntimeError("graph changed while reading")
                return [items[i] for i in range(count)]
            if ug_graph_shortest_path(self._handle, start, goal, items,
                                      <size_t>count, &cost) != count:
                raise RuntimeError("graph changed while reading")
            return ([items[i] for i in range(count)], cost)
        finally:
            free(items)

    def shortest_path(self, long long start, long long goal):
        return self._path(start, goal, False)

    def a_star(self, long long start, long long goal):
        return self._path(start, goal, True)

    def bellman_ford(self, long long start):
        cdef long long count = ug_graph_bellman_ford(self._handle, start, NULL,
                                                     NULL, 0, NULL)
        cdef long long *vertices = NULL
        cdef double *distances = NULL
        cdef int negative = 0
        cdef long long i
        if count < 0:
            raise ValueError("unknown start vertex")
        if count == 0:
            return ({}, False)
        vertices = <long long *>malloc(<size_t>count * sizeof(long long))
        distances = <double *>malloc(<size_t>count * sizeof(double))
        if vertices is NULL or distances is NULL:
            free(vertices)
            free(distances)
            raise MemoryError()
        try:
            if ug_graph_bellman_ford(self._handle, start, vertices, distances,
                                     <size_t>count, &negative) != count:
                raise RuntimeError("graph changed while reading")
            return ({vertices[i]: distances[i] for i in range(count)},
                    bool(negative))
        finally:
            free(vertices)
            free(distances)

    cdef list _edge_algorithm(self,
                              long long (*fn)(UniGraphHandle, UgEdge *, size_t)):
        cdef long long count = fn(self._handle, NULL, 0)
        cdef UgEdge *items = NULL
        cdef long long i
        if count < 0:
            raise ValueError("algorithm is not defined for this graph")
        if count == 0:
            return []
        items = <UgEdge *>malloc(<size_t>count * sizeof(UgEdge))
        if items is NULL:
            raise MemoryError()
        try:
            if fn(self._handle, items, <size_t>count) != count:
                raise RuntimeError("graph changed while reading")
            return [(items[i].source, items[i].target, items[i].weight)
                    for i in range(count)]
        finally:
            free(items)

    def prim(self):
        return self._edge_algorithm(ug_graph_prim)

    def kruskal(self):
        return self._edge_algorithm(ug_graph_kruskal)

    cdef list _components(self, bint use_kosaraju):
        cdef long long count
        cdef long long required
        cdef UgComponentEntry *items = NULL
        cdef long long i
        if use_kosaraju:
            count = ug_graph_kosaraju(self._handle, NULL, 0)
        else:
            count = ug_graph_scc(self._handle, NULL, 0)
        if count < 0:
            raise ValueError("invalid graph")
        if count == 0:
            return []
        items = <UgComponentEntry *>malloc(<size_t>count * sizeof(UgComponentEntry))
        if items is NULL:
            raise MemoryError()
        try:
            if use_kosaraju:
                required = ug_graph_kosaraju(self._handle, items,
                                             <size_t>count)
                if required != count:
                    raise RuntimeError("graph changed while reading")
            elif ug_graph_scc(self._handle, items, <size_t>count) != count:
                raise RuntimeError("graph changed while reading")
            return [(items[i].vertex, items[i].component) for i in range(count)]
        finally:
            free(items)

    def strongly_connected_components(self):
        return self._components(False)

    def kosaraju(self):
        return self._components(True)

    def articulation_points(self):
        return self._ids(ug_graph_articulation_points)

    cdef tuple _tour(self, long long start, long long max_iterations, int kind):
        cdef long long count
        cdef long long required
        cdef long long *items = NULL
        cdef double cost = 0.0
        cdef long long i
        if kind == 0:
            count = ug_graph_tsp_naive(self._handle, NULL, 0, &cost)
        elif kind == 1:
            count = ug_graph_tsp_2opt(self._handle, max_iterations, NULL, 0, &cost)
        else:
            count = ug_graph_tsp_nearest(self._handle, start, NULL, 0, &cost)
        if count < 0:
            raise ValueError("invalid TSP arguments")
        if count == 0:
            return ([], cost)
        items = <long long *>malloc(<size_t>count * sizeof(long long))
        if items is NULL:
            raise MemoryError()
        try:
            if kind == 0:
                required = ug_graph_tsp_naive(self._handle, items,
                                              <size_t>count, &cost)
            elif kind == 1:
                required = ug_graph_tsp_2opt(self._handle, max_iterations,
                                             items, <size_t>count, &cost)
            else:
                required = ug_graph_tsp_nearest(self._handle, start, items,
                                                <size_t>count, &cost)
            if required != count:
                raise RuntimeError("graph changed while reading")
            return ([items[i] for i in range(count)], cost)
        finally:
            free(items)

    def tsp_naive(self):
        return self._tour(0, 0, 0)

    def tsp_2opt(self, long long max_iterations=1000):
        return self._tour(0, max_iterations, 1)

    def tsp_nearest(self, long long start):
        return self._tour(start, 0, 2)

    cdef str _render(self, bint dot):
        cdef long long count
        cdef char *output = NULL
        if dot:
            count = ug_graph_to_dot(self._handle, NULL, 0)
        else:
            count = ug_graph_to_ascii(self._handle, NULL, 0)
        if count < 0:
            raise ValueError("invalid graph")
        output = <char *>malloc(<size_t>count + 1)
        if output is NULL:
            raise MemoryError()
        try:
            if dot:
                ug_graph_to_dot(self._handle, output, <size_t>count + 1)
            else:
                ug_graph_to_ascii(self._handle, output, <size_t>count + 1)
            return PyBytes_FromStringAndSize(output, count).decode("utf-8")
        finally:
            free(output)

    def to_ascii(self):
        return self._render(False)

    def to_dot(self):
        return self._render(True)

    def degree_distribution(self):
        cdef long long count = ug_graph_degree_distribution(self._handle, NULL, 0)
        cdef UgDegreeCount *items = NULL
        cdef long long i
        if count < 0:
            raise ValueError("invalid graph")
        if count == 0:
            return []
        items = <UgDegreeCount *>malloc(<size_t>count * sizeof(UgDegreeCount))
        if items is NULL:
            raise MemoryError()
        try:
            if ug_graph_degree_distribution(self._handle, items,
                                            <size_t>count) != count:
                raise RuntimeError("graph changed while reading")
            return [(items[i].degree, items[i].count) for i in range(count)]
        finally:
            free(items)

    @property
    def vertex_count(self):
        return ug_graph_vertex_count(self._handle)

    @property
    def edge_count(self):
        return ug_graph_edge_count(self._handle)
