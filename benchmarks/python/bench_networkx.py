#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Cross-library benchmark harness: networkx side.

pip deps: networkx (see tsp_common.py for the shared TSP heuristics; no
other third-party dependency).

Reads the *.edges / tsp/*.tsp fixtures produced by ../generate_graphs.py
(same files every language harness reads) and appends one CSV row per
(library, algorithm, graph) run to the path given as the second argument.
See ../nim/bench_unigraph.nim for the ground-truth algorithm semantics and
../README.md for the file formats and digest values used to cross-check
correctness.

Usage: python3 bench_networkx.py <data_dir> <output_csv>
"""
import csv
import glob
import os
import sys
import time

import networkx as nx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tsp_common import load_coords, nearest_neighbor, two_opt


def load_header(path):
    with open(path) as f:
        first = f.readline()
    n, m, directed, weighted, start = first.split()
    return int(n), int(m), int(directed) != 0, int(weighted) != 0, int(start)


def load_edges(path, m):
    edges = []
    with open(path) as f:
        f.readline()
        for _ in range(m):
            u, v, w = f.readline().split()
            edges.append((int(u), int(v), float(w)))
    return edges


def build_graph(n, edges, directed):
    # Undirected graphs list each edge once in the fixture; nx.Graph is
    # inherently undirected so a single add_edge suffices -- no manual
    # reverse-edge insertion needed (that instruction targets adjacency-list
    # style kernels, not networkx's native undirected container).
    #
    # UniGraph's ListKernel defaults to graphType Simple, which rejects
    # addEdge on a (source, target) pair that already exists -- so on the
    # rare accidental duplicate line, the FIRST occurrence wins and later
    # ones are no-ops. Mirror that here (has_edge is symmetric on nx.Graph,
    # so a reversed-order duplicate is caught too) instead of last-write-wins,
    # or weighted digests (dijkstra/mst) diverge from the reference.
    g = nx.DiGraph() if directed else nx.Graph()
    g.add_nodes_from(range(n))
    for u, v, w in edges:
        if not g.has_edge(u, v):
            g.add_edge(u, v, weight=w)
    return g


def record(writer, algo, graph, n, m, directed, weighted, load_s, algo_s, digest):
    writer.writerow(["python", "networkx", algo, graph, n, m, int(directed),
                      int(weighted), f"{load_s:.6f}", f"{algo_s:.6f}", digest])
    print(f"  networkx/{algo} on {graph}: load={load_s:.3f}s algo={algo_s:.3f}s "
          f"digest={digest}", file=sys.stderr)


def run_graph_benchmarks(path, name, writer):
    print(f"Graph: {name}", file=sys.stderr)
    t0 = time.perf_counter()
    n, m, directed, weighted, start = load_header(path)
    edges = load_edges(path, m)
    g = build_graph(n, edges, directed)
    load_s = time.perf_counter() - t0

    t0 = time.perf_counter()
    reach = nx.single_source_shortest_path_length(g, start)
    algo_s = time.perf_counter() - t0
    record(writer, "bfs", name, n, m, directed, weighted, load_s, algo_s, str(len(reach)))

    t0 = time.perf_counter()
    order = list(nx.dfs_preorder_nodes(g, start))
    algo_s = time.perf_counter() - t0
    record(writer, "dfs", name, n, m, directed, weighted, load_s, algo_s, str(len(order)))

    if weighted:
        t0 = time.perf_counter()
        dist = nx.single_source_dijkstra_path_length(g, start, weight="weight")
        algo_s = time.perf_counter() - t0
        total = sum(dist.values())
        record(writer, "dijkstra", name, n, m, directed, weighted, load_s, algo_s,
               f"{total:.2f}")

    if not directed:
        t0 = time.perf_counter()
        mst_prim = nx.minimum_spanning_tree(g, weight="weight", algorithm="prim")
        algo_s = time.perf_counter() - t0
        total = sum(d["weight"] for _, _, d in mst_prim.edges(data=True))
        record(writer, "mst_prim", name, n, m, directed, weighted, load_s, algo_s,
               f"{total:.2f}")

        t0 = time.perf_counter()
        mst_kruskal = nx.minimum_spanning_tree(g, weight="weight", algorithm="kruskal")
        algo_s = time.perf_counter() - t0
        total = sum(d["weight"] for _, _, d in mst_kruskal.edges(data=True))
        record(writer, "mst_kruskal", name, n, m, directed, weighted, load_s, algo_s,
               f"{total:.2f}")

    if directed:
        t0 = time.perf_counter()
        sccs = list(nx.strongly_connected_components(g))
        algo_s = time.perf_counter() - t0
        record(writer, "scc_tarjan", name, n, m, directed, weighted, load_s, algo_s,
               str(len(sccs)))


def run_tsp_benchmarks(path, name, writer):
    print(f"TSP: {name}", file=sys.stderr)
    t0 = time.perf_counter()
    coords = load_coords(path)
    load_s = time.perf_counter() - t0
    n = len(coords)

    t0 = time.perf_counter()
    nn_path, nn_cost = nearest_neighbor(coords, 0)
    nn_s = time.perf_counter() - t0
    record(writer, "tsp_nn", name, n, 0, False, True, load_s, nn_s, f"{nn_cost:.2f}")

    t0 = time.perf_counter()
    _, opt_cost = two_opt(coords, nn_path, 1000)
    opt_s = time.perf_counter() - t0
    record(writer, "tsp_2opt", name, n, 0, False, True, load_s, opt_s, f"{opt_cost:.2f}")


def main():
    if len(sys.argv) < 3:
        print("usage: bench_networkx.py <data_dir> <output_csv>", file=sys.stderr)
        sys.exit(1)
    data_dir, output_csv = sys.argv[1], sys.argv[2]

    graph_files = sorted(glob.glob(os.path.join(data_dir, "*.edges")))
    tsp_files = sorted(glob.glob(os.path.join(data_dir, "tsp", "*.tsp")))

    write_header = not os.path.exists(output_csv)
    with open(output_csv, "a", newline="") as f:
        writer = csv.writer(f)
        if write_header:
            writer.writerow(["lang", "library", "algorithm", "graph", "n", "m",
                              "directed", "weighted", "load_seconds", "algo_seconds",
                              "digest"])
        for path in graph_files:
            name = os.path.splitext(os.path.basename(path))[0]
            run_graph_benchmarks(path, name, writer)
        for path in tsp_files:
            name = os.path.splitext(os.path.basename(path))[0]
            run_tsp_benchmarks(path, name, writer)


if __name__ == "__main__":
    main()
