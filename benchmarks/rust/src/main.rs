// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
//! Cross-library benchmark harness: petgraph side.
//!
//! Reads the *.edges / tsp/*.tsp fixtures produced by ../generate_graphs.py
//! (same files every language harness reads) and appends one CSV row per
//! (library, algorithm, graph) run to the path given as the second
//! argument. Mirrors ../nim/bench_unigraph.nim exactly: same digests, same
//! CSV contract, same nearest-neighbor/2-opt loop structure for TSP.
//!
//! Graphs are always built as a Directed petgraph graph; undirected
//! fixtures get both edge directions added explicitly (matching the Nim
//! harness's always-directed ListKernel). petgraph ships exactly one MST
//! algorithm (Kruskal-based, via `min_spanning_tree`) -- no separate Prim,
//! so only a single `mst_default` row is recorded (see README.md).

use petgraph::algo::{dijkstra, min_spanning_tree, tarjan_scc};
use petgraph::data::Element;
use petgraph::graph::{DiGraph, NodeIndex};
use petgraph::visit::{Bfs, Dfs};
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Instant;

struct GraphData {
    n: usize,
    m: usize,
    directed: bool,
    weighted: bool,
    start: usize,
    edges: Vec<(usize, usize, f64)>,
}

fn load_graph(path: &Path) -> GraphData {
    let content = fs::read_to_string(path).expect("read edges file");
    let mut lines = content.lines();
    let header: Vec<&str> = lines.next().expect("header line").split_whitespace().collect();
    let n: usize = header[0].parse().unwrap();
    let m: usize = header[1].parse().unwrap();
    let directed = header[2].parse::<i32>().unwrap() != 0;
    let weighted = header[3].parse::<i32>().unwrap() != 0;
    let start: usize = header[4].parse().unwrap();
    let mut edges = Vec::with_capacity(m);
    for line in lines.take(m) {
        let p: Vec<&str> = line.split_whitespace().collect();
        if p.len() < 3 {
            continue;
        }
        let u: usize = p[0].parse().unwrap();
        let v: usize = p[1].parse().unwrap();
        let w: f64 = p[2].parse().unwrap();
        edges.push((u, v, w));
    }
    GraphData { n, m, directed, weighted, start, edges }
}

/// Always builds a Directed graph; undirected fixtures get both directions
/// added explicitly (edges are listed once in the file for undirected
/// graphs -- see README.md), matching the Nim harness's ListKernel.
fn build_graph(g: &GraphData) -> (DiGraph<(), f64>, Vec<NodeIndex>) {
    let cap = if g.directed { g.edges.len() } else { g.edges.len() * 2 };
    let mut graph = DiGraph::<(), f64>::with_capacity(g.n, cap);
    let mut ids = Vec::with_capacity(g.n);
    for _ in 0..g.n {
        ids.push(graph.add_node(()));
    }
    for &(u, v, w) in &g.edges {
        graph.add_edge(ids[u], ids[v], w);
        if !g.directed {
            graph.add_edge(ids[v], ids[u], w);
        }
    }
    (graph, ids)
}

fn record(
    rows: &mut Vec<String>,
    algorithm: &str,
    graph: &str,
    n: usize,
    m: usize,
    directed: bool,
    weighted: bool,
    load_s: f64,
    algo_s: f64,
    digest: &str,
) {
    rows.push(format!(
        "rust,petgraph,{},{},{},{},{},{},{:.6},{:.6},{}",
        algorithm, graph, n, m, directed as u8, weighted as u8, load_s, algo_s, digest
    ));
    eprintln!(
        "  petgraph/{} on {}: load={:.3}s algo={:.3}s digest={}",
        algorithm, graph, load_s, algo_s, digest
    );
}

