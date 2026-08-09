#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Cross-library correctness check over benchmarks/results/results.csv.

Every harness (Nim/UniGraph, Python/networkx, Python/igraph, C++/Boost,
Rust/petgraph) runs the same algorithm on the same fixture and reports a
`digest` -- a single number cheap to compare that should agree across
libraries if everyone's implementation (and this benchmark's plumbing) is
correct. This script is the actual "verify our algorithms" check: a
performance number is only meaningful once the two sides being timed agree
on the answer.

Rules
-----
- bfs/dfs: exact-integer reachable-vertex count. Must match exactly across
  every library for a given graph, AND bfs must equal dfs for the same
  library+graph (same reachable set, independent of traversal order).
- scc_tarjan: exact-integer component count. Must match exactly.
- dijkstra, normalized mst, tsp_nn: float digest, compared with a tight relative
  tolerance (rounding-only differences expected).
- tsp_2opt: float digest, wider tolerance -- local-search optima can differ
  slightly across implementations of the identical algorithm depending on
  floating-point summation order.
- mst_prim vs mst_kruskal (or mst_default) within the SAME library on the
  SAME graph: both must find the same total weight -- a spanning-tree
  optimality fact, not a cross-library thing. Mismatch there means a bug in
  that harness, not a real difference between Prim and Kruskal.

Usage: python3 correctness_check.py [results.csv]
"""
import csv
import math
import sys
import os
from collections import defaultdict

EXACT_ALGOS = {"bfs", "dfs", "scc_tarjan"}
TIGHT_ALGOS = {"dijkstra", "mst", "tsp_nn"}
TIGHT_REL_TOL = 1e-3
LOOSE_REL_TOL = 0.05  # tsp_2opt: local-search optima may legitimately differ


def rel_diff(a, b):
    scale = max(abs(a), abs(b), 1e-9)
    return abs(a - b) / scale


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "results", "results.csv")
    if not os.path.exists(path):
        print(f"No results file at {path} -- run the harnesses first.")
        return 1

    rows = []
    with open(path) as f:
        for row in csv.DictReader(f):
            rows.append(row)
    if not rows:
        print(f"No result rows in {path}.")
        return 1

    failures = []
    repeated = defaultdict(list)
    for row in rows:
        repeated[(row["library"], row["graph"],
                  row["algorithm"])].append(row["digest"])

    validated_rows = []
    for (library, graph, algorithm), digests in sorted(repeated.items()):
        distinct = set(digests)
        if len(distinct) > 1:
            failures.append(
                f"[CONFLICTING DUPLICATES] {library}/{graph}/{algorithm}: "
                f"{sorted(distinct)}")
            continue
        validated_rows.append({"library": library, "graph": graph,
                               "algorithm": algorithm,
                               "digest": digests[0]})

    by_graph_algo = defaultdict(dict)
    by_lib_graph = defaultdict(dict)  # (library, graph) -> {algorithm: digest}
    for r in validated_rows:
        raw_algo = r["algorithm"]
        algo = "mst" if raw_algo in {"mst_default", "mst_prim", "mst_kruskal"} else raw_algo
        value = r["digest"]
        try:
            if algo in EXACT_ALGOS:
                value = int(value)
            elif algo in TIGHT_ALGOS or algo == "tsp_2opt":
                value = float(value)
                if not math.isfinite(value):
                    raise ValueError("non-finite digest")
        except ValueError:
            failures.append(
                f"[INVALID DIGEST] {r['library']}/{r['graph']}/"
                f"{raw_algo}: {r['digest']!r}")
            continue
        by_lib_graph[(r["library"], r["graph"])][raw_algo] = value
        if algo != "mst":
            by_graph_algo[(r["graph"], algo)][r["library"]] = value

    checks = 0

    mst_algos = ("mst_default", "mst_prim", "mst_kruskal")
    for (library, graph), algos in sorted(by_lib_graph.items()):
        variants = [(algo, algos[algo]) for algo in mst_algos
                    if algo in algos]
        if not variants:
            continue
        checks += 1
        consistent = True
        for i in range(len(variants)):
            for j in range(i + 1, len(variants)):
                algo_a, val_a = variants[i]
                algo_b, val_b = variants[j]
                d = rel_diff(val_a, val_b)
                if d > TIGHT_REL_TOL:
                    consistent = False
                    failures.append(
                        f"[MST VARIANT MISMATCH {d:.4f}] {library}/{graph}: "
                        f"{algo_a}={val_a} vs {algo_b}={val_b}")
        if consistent:
            by_graph_algo[(graph, "mst")][library] = variants[0][1]

    for (graph, algo), digests in sorted(by_graph_algo.items()):
        if algo not in EXACT_ALGOS and algo not in TIGHT_ALGOS and algo != "tsp_2opt":
            checks += 1
            failures.append(f"[UNSUPPORTED] {graph}/{algo}")
            continue
        if len(digests) < 2:
            checks += 1
            failures.append(
                f"[INCOMPLETE] {graph}/{algo}: fewer than two libraries")
            continue
        if algo in EXACT_ALGOS:
            values = set(digests.values())
            checks += 1
            if len(values) > 1:
                failures.append(
                    f"[EXACT MISMATCH] {graph}/{algo}: {digests}")
        elif algo in TIGHT_ALGOS or algo == "tsp_2opt":
            tol = LOOSE_REL_TOL if algo == "tsp_2opt" else TIGHT_REL_TOL
            parsed = list(digests.items())
            checks += 1
            for i in range(len(parsed)):
                for j in range(i + 1, len(parsed)):
                    lib_a, val_a = parsed[i]
                    lib_b, val_b = parsed[j]
                    d = rel_diff(val_a, val_b)
                    if d > tol:
                        failures.append(
                            f"[TOLERANCE {d:.4f} > {tol}] {graph}/{algo}: "
                            f"{lib_a}={val_a} vs {lib_b}={val_b}")

    for (library, graph), algos in sorted(by_lib_graph.items()):
        bfs = algos.get("bfs")
        dfs = algos.get("dfs")
        if bfs is not None and dfs is not None:
            checks += 1
            if bfs != dfs:
                failures.append(
                    f"[BFS != DFS] {library}/{graph}: bfs={bfs} vs dfs={dfs}")

    print(f"{checks} correctness checks across {len(rows)} result rows.")
    if failures:
        print(f"\n{len(failures)} FAILED:")
        for f in failures:
            print(" ", f)
        return 1
    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
