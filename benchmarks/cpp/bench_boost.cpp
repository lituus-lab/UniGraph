// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
// Cross-library benchmark harness: Boost Graph Library side.
//
// Reads the *.edges / tsp/*.tsp fixtures produced by ../generate_graphs.py
// (same files every language harness reads) and appends one CSV row per
// (library, algorithm, graph) run to the path given as the second argument.
// See ../nim/bench_unigraph.nim for the reference semantics this mirrors
// (exact algorithm loop structure for TSP, exact CSV contract) and
// ../README.md for file formats and cross-check digests. TSP runs a
// standalone nearest-neighbor/2-opt directly on the coordinate array --
// Boost has no TSP heuristic, and materializing a complete adjacency_list
// for thousands of cities would be wasteful.
#include <boost/graph/adjacency_list.hpp>
#include <boost/graph/breadth_first_search.hpp>
#include <boost/graph/depth_first_search.hpp>
#include <boost/graph/dijkstra_shortest_paths.hpp>
#include <boost/graph/kruskal_min_spanning_tree.hpp>
#include <boost/graph/prim_minimum_spanning_tree.hpp>
#include <boost/graph/strong_components.hpp>
#include <boost/property_map/property_map.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <set>
#include <string>
#include <tuple>
#include <vector>

namespace fs = std::filesystem;

using UndirGraph = boost::adjacency_list<boost::vecS, boost::vecS, boost::undirectedS,
    boost::no_property, boost::property<boost::edge_weight_t, double>>;
using DirGraph = boost::adjacency_list<boost::vecS, boost::vecS, boost::directedS,
    boost::no_property, boost::property<boost::edge_weight_t, double>>;

// ============================================================================
// Timing / CSV plumbing
// ============================================================================

template <typename F>
double timeSeconds(F&& f) {
  auto t0 = std::chrono::steady_clock::now();
  f();
  auto t1 = std::chrono::steady_clock::now();
  return std::chrono::duration<double>(t1 - t0).count();
}

std::string fmt2(double v) {
  std::ostringstream oss;
  oss << std::fixed << std::setprecision(2) << v;
  return oss.str();
}

static std::vector<std::string> csvLines;

void record(const std::string& algo, const std::string& graph, int n, int m,
    bool directed, bool weighted, double loadS, double algoS, const std::string& digest) {
  std::ostringstream oss;
  oss << "cpp,boost," << algo << "," << graph << "," << n << "," << m << ","
      << (directed ? 1 : 0) << "," << (weighted ? 1 : 0) << "," << std::fixed
      << std::setprecision(6) << loadS << "," << algoS << "," << digest;
  csvLines.push_back(oss.str());
  std::cerr << "  boost/" << algo << " on " << graph << ": load=" << std::fixed
             << std::setprecision(3) << loadS << "s algo=" << algoS << "s digest=" << digest
             << "\n";
}

// ============================================================================
// Graph loading: *.edges -> (header fields, edge list)
// ============================================================================

struct GraphData {
  int n = 0, m = 0;
  bool directed = false, weighted = false;
  int start = 0; // precomputed max-degree vertex -- see generate_graphs.py
  std::vector<std::tuple<int, int, double>> edges;
};

GraphData loadGraph(const std::string& path) {
  std::ifstream in(path);
  if (!in) throw std::runtime_error("cannot open graph fixture: " + path);
  GraphData g;
  std::string line;
  if (!std::getline(in, line)) throw std::runtime_error("missing graph header: " + path);
  {
    std::istringstream hs(line);
    int d = 0, w = 0;
    if (!(hs >> g.n >> g.m >> d >> w >> g.start) || g.n <= 0 || g.m < 0 ||
        (d != 0 && d != 1) || (w != 0 && w != 1) || g.start < 0 || g.start >= g.n)
      throw std::runtime_error("invalid graph header: " + path);
    g.directed = d != 0;
    g.weighted = w != 0;
  }
  g.edges.reserve(g.m);
  std::set<std::pair<int, int>> seen;
  for (int i = 0; i < g.m; ++i) {
    if (!std::getline(in, line)) throw std::runtime_error("truncated graph fixture: " + path);
    std::istringstream ls(line);
    int u = 0, v = 0;
    double w = 0.0;
    if (!(ls >> u >> v >> w) || u < 0 || u >= g.n || v < 0 || v >= g.n ||
        !std::isfinite(w))
      throw std::runtime_error("invalid graph edge: " + path);
    auto key = g.directed ? std::make_pair(u, v)
                          : std::make_pair((std::min)(u, v), (std::max)(u, v));
    if (seen.insert(key).second) g.edges.emplace_back(u, v, w);
  }
  return g;
}