fn run_graph_benchmarks(path: &Path, name: &str, rows: &mut Vec<String>) {
    eprintln!("Graph: {}", name);

    let t0 = Instant::now();
    let g = load_graph(path);
    let load_s = t0.elapsed().as_secs_f64();

    let t1 = Instant::now();
    let (graph, ids) = build_graph(&g);
    let build_s = t1.elapsed().as_secs_f64();
    let total_load_s = load_s + build_s;

    let start = ids[g.start];

    // bfs
    {
        let t = Instant::now();
        let mut bfs = Bfs::new(&graph, start);
        let mut count = 0usize;
        while bfs.next(&graph).is_some() {
            count += 1;
        }
        let algo_s = t.elapsed().as_secs_f64();
        record(rows, "bfs", name, g.n, g.m, g.directed, g.weighted, total_load_s, algo_s,
            &count.to_string());
    }

    // dfs
    {
        let t = Instant::now();
        let mut dfs = Dfs::new(&graph, start);
        let mut count = 0usize;
        while dfs.next(&graph).is_some() {
            count += 1;
        }
        let algo_s = t.elapsed().as_secs_f64();
        record(rows, "dfs", name, g.n, g.m, g.directed, g.weighted, total_load_s, algo_s,
            &count.to_string());
    }

    // dijkstra (weighted only)
    if g.weighted {
        let t = Instant::now();
        let distances = dijkstra(&graph, start, None, |e| *e.weight());
        let algo_s = t.elapsed().as_secs_f64();
        let total: f64 = distances.values().sum();
        record(rows, "dijkstra", name, g.n, g.m, g.directed, g.weighted, total_load_s, algo_s,
            &format!("{:.2}", total));
    }

    // mst_default (undirected only) -- petgraph has one MST algorithm
    // (Kruskal via UnionFind, min_spanning_tree); no separate Prim to
    // compare, so no mst_prim/mst_kruskal split like the other libraries.
    if !g.directed {
        let t = Instant::now();
        let mst = min_spanning_tree(&graph);
        let algo_s = t.elapsed().as_secs_f64();
        let mut total = 0.0;
        for elem in mst {
            if let Element::Edge { weight, .. } = elem {
                total += weight;
            }
        }
        record(rows, "mst_default", name, g.n, g.m, g.directed, g.weighted, total_load_s,
            algo_s, &format!("{:.2}", total));
    }

    // scc_tarjan (directed only)
    if g.directed {
        let t = Instant::now();
        let sccs = tarjan_scc(&graph);
        let algo_s = t.elapsed().as_secs_f64();
        record(rows, "scc_tarjan", name, g.n, g.m, g.directed, g.weighted, total_load_s,
            algo_s, &sccs.len().to_string());
    }
}

// ============================================================================
// TSP: standalone nearest-neighbor / 2-opt on a coordinate distance function.
// Mirrors ../nim/bench_unigraph.nim's nearestNeighbor/twoOpt exactly (same
// candidate scan order, same first-improvement 2-opt loop) so digests are
// directly comparable across languages -- see README.md.
// ============================================================================

fn load_coords(path: &Path) -> Vec<(f64, f64)> {
    let content = fs::read_to_string(path).expect("read tsp file");
    let mut lines = content.lines();
    let n: usize = lines.next().expect("n line").trim().parse().unwrap();
    let mut coords = Vec::with_capacity(n);
    for line in lines.take(n) {
        let p: Vec<&str> = line.split_whitespace().collect();
        let x: f64 = p[0].parse().unwrap();
        let y: f64 = p[1].parse().unwrap();
        coords.push((x, y));
    }
    coords
}

fn dist(coords: &[(f64, f64)], i: usize, j: usize) -> f64 {
    let (xi, yi) = coords[i];
    let (xj, yj) = coords[j];
    ((xi - xj).powi(2) + (yi - yj).powi(2)).sqrt()
}

fn tour_cost(coords: &[(f64, f64)], path: &[usize]) -> f64 {
    let mut total = 0.0;
    for w in path.windows(2) {
        total += dist(coords, w[0], w[1]);
    }
    total += dist(coords, *path.last().unwrap(), path[0]);
    total
}

fn nearest_neighbor(coords: &[(f64, f64)], start: usize) -> (Vec<usize>, f64) {
    let n = coords.len();
    let mut path = vec![start];
    let mut visited = vec![false; n];
    visited[start] = true;
    while path.len() < n {
        let current = *path.last().unwrap();
        let mut best = usize::MAX;
        let mut best_dist = f64::INFINITY;
        for v in 0..n {
            if !visited[v] {
                let d = dist(coords, current, v);
                if d < best_dist {
                    best_dist = d;
                    best = v;
                }
            }
        }
        visited[best] = true;
        path.push(best);
    }
    let cost = tour_cost(coords, &path);
    (path, cost)
}

