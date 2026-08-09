#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Cross-library benchmark harness: python-igraph side (wraps the C igraph
core).

pip deps: python-igraph >= 0.11.8 (see tsp_common.py for the shared TSP
heuristics; no other third-party dependency).

Reads the *.edges / tsp/*.tsp fixtures produced by ../generate_graphs.py
(same files every language harness reads) and appends one CSV row per
(library, algorithm, graph) run to the path given as the second argument.
See ../nim/bench_unigraph.nim for the ground-truth algorithm semantics and
../README.md for the file formats and digest values used to cross-check
correctness. python-igraph does not expose separate Prim/Kruskal MST
implementations -- its single spanning_tree() call is recorded once as
algorithm "mst_default" instead of mst_prim/mst_kruskal.

Usage: python3 bench_igraph.py <data_dir> <output_csv>
"""
import csv
import glob
import math
import os
import sys
import time

import igraph as ig

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


def build_graph(n, edges, directed, weighted):
    # Undirected graphs list each edge once in the fixture; igraph.Graph
    # with directed=False is inherently undirected, so a single edge
    # insertion per fixture line suffices -- no manual reverse-edge
    # insertion needed (that instruction targets adjacency-list style
    # kernels, not igraph's native undirected container).
    #
    # UniGraph's ListKernel defaults to graphType Simple, which rejects
    # addEdge on a (source, target) pair that already exists -- so on the
    # rare accidental duplicate line, the FIRST occurrence wins and later
    # ones are no-ops. Mirror that by deduping before construction (keyed on
    # the unordered pair for undirected graphs), or weighted digests
    # (dijkstra/mst) diverge from the reference.
    seen = set()
    unique_edges = []
    unique_weights = []
    for u, v, w in edges:
        key = (u, v) if directed else (min(u, v), max(u, v))
        if key in seen:
            continue
        seen.add(key)
        unique_edges.append((u, v))
        if weighted:
            unique_weights.append(w)
    g = ig.Graph(n=n, edges=unique_edges, directed=directed)
    if weighted:
        g.es["weight"] = unique_weights
    return g


def record(writer, algo, graph, n, m, directed, weighted, load_s, algo_s, digest):
    writer.writerow(["python", "igraph", algo, graph, n, m, int(directed),
                      int(weighted), f"{load_s:.6f}", f"{algo_s:.6f}", digest])
    print(f"  igraph/{algo} on {graph}: load={load_s:.3f}s algo={algo_s:.3f}s "
          f"digest={digest}", file=sys.stderr)


def run_graph_benchmarks(path, name, writer):
    print(f"Graph: {name}", file=sys.stderr)
    t0 = time.perf_counter()
    n, m, directed, weighted, start = load_header(path)
    edges = load_edges(path, m)
    g = build_graph(n, edges, directed, weighted)
    load_s = time.perf_counter() - t0

    t0 = time.perf_counter()
    order, _, _ = g.bfs(start, mode="out")
    algo_s = time.perf_counter() - t0
    record(writer, "bfs", name, n, m, directed, weighted, load_s, algo_s, str(len(order)))

    t0 = time.perf_counter()
    order, _ = g.dfs(start, mode="out")
    algo_s = time.perf_counter() - t0
    record(writer, "dfs", name, n, m, directed, weighted, load_s, algo_s, str(len(order)))

    if weighted:
        t0 = time.perf_counter()
        dists = g.distances(source=[start], weights="weight", mode="out")[0]
        algo_s = time.perf_counter() - t0
        total = sum(d for d in dists if math.isfinite(d))
        record(writer, "dijkstra", name, n, m, directed, weighted, load_s, algo_s,
               f"{total:.2f}")

    if not directed:
        t0 = time.perf_counter()
        tree = g.spanning_tree(weights="weight" if weighted else None)
        algo_s = time.perf_counter() - t0
        total = sum(tree.es["weight"]) if weighted else len(tree.es)
        record(writer, "mst_default", name, n, m, directed, weighted, load_s, algo_s,
               f"{total:.2f}")

    if directed:
        t0 = time.perf_counter()
        comps = g.connected_components(mode="strong")
        algo_s = time.perf_counter() - t0
        record(writer, "scc_tarjan", name, n, m, directed, weighted, load_s, algo_s,
               str(len(comps)))


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
        print("usage: bench_igraph.py <data_dir> <output_csv>", file=sys.stderr)
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