// ============================================================================
// BFS/DFS reachability visitors: count discovered vertices from a single
// source. depth_first_visit (lowercase) restricts DFS to the reachable set --
// depth_first_search (whole-graph, iterates every vertex as a root) would not.
// ============================================================================

struct BfsCounter : public boost::default_bfs_visitor {
  int& count;
  explicit BfsCounter(int& c) : count(c) {}
  template <typename Vertex, typename Graph>
  void discover_vertex(Vertex, const Graph&) {
    ++count;
  }
};

struct DfsCounter : public boost::default_dfs_visitor {
  int& count;
  explicit DfsCounter(int& c) : count(c) {}
  template <typename Vertex, typename Graph>
  void discover_vertex(Vertex, const Graph&) {
    ++count;
  }
};

// ============================================================================
// Per-graph algorithm suite, one instantiation per directedness (the
// property map / algorithm set differs: MST only makes sense undirected,
// SCC only directed).
// ============================================================================

void processUndirected(const GraphData& g, const std::string& name, double loadS) {
  UndirGraph graph;
  double buildS = timeSeconds([&] {
    graph = UndirGraph(g.n);
    for (auto& [u, v, w] : g.edges) boost::add_edge(u, v, w, graph);
  });
  double totalLoadS = loadS + buildS;
  auto start = static_cast<UndirGraph::vertex_descriptor>(g.start);

  {
    int count = 0;
    BfsCounter vis(count);
    double algoS = timeSeconds([&] { boost::breadth_first_search(graph, start, boost::visitor(vis)); });
    record("bfs", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, std::to_string(count));
  }
  {
    int count = 0;
    DfsCounter vis(count);
    std::vector<boost::default_color_type> colors(boost::num_vertices(graph), boost::white_color);
    auto colorMap = boost::make_iterator_property_map(colors.begin(), boost::get(boost::vertex_index, graph));
    double algoS = timeSeconds([&] { boost::depth_first_visit(graph, start, vis, colorMap); });
    record("dfs", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, std::to_string(count));
  }
  if (g.weighted) {
    std::vector<double> distances(boost::num_vertices(graph), (std::numeric_limits<double>::max)());
    auto distMap = boost::make_iterator_property_map(distances.begin(), boost::get(boost::vertex_index, graph));
    double algoS = timeSeconds(
        [&] { boost::dijkstra_shortest_paths(graph, start, boost::distance_map(distMap)); });
    double total = 0.0;
    for (double d : distances)
      if (d < (std::numeric_limits<double>::max)()) total += d;
    record("dijkstra", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, fmt2(total));
  }
  {
    // This Boost version's prim_minimum_spanning_tree is literally
    // dijkstra_shortest_paths with a tweaked compare/combine (see
    // prim_minimum_spanning_tree.hpp): it only explores the root's
    // connected component, like any single-source shortest-path call, and
    // silently leaves other components untouched (pred[v] == v) rather than
    // erroring. On a graph that isn't fully connected (this fixture's own
    // bfs digest below start is less than n) a single root_vertex(start)
    // call would only span that one component while kruskal spans the
    // whole forest -- so loop Prim over each unvisited component to build
    // the full minimum spanning forest, matching kruskal's coverage.
    // Read each component's weight back from the distance_map Prim itself
    // fills in (a vertex's final distance is the weight of the edge that
    // attached it to the tree) rather than re-querying edge(pred[v], v, g)
    // afterwards -- with parallel edges present (a handful, from the
    // generator; see notes above), that query can land on the wrong
    // duplicate and silently produce a total that disagrees with Kruskal's.
    double total = 0.0;
    std::vector<bool> visited(g.n, false);
    std::vector<UndirGraph::vertex_descriptor> pred(boost::num_vertices(graph));
    std::vector<double> dist(boost::num_vertices(graph), 0.0);
    double algoS = timeSeconds([&] {
      for (int root = 0; root < g.n; ++root) {
        if (visited[root]) continue;
        if (boost::out_degree(static_cast<UndirGraph::vertex_descriptor>(root), graph) == 0) {
          visited[root] = true;
          continue;
        }
        std::fill(pred.begin(), pred.end(), UndirGraph::null_vertex());
        std::fill(dist.begin(), dist.end(), 0.0);
        auto distMap = boost::make_iterator_property_map(dist.begin(), boost::get(boost::vertex_index, graph));
        boost::prim_minimum_spanning_tree(graph, &pred[0], boost::distance_map(distMap).root_vertex(
            static_cast<UndirGraph::vertex_descriptor>(root)));
        for (std::size_t v = 0; v < pred.size(); ++v) {
          if (!visited[v] && (static_cast<int>(v) == root || pred[v] != v)) {
            visited[v] = true;
            if (pred[v] != v) total += dist[v];
          }
        }
      }
    });
    record("mst_prim", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, fmt2(total));
  }
  {
    std::vector<UndirGraph::edge_descriptor> tree;
    double algoS =
        timeSeconds([&] { boost::kruskal_minimum_spanning_tree(graph, std::back_inserter(tree)); });
    auto weightMap = boost::get(boost::edge_weight, graph);
    double total = 0.0;
    for (auto& e : tree) total += boost::get(weightMap, e);
    record("mst_kruskal", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, fmt2(total));
  }
}

