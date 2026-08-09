#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Deterministic graph/TSP-instance generator shared by every language harness.

Every harness (Nim/UniGraph, Python/networkx+igraph, C++/Boost, Rust/petgraph)
reads the exact same files from benchmarks/data/, so a timing or correctness
difference reflects the library/algorithm, not the input.

File formats
------------
Graph file (*.edges):
    line 1: "V E DIRECTED WEIGHTED START"  (five ints; DIRECTED/WEIGHTED
            are 0|1; START is the vertex every harness must use as the
            fixed BFS/DFS/Dijkstra source)
    lines 2..E+1: "u v w"             (0-indexed vertex ids, float weight)
    Undirected graphs list each edge once; consumers add both directions.
    No (u, v) pair repeats: an accidental duplicate from random sampling is
    dropped, not resampled, so the actual edge count can be a handful below
    the nominal m at the largest sizes. This matters because libraries
    disagree on how to handle a parallel edge: UniGraph's ListKernel keeps
    only the first-written weight and silently rejects the rest under its
    Simple graphType, while Boost/petgraph keep every parallel edge and let
    Dijkstra pick the best one during relaxation. Each behavior is
    internally correct for the graph its own library ends up building, but
    the two builds then differ from the same file. Deduplicating at
    generation time removes the ambiguity: every language builds the exact
    same simple graph, independent of its own parallel-edge policy.

    START is precomputed here (max-degree vertex from the raw edge list,
    ties -> lowest index) instead of left for each harness to recompute: a
    library that silently dedupes parallel edges could otherwise land on a
    different max-degree vertex than one that doesn't, making BFS/DFS/
    Dijkstra digests diverge for a reason unrelated to the algorithm being
    benchmarked. Vertex 0 is not used as the fixed start: on a sparse random
    graph it can be near-isolated by chance, which would make the traversal
    trivial.

