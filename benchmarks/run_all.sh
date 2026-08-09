#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
#
# Orchestrates the full cross-library benchmark run: generates fixtures,
# builds and runs every language harness against them, then checks that
# they all agree on the answer before anyone looks at the timings.
#
# Usage:
#   ./run_all.sh              # everything, full-size fixtures (slow, hours)
#   ./run_all.sh --smoke      # only benchmarks/data/_smoke (fast, minutes)
#   ./run_all.sh --skip-gen   # reuse whatever's already in benchmarks/data/
#
# See README.md for what each harness covers, known gaps (petgraph has no
# Prim, igraph has no NN/2-opt built in, etc.), and how to install each
# toolchain's dependencies.
set -euo pipefail
cd "$(dirname "$0")"

DATA_DIR="data"
SKIP_GEN=0
for arg in "$@"; do
  case "$arg" in
    --smoke) DATA_DIR="data/_smoke" ;;
    --skip-gen) SKIP_GEN=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

RESULTS_DIR="results"
RESULTS_CSV="$RESULTS_DIR/results.csv"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_CSV"

if [[ "$SKIP_GEN" -eq 0 ]]; then
  echo "== Generating fixtures =="
  if [[ "$DATA_DIR" == "data/_smoke" ]]; then
    python3 generate_graphs.py --smoke --output-dir "$DATA_DIR"
  else
    python3 generate_graphs.py --output-dir "$DATA_DIR"
  fi
elif [[ ! -d "$DATA_DIR" ]]; then
  echo "fixture directory does not exist: $DATA_DIR" >&2
  exit 1
fi

VENV_DIR=".venv"
python3 -m venv "$VENV_DIR"
PYTHON="$VENV_DIR/bin/python"
"$PYTHON" -m pip install --quiet 'networkx==3.5' 'python-igraph>=0.11.8'

echo "== Nim / UniGraph =="
nim c -d:release --threads:on --path:../src --hints:off -o:nim/bench_unigraph nim/bench_unigraph.nim
./nim/bench_unigraph "$DATA_DIR" "$RESULTS_CSV"

echo "== Python / networkx =="
"$PYTHON" python/bench_networkx.py "$DATA_DIR" "$RESULTS_CSV"

echo "== Python / igraph =="
"$PYTHON" python/bench_igraph.py "$DATA_DIR" "$RESULTS_CSV"

echo "== C++ / Boost =="
make -C cpp
./cpp/bench_boost "$DATA_DIR" "$RESULTS_CSV"

echo "== Rust / petgraph =="
(cd rust && cargo build --release --quiet)
./rust/target/release/bench_petgraph "$DATA_DIR" "$RESULTS_CSV"

echo "== Correctness check =="
"$PYTHON" correctness_check.py "$RESULTS_CSV"

echo
echo "Results: $RESULTS_CSV"
