# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# UniGraph — generic, pedagogical graph data structure library. Ported
# from graphn; see git history for the port.

version       = "1.0.0"
author        = "lituus-lab"
description   = "A generic, pedagogical graph data structure library for Nim"
license       = "Apache-2.0"
srcDir        = "src"

# Core: stdlib plus NimContracts (Design by Contract; require/ensure compile
# away under -d:release, matching every other Uni* lib — see AGENTS.md).
requires "nim >= 2.2.0"
requires "https://github.com/lbartoletti/NimContracts#main"

# nimib/nimibook: book build only, never required by the library core.
# The nimble registry lags upstream on both (nimib max 0.4.0, nimibook max
# 0.3.1) and 0.3.1/0.4.0 don't work together; pin the real GitHub tags,
# where nimibook v0.4.0 targets nimib v0.4.1 directly.
taskRequires "book", "https://github.com/pietroppeter/nimib#v0.4.1",
    "https://github.com/pietroppeter/nimibook#v0.4.0"
taskRequires "docs", "https://github.com/pietroppeter/nimib#v0.4.1",
    "https://github.com/pietroppeter/nimibook#v0.4.0"
taskRequires "docsDeps", "https://github.com/pietroppeter/nimib#v0.4.1",
    "https://github.com/pietroppeter/nimibook#v0.4.0"

task lint, "Fail if nimpretty would reformat a source":
  exec "nim c -r --hints:off -o:build/lint_tool tools/lint.nim"

task checkVGraph, "Fail on an import that climbs the layers in vgraph.cfg":
  exec "nim c -r --hints:off -o:build/vgraph_tool tools/vgraph.nim"

const unitTests = [
  "tests/unit/test_types.nim",
  "tests/unit/test_basic_graph.nim",
  "tests/unit/test_kernels.nim",
  "tests/unit/test_kernel_concept.nim",
  "tests/unit/test_kernel_matrix.nim",
  "tests/unit/test_traversals.nim",
  "tests/unit/test_algorithms.nim",
  "tests/unit/test_oracles.nim",
  "tests/unit/test_visualize.nim",
]

task test, "Nim tests (debug, contracts active)":
  for t in unitTests:
    exec "nim c -r --path:src --hints:off --outdir:build/tests " & t

task testRelease, "Nim tests (release, contracts compiled away)":
  for t in unitTests:
    exec "nim c -r -d:release --path:src --hints:off --outdir:build/tests " & t

task testCi, "Nim tests (CI subset, debug)":
  exec "nimble test"

task testCiRelease, "Nim tests (CI subset, release)":
  exec "nimble testRelease"

task testAll, "debug + release + C ABI":
  exec "nimble test"
  exec "nimble testRelease"
  exec "nimble ctest"

task example, "Nim examples":
  exec "nim c -r --path:src --hints:off --outdir:build/examples examples/basic_example.nim"
  exec "nim c -r --path:src --hints:off --outdir:build/examples examples/traversal_example.nim"
  exec "nim c -r --path:src --hints:off --outdir:build/examples examples/kernel_comparison.nim"

task benchmark, "Performance oracle: CsrKernel.edges() O(V+E) fix vs the old O(V*E)":
  exec "nim c -r -d:release --path:src --hints:off --outdir:build/examples" &
       " examples/benchmark_csr_edges.nim"

task benchmarkCross, "Build the Nim side of the cross-library benchmark suite":
  exec "nim c -d:release --threads:on --path:src --hints:off -o:benchmarks/nim/bench_unigraph" &
       " benchmarks/nim/bench_unigraph.nim"
  echo "Run: benchmarks/nim/bench_unigraph <data_dir> <output_csv> -- see benchmarks/README.md"

# Nim takes `-o:` literally and appends no platform extension.
const
  sharedLib =
    when defined(windows): "libUniGraph.dll"
    elif defined(macosx): "libUniGraph.dylib"
    else: "libUniGraph.so"
  staticLib = "libUniGraph.a" # MinGW `ar` on Windows, so `.a` everywhere.

  # @rpath install_name, so the copy bundled in the wheel is found at import.
  macArgs =
    when defined(macosx): " --passL:\"-Wl,-install_name,@rpath/" & sharedLib & "\""
    else: ""

task clib, "C shared library":
  exec "nim c --app:lib --noMain --mm:arc -d:release -o:" & sharedLib & macArgs &
       " src/UniGraph/c_api.nim"

task clibStatic, "C static library":
  exec "nim c --app:staticlib -d:staticNoAutoInit --noMain --mm:arc -d:release -o:" & staticLib &
       " src/UniGraph/c_api.nim"

task clibMsvc, "C static library, MSVC ABI (Windows Python extension)":
  when defined(windows):
    # CPython on Windows is MSVC-built and cannot link MinGW output.
    exec "nim c --cc:vcc --app:staticlib -d:staticNoAutoInit --noMain --mm:arc -d:release" &
         " -o:UniGraph.lib src/UniGraph/c_api.nim"
  else:
    echo "clibMsvc: Windows-only task; no artifact on this host."