TSP instance (tsp/*.tsp):
    line 1: "N"
    lines 2..N+1: "x y"               (2D coordinates; distance = Euclidean)

    N tops out at 500, well below the general-graph sizes below: every
    harness's 2-opt recomputes the full tour cost per candidate move (see
    README.md's TSP methodology), an O(n) cost per move on top of the O(n^2)
    moves per pass, so each pass is O(n^3). Measured directly: one 2-opt run
    takes ~9s at n=1000 and ~74s at n=2000 in compiled, release-mode Nim --
    the fastest of the five harnesses -- which would run to tens of minutes
    per instance in pure Python. n=500 keeps every harness's run in the
    range of seconds to low tens of seconds.

Sizes for the general (non-TSP) graphs are tiered (1e3/1e4/1e5, with 1e6
only for the generators cheap enough to build and traverse at that scale in
every language within a reasonable benchmark run) -- see README.md for why.
"""
import random
import os
import argparse

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
TSP_DIR = os.path.join(DATA_DIR, "tsp")

SEED = 42


def max_degree_start(n, directed, edges):
    """Degree (out-degree if directed) counted from the raw edge list --
    a pure function of the file contents, independent of how any given
    library later represents/dedupes the graph. Ties -> lowest index."""
    degree = [0] * n
    for u, v, _ in edges:
        degree[u] += 1
        if not directed:
            degree[v] += 1
    best = 0
    for i in range(1, n):
        if degree[i] > degree[best]:
            best = i
    return best


def write_graph(path, n, directed, weighted, edges):
    start = max_degree_start(n, directed, edges)
    with open(path, "w") as f:
        f.write(f"{n} {len(edges)} {int(directed)} {int(weighted)} {start}\n")
        for u, v, w in edges:
            f.write(f"{u} {v} {w}\n")


def er_undirected(n, avg_degree, rng):
    m = (n * avg_degree) // 2
    edges = []
    seen = set()
    for _ in range(m):
        u = rng.randrange(n)
        v = rng.randrange(n)
        while v == u:
            v = rng.randrange(n)
        key = (u, v) if u < v else (v, u)
        if key in seen:
            continue  # dropped, not resampled: see module docstring
        seen.add(key)
        edges.append((u, v, round(rng.uniform(1, 100), 3)))
    return edges


def er_directed(n, avg_out_degree, rng):
    m = n * avg_out_degree
    edges = []
    seen = set()
    for _ in range(m):
        u = rng.randrange(n)
        v = rng.randrange(n)
        while v == u:
            v = rng.randrange(n)
        if (u, v) in seen:
            continue  # dropped, not resampled: see module docstring
        seen.add((u, v))
        edges.append((u, v, round(rng.uniform(1, 100), 3)))
    return edges


def barabasi_albert(n, m_attach, rng):
    """Preferential attachment via the standard repeated-node-list trick."""
    m0 = max(m_attach + 1, 3)
    edges = []
    repeated_nodes = []
    for u in range(m0):
        for v in range(u):
            edges.append((u, v, round(rng.uniform(1, 100), 3)))
            repeated_nodes += [u, v]
    for u in range(m0, n):
        targets = set()
        while len(targets) < m_attach:
            targets.add(repeated_nodes[rng.randrange(len(repeated_nodes))])
        for v in targets:
            edges.append((u, v, round(rng.uniform(1, 100), 3)))
            repeated_nodes += [u, v]
    return edges


def grid(side, rng):
    n = side * side
    edges = []

    def idx(r, c):
        return r * side + c

    for r in range(side):
        for c in range(side):
            u = idx(r, c)
            if c + 1 < side:
                edges.append((u, idx(r, c + 1), round(rng.uniform(1, 100), 3)))
            if r + 1 < side:
                edges.append((u, idx(r + 1, c), round(rng.uniform(1, 100), 3)))
    return n, edges


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--output-dir", default=DATA_DIR)
    args = parser.parse_args()
    data_dir = args.output_dir
    tsp_dir = os.path.join(data_dir, "tsp")
    os.makedirs(data_dir, exist_ok=True)
    os.makedirs(tsp_dir, exist_ok=True)
    manifest = []

    sparse_sizes = (100,) if args.smoke else (1_000, 10_000, 100_000, 1_000_000)
    dense_sizes = (100,) if args.smoke else (1_000, 5_000)
    scale_sizes = (100,) if args.smoke else (1_000, 10_000, 100_000, 1_000_000)
    grid_sides = (10,) if args.smoke else (32, 100, 316, 1000)
    directed_sizes = (100,) if args.smoke else (1_000, 10_000, 100_000, 1_000_000)
    tsp_sizes = (20,) if args.smoke else (100, 300, 500)

    for n in sparse_sizes:
        rng = random.Random(SEED)
        edges = er_undirected(n, avg_degree=4, rng=rng)
        name = f"er_sparse_undirected_n{n}"
        write_graph(os.path.join(data_dir, name + ".edges"), n, False, True, edges)
        manifest.append((name, n, len(edges), False))

    for n in dense_sizes:
        rng = random.Random(SEED)
        edges = er_undirected(n, avg_degree=max(2, int(0.05 * (n - 1))), rng=rng)
        name = f"er_dense_undirected_n{n}"
        write_graph(os.path.join(data_dir, name + ".edges"), n, False, True, edges)
        manifest.append((name, n, len(edges), False))

    for n in scale_sizes:
        rng = random.Random(SEED)
        edges = barabasi_albert(n, m_attach=3, rng=rng)
        name = f"ba_scalefree_undirected_n{n}"
        write_graph(os.path.join(data_dir, name + ".edges"), n, False, True, edges)
        manifest.append((name, n, len(edges), False))

    for side in grid_sides:
        rng = random.Random(SEED)
        n, edges = grid(side, rng)
        name = f"grid_undirected_n{n}"
        write_graph(os.path.join(data_dir, name + ".edges"), n, False, True, edges)
        manifest.append((name, n, len(edges), False))

    for n in directed_sizes:
        rng = random.Random(SEED)
        edges = er_directed(n, avg_out_degree=4, rng=rng)
        name = f"er_directed_n{n}"
        write_graph(os.path.join(data_dir, name + ".edges"), n, True, True, edges)
        manifest.append((name, n, len(edges), True))

    for n in tsp_sizes:
        rng = random.Random(SEED)
        with open(os.path.join(tsp_dir, f"tsp_n{n}.tsp"), "w") as f:
            f.write(f"{n}\n")
            for _ in range(n):
                f.write(f"{rng.uniform(0, 1000):.3f} {rng.uniform(0, 1000):.3f}\n")
        manifest.append((f"tsp_n{n}", n, None, None))

    with open(os.path.join(data_dir, "MANIFEST.txt"), "w") as f:
        for name, n, m, directed in manifest:
            f.write(f"{name} n={n} m={m} directed={directed}\n")

    print(f"Wrote {len(manifest)} files to {data_dir}")


if __name__ == "__main__":
    main()