void processDirected(const GraphData& g, const std::string& name, double loadS) {
  DirGraph graph;
  double buildS = timeSeconds([&] {
    graph = DirGraph(g.n);
    for (auto& [u, v, w] : g.edges) boost::add_edge(u, v, w, graph);
  });
  double totalLoadS = loadS + buildS;
  auto start = static_cast<DirGraph::vertex_descriptor>(g.start);

  {
    int count = 0;
    BfsCounter vis(count);
    double algoS = timeSeconds([&] { boost::breadth_first_search(graph, start, boost::visitor(vis)); });
    record("bfs", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, std::to_string(count));
  }
  {
    int count = 0;
    DfsCounter vis(count);
    std::vector<boost::default_color_type> colors(boost::num_vertices(graph), boost::white_color);
    auto colorMap = boost::make_iterator_property_map(colors.begin(), boost::get(boost::vertex_index, graph));
    double algoS = timeSeconds([&] { boost::depth_first_visit(graph, start, vis, colorMap); });
    record("dfs", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, std::to_string(count));
  }
  if (g.weighted) {
    std::vector<double> distances(boost::num_vertices(graph), (std::numeric_limits<double>::max)());
    auto distMap = boost::make_iterator_property_map(distances.begin(), boost::get(boost::vertex_index, graph));
    double algoS = timeSeconds(
        [&] { boost::dijkstra_shortest_paths(graph, start, boost::distance_map(distMap)); });
    double total = 0.0;
    for (double d : distances)
      if (d < (std::numeric_limits<double>::max)()) total += d;
    record("dijkstra", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, fmt2(total));
  }
  {
    std::vector<int> component(boost::num_vertices(graph));
    int numComp = 0;
    double algoS = timeSeconds([&] {
      numComp = boost::strong_components(
          graph, boost::make_iterator_property_map(component.begin(), boost::get(boost::vertex_index, graph)));
    });
    record("scc_tarjan", name, g.n, g.m, g.directed, g.weighted, totalLoadS, algoS, std::to_string(numComp));
  }
}

void runGraphBenchmarks(const std::string& path, const std::string& name) {
  std::cerr << "Graph: " << name << "\n";
  GraphData g;
  double loadS = timeSeconds([&] { g = loadGraph(path); });
  if (g.directed)
    processDirected(g, name, loadS);
  else
    processUndirected(g, name, loadS);
}

// ============================================================================
// TSP: standalone nearest-neighbor / 2-opt on a coordinate distance function.
// Mirrors ../nim/bench_unigraph.nim's nearestNeighbor/twoOpt exactly (same
// candidate scan order, same first-improvement 2-opt loop) so digests are
// directly comparable to the other languages -- see ../README.md.
// ============================================================================

std::vector<std::pair<double, double>> loadCoords(const std::string& path) {
  std::ifstream in(path);
  if (!in) throw std::runtime_error("cannot open TSP fixture: " + path);
  std::string line;
  if (!std::getline(in, line)) throw std::runtime_error("missing TSP header: " + path);
  std::size_t parsed = 0;
  int n = std::stoi(line, &parsed);
  if (parsed != line.size() || n <= 0) throw std::runtime_error("invalid TSP header: " + path);
  std::vector<std::pair<double, double>> coords;
  coords.reserve(n);
  for (int i = 0; i < n; ++i) {
    if (!std::getline(in, line)) throw std::runtime_error("truncated TSP fixture: " + path);
    std::istringstream ls(line);
    double x = 0.0, y = 0.0;
    if (!(ls >> x >> y) || !std::isfinite(x) || !std::isfinite(y))
      throw std::runtime_error("invalid TSP coordinate: " + path);
    coords.emplace_back(x, y);
  }
  return coords;
}

double dist(const std::vector<std::pair<double, double>>& coords, int i, int j) {
  double dx = coords[i].first - coords[j].first;
  double dy = coords[i].second - coords[j].second;
  return std::sqrt(dx * dx + dy * dy);
}

double tourCost(const std::vector<std::pair<double, double>>& coords, const std::vector<int>& path) {
  double total = 0.0;
  for (std::size_t i = 0; i + 1 < path.size(); ++i) total += dist(coords, path[i], path[i + 1]);
  total += dist(coords, path.back(), path.front());
  return total;
}