fn two_opt(coords: &[(f64, f64)], initial: &[usize], max_iterations: usize) -> (Vec<usize>, f64) {
    let mut path = initial.to_vec();
    let mut cost = tour_cost(coords, &path);
    let mut improved = true;
    let mut iterations = 0;
    while improved && iterations < max_iterations {
        improved = false;
        iterations += 1;
        for i in 0..path.len() - 1 {
            for j in (i + 1)..path.len() {
                let mut new_path = path.clone();
                new_path[i..=j].reverse();
                let new_cost = tour_cost(coords, &new_path);
                if new_cost < cost {
                    cost = new_cost;
                    path = new_path;
                    improved = true;
                }
            }
        }
    }
    (path, cost)
}

fn run_tsp_benchmarks(path: &Path, name: &str, rows: &mut Vec<String>) {
    eprintln!("TSP: {}", name);

    let t0 = Instant::now();
    let coords = load_coords(path);
    let load_s = t0.elapsed().as_secs_f64();
    let n = coords.len();

    let t1 = Instant::now();
    let (nn_path, nn_cost) = nearest_neighbor(&coords, 0);
    let nn_s = t1.elapsed().as_secs_f64();
    record(rows, "tsp_nn", name, n, 0, false, true, load_s, nn_s, &format!("{:.2}", nn_cost));

    let t2 = Instant::now();
    let (_, opt_cost) = two_opt(&coords, &nn_path, 1000);
    let opt_s = t2.elapsed().as_secs_f64();
    record(rows, "tsp_2opt", name, n, 0, false, true, load_s, opt_s, &format!("{:.2}", opt_cost));
}

fn main() {
    // petgraph::algo::tarjan_scc recurses per DFS-tree edge; on a directed
    // million-vertex graph the recursion depth can overflow the default 8MB
    // OS thread stack. Rust threads can be given an arbitrary stack size
    // (unlike the main thread, which is capped by the OS), so the actual
    // work runs on a dedicated thread with a generous one instead of
    // depending on the caller's `ulimit -s`.
    let handle = thread::Builder::new()
        .stack_size(1 << 30) // 1 GiB
        .spawn(run)
        .expect("spawn worker thread");
    handle.join().expect("worker thread panicked");
}

fn run() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: bench_petgraph <data_dir> <output_csv>");
        std::process::exit(1);
    }
    let data_dir = PathBuf::from(&args[1]);
    let output_csv = PathBuf::from(&args[2]);

    let mut rows: Vec<String> = Vec::new();

    let mut graph_files: Vec<PathBuf> = fs::read_dir(&data_dir)
        .expect("read data_dir")
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.is_file() && p.extension().map_or(false, |ext| ext == "edges"))
        .collect();
    graph_files.sort();

    let tsp_dir = data_dir.join("tsp");
    let tsp_files: Vec<PathBuf> = fs::read_dir(&tsp_dir)
        .map(|entries| {
            let mut v: Vec<PathBuf> = entries
                .filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| p.is_file() && p.extension().map_or(false, |ext| ext == "tsp"))
                .collect();
            v.sort();
            v
        })
        .unwrap_or_default(); // no tsp/ subdir -- just skip that benchmark track

    for path in &graph_files {
        let name = path.file_stem().unwrap().to_string_lossy().to_string();
        run_graph_benchmarks(path, &name, &mut rows);
    }
    for path in &tsp_files {
        let name = path.file_stem().unwrap().to_string_lossy().to_string();
        run_tsp_benchmarks(path, &name, &mut rows);
    }

    let write_header = !output_csv.exists();
    let mut f = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&output_csv)
        .expect("open output csv");
    if write_header {
        writeln!(f, "lang,library,algorithm,graph,n,m,directed,weighted,load_seconds,algo_seconds,digest").unwrap();
    }
    for line in &rows {
        writeln!(f, "{}", line).unwrap();
    }
}
