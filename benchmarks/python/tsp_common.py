# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Shared nearest-neighbor / 2-opt TSP heuristics for the Python benchmark
harnesses (bench_networkx.py, bench_igraph.py). Neither networkx nor
python-igraph ships this, so it's hand-rolled here once and imported by
both scripts -- guaranteeing they run the identical algorithm rather than
two subtly different ones. Mirrors algorithms/tsp.nim's
tspNearestNeighbor/tsp2Opt, as implemented by the standalone
nearestNeighbor/twoOpt procs in ../nim/bench_unigraph.nim: same candidate
scan order (index 0..n-1, first strictly-smaller distance wins), same
first-improvement full-double-loop 2-opt. See ../README.md.
"""
import math


def _dist(coords, i, j):
    xi, yi = coords[i]
    xj, yj = coords[j]
    return math.sqrt((xi - xj) ** 2 + (yi - yj) ** 2)


def _tour_cost(coords, path):
    total = 0.0
    for i in range(len(path) - 1):
        total += _dist(coords, path[i], path[i + 1])
    total += _dist(coords, path[-1], path[0])
    return total


def load_coords(path):
    """Read a `tsp/*.tsp` fixture: line 1 = N, lines 2..N+1 = 'x y'."""
    with open(path) as f:
        lines = f.read().splitlines()
    n = int(lines[0].strip())
    coords = []
    for i in range(1, n + 1):
        x, y = lines[i].split()
        coords.append((float(x), float(y)))
    return coords


def nearest_neighbor(coords, start=0):
    """Greedy tour: from the current city, scan ALL unvisited cities in
    index order 0..n-1, pick the strictly closest (first strictly-smaller
    distance wins ties), until all n visited; then close the tour back to
    start. Returns (path, cost)."""
    n = len(coords)
    path = [start]
    visited = [False] * n
    visited[start] = True
    while len(path) < n:
        current = path[-1]
        best = -1
        best_dist = math.inf
        for v in range(n):
            if not visited[v]:
                d = _dist(coords, current, v)
                if d < best_dist:
                    best_dist = d
                    best = v
        visited[best] = True
        path.append(best)
    return path, _tour_cost(coords, path)


def two_opt(coords, initial_path, max_iterations=1000):
    """First-improvement full double loop: repeat up to max_iterations full
    passes; for i in 0..len-2, for j in i+1..len-1, reverse path[i..j]; keep
    the reversal if the new tour cost is strictly lower. Recomputes the full
    tour cost per candidate move (O(n^3) per pass) to match the Nim
    reference exactly -- not optimized into an incremental-delta version, so
    timing stays comparable. Stops early after a pass with no improvement.
    Returns (path, cost)."""
    path = list(initial_path)
    cost = _tour_cost(coords, path)
    improved = True
    iterations = 0
    while improved and iterations < max_iterations:
        improved = False
        iterations += 1
        for i in range(len(path) - 1):
            for j in range(i + 1, len(path)):
                new_path = path[:i] + path[i:j + 1][::-1] + path[j + 1:]
                new_cost = _tour_cost(coords, new_path)
                if new_cost < cost:
                    cost = new_cost
                    path = new_path
                    improved = True
    return path, cost