std::pair<std::vector<int>, double> nearestNeighbor(
    const std::vector<std::pair<double, double>>& coords, int start) {
  int n = static_cast<int>(coords.size());
  std::vector<int> path{start};
  path.reserve(n);
  std::vector<bool> visited(n, false);
  visited[start] = true;
  while (static_cast<int>(path.size()) < n) {
    int current = path.back();
    int best = -1;
    double bestDist = std::numeric_limits<double>::infinity();
    for (int v = 0; v < n; ++v) {
      if (!visited[v]) {
        double d = dist(coords, current, v);
        if (d < bestDist) {
          bestDist = d;
          best = v;
        }
      }
    }
    if (best < 0) throw std::runtime_error("nearest-neighbor search found no candidate");
    visited[best] = true;
    path.push_back(best);
  }
  return {path, tourCost(coords, path)};
}

std::pair<std::vector<int>, double> twoOpt(
    const std::vector<std::pair<double, double>>& coords, std::vector<int> initial, int maxIterations) {
  std::vector<int> path = std::move(initial);
  double cost = tourCost(coords, path);
  bool improved = true;
  int iterations = 0;
  while (improved && iterations < maxIterations) {
    improved = false;
    ++iterations;
    for (std::size_t i = 0; i + 1 < path.size(); ++i) {
      for (std::size_t j = i + 1; j < path.size(); ++j) {
        std::vector<int> newPath = path;
        std::size_t left = i, right = j;
        while (left < right) {
          std::swap(newPath[left], newPath[right]);
          ++left;
          --right;
        }
        double newCost = tourCost(coords, newPath);
        if (newCost < cost) {
          cost = newCost;
          path = newPath;
          improved = true;
        }
      }
    }
  }
  return {path, cost};
}

void runTspBenchmarks(const std::string& path, const std::string& name) {
  std::cerr << "TSP: " << name << "\n";
  std::vector<std::pair<double, double>> coords;
  double loadS = timeSeconds([&] { coords = loadCoords(path); });
  int n = static_cast<int>(coords.size());

  std::vector<int> nnPath;
  double nnCost = 0.0;
  double nnS = timeSeconds([&] {
    auto [p, c] = nearestNeighbor(coords, 0);
    nnPath = p;
    nnCost = c;
  });
  record("tsp_nn", name, n, 0, false, true, loadS, nnS, fmt2(nnCost));

  double optCost = 0.0;
  double optS = timeSeconds([&] {
    auto [p, c] = twoOpt(coords, nnPath, 1000);
    optCost = c;
  });
  record("tsp_2opt", name, n, 0, false, true, loadS, optS, fmt2(optCost));
}

// ============================================================================

int main(int argc, char** argv) {
  if (argc < 3) {
    std::cerr << "usage: bench_boost <data_dir> <output_csv>\n";
    return 1;
  }
  try {
    std::string dataDir = argv[1];
    std::string outputCsv = argv[2];

    std::vector<std::string> graphFiles, tspFiles;
    for (auto& entry : fs::directory_iterator(dataDir)) {
      if (entry.is_regular_file() && entry.path().extension() == ".edges")
        graphFiles.push_back(entry.path().string());
    }
    fs::path tspDir = fs::path(dataDir) / "tsp";
    if (fs::exists(tspDir)) {
      for (auto& entry : fs::directory_iterator(tspDir)) {
        if (entry.is_regular_file() && entry.path().extension() == ".tsp")
          tspFiles.push_back(entry.path().string());
      }
    }
    if (graphFiles.empty() && tspFiles.empty())
      throw std::runtime_error("no benchmark fixtures in: " + dataDir);
    std::sort(graphFiles.begin(), graphFiles.end());
    std::sort(tspFiles.begin(), tspFiles.end());

    for (auto& path : graphFiles) runGraphBenchmarks(path, fs::path(path).stem().string());
    for (auto& path : tspFiles) runTspBenchmarks(path, fs::path(path).stem().string());

    bool writeHeader = !fs::exists(outputCsv);
    std::ofstream f(outputCsv, std::ios::app);
    if (!f) throw std::runtime_error("cannot open output CSV: " + outputCsv);
    if (writeHeader)
      f << "lang,library,algorithm,graph,n,m,directed,weighted,load_seconds,algo_seconds,digest\n";
    for (auto& line : csvLines) f << line << "\n";
    f.flush();
    if (!f) throw std::runtime_error("cannot write output CSV: " + outputCsv);
    return 0;
  } catch (const fs::filesystem_error& e) {
    std::cerr << "filesystem error: " << e.what() << "\n";
  } catch (const std::invalid_argument& e) {
    std::cerr << "invalid numeric input: " << e.what() << "\n";
  } catch (const std::out_of_range& e) {
    std::cerr << "numeric input out of range: " << e.what() << "\n";
  } catch (const std::exception& e) {
    std::cerr << "benchmark error: " << e.what() << "\n";
  }
  return 1;
}