# Nim's MinGW toolchain names it mingw32-make.
let makeExe = if findExe("mingw32-make").len > 0: "mingw32-make" else: "make"

# `make -C`, not `cd dir && make`: nimble's exec runs no shell on Windows.
task ctest, "C ABI tests":
  exec "nimble clibStatic"
  exec makeExe & " -C tests/c"

task cexample, "C demo":
  exec "nimble clibStatic"
  exec makeExe & " -C examples/c"

task pyDeps, "Install Python build deps (setuptools, Cython, pytest) if missing":
  exec "python3 -m pip install --break-system-packages --quiet setuptools wheel \"Cython>=3.0.0\" pytest"

# The extension links the vcc static lib on Windows, the shared lib elsewhere.
task pyLib, "Build the library the Python extension links against":
  when defined(windows):
    exec "nimble clibMsvc"
  else:
    exec "nimble clib"

task buildCython, "Cython extension in-place":
  exec "nimble pyLib"
  exec "nimble pyDeps"
  # nimscript `cd` (lib/system/nimscript.nim) changes the VM cwd for the next
  # exec without a shell, so the task works under nimble's no-shell exec on Windows.
  cd "py"
  exec "python3 setup.py build_ext --inplace"
  cd ".."

task pyTest, "Cython extension + pytest":
  exec "nimble buildCython"
  cd "py"
  exec "python3 -m pytest -q"
  cd ".."

task pyWheel, "wheel":
  exec "nimble pyLib"
  exec "nimble pyDeps"
  cd "py"
  exec "python3 setup.py bdist_wheel"
  cd ".."

task docsDeps, "Install the docs toolchain (nimib + nimibook)":
  # This task's own taskRequires (above) is what actually fetches
  # nimib/nimibook -- nimble resolves and installs them before running the
  # body below, same as it already does for `book`/`docs` themselves. A
  # bare `nimble install <url>` here would hit an unrelated global
  # SAT-solver failure on this nimble version outside project scope.
  echo "nimib/nimibook installed."

task book, "Build the nimib book (needs nimib+nimibook)":
  withDir "book":
    exec "nim c -r --hints:off nbook.nim init"
    exec "nim c -r --hints:off nbook.nim build"

task docs, "API reference + book into pages/ — what CI publishes":
  rmDir "pages"
  exec "nim doc --index:on --outdir:pages/api --project --hints:off src/UniGraph.nim"
  exec "nimble book"
  cpDir "book/__site", "pages"

task coverage, "LCOV + HTML coverage report for the Nim sources (needs lcov)":
  # gcov and lcov driven directly, no coco. Linux and macOS only.
  # --debugger:native attributes lines to the .nim sources, not the generated C.
  # --include keeps stdlib out of the final trace. Every error category remains
  # fatal except the documented EOF+1 range artifact handled below.
  let cache = "build/covcache"
  rmDir cache
  rmDir "coverage"
  var testIndex = 0
  for t in unitTests:
    let testCache = cache & "/" & $testIndex
    exec "nim c --path:src --nimcache:" & testCache &
         " --debugger:native --passC:--coverage --passL:--coverage" &
         " --outdir:build/tests " & t
    inc testIndex
  exec "./build/tests/test_types"
  exec "./build/tests/test_basic_graph"
  exec "./build/tests/test_kernels"
  exec "./build/tests/test_kernel_concept"
  exec "./build/tests/test_kernel_matrix"
  exec "./build/tests/test_traversals"
  exec "./build/tests/test_algorithms"
  exec "./build/tests/test_oracles"
  exec "./build/tests/test_visualize"
  # lcov applies --include after gcov has parsed every object. Remove coverage
  # pairs for the test harness and stdlib first, so only UniGraph is captured.
  exec "find " & cache &
       " -type f \\( -name '*.gcda' -o -name '*.gcno' \\)" &
       " ! -name '@pUniGraph@*' -delete"
  # Nim emits several compiler-generated destructors at the same source line.
  # Collect line coverage only; function attribution for those symbols is not
  # well-defined and lcov 2.x correctly rejects it as inconsistent.
  exec "lcov --capture --no-function-coverage --directory " & cache &
       " --base-directory ." &
       " --include \"*/src/UniGraph/*\" --output-file lcov.info --quiet"
  # gcov can attribute a final generated expression to EOF + 1; `range` is
  # genhtml's documented filter for precisely that compiler artifact. lcov 2.x
  # requires the matching category allowance before it applies the filter.
  exec "genhtml lcov.info --filter range --ignore-errors range" &
       " --output-directory coverage" &
       " --legend --quiet"
  exec "lcov --summary lcov.info"
