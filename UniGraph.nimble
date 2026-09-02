# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# UniGraph — generic, pedagogical graph data structure library. Ported
# from graphn; see git history for the port.

version       = "1.0.1"
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
    "https://github.com/pietroppeter/nimibook#v0.4.0",
    "https://github.com/lituus-lab/lituus-theme#v0.2.0"
taskRequires "docs", "https://github.com/pietroppeter/nimib#v0.4.1",
    "https://github.com/pietroppeter/nimibook#v0.4.0",
    "https://github.com/lituus-lab/lituus-theme#v0.2.0"
taskRequires "docsDeps", "https://github.com/pietroppeter/nimib#v0.4.1",
    "https://github.com/pietroppeter/nimibook#v0.4.0",
    "https://github.com/lituus-lab/lituus-theme#v0.2.0"

# nimble 0.22 exits 0 even when an `exec` inside a task fails, so a task's exit
# code says nothing about whether its body ran. Each task writes a marker as
# its last statement; `tools/gate.nim` removes the marker, runs the task, and
# fails if it is not there afterwards. `nimble canary` proves the gate still
# bites -- if that one ever passes, every other green result is worthless.
const gateExe =
  when defined(windows): "build/unigate.exe" else: "build/unigate"

template done(task: string) =
  mkDir "build/.gate"
  writeFile("build/.gate/" & task & ".ok", "")

proc gate(task: string): string =
  ## `exec gate("test")` -- builds the tool on first use.
  if not fileExists(gateExe):
    exec "nim c --hints:off -o:" & gateExe & " tools/gate.nim"
  gateExe & " " & task

task canary, "Must fail: proves the gate still catches a broken build":
  # No `done` here on purpose: the exec below raises, so the marker is never
  # written and the gate reports the failure nimble swallowed.
  exec "nim c -r --hints:off --path:src -o:build/canary tests/canary_broken.nim"

task lint, "Fail if nimpretty would reformat a source":
  exec "nim c -r --hints:off -o:build/lint_tool tools/lint.nim"
  done "lint"

task checkVGraph, "Fail on an import that climbs the layers in vgraph.cfg":
  exec "nim c -r --hints:off -o:build/vgraph_tool tools/vgraph.nim"
  done "checkVGraph"

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
  "tests/test_version.nim",
]

task test, "Nim tests (debug, contracts active)":
  for t in unitTests:
    exec "nim c -r --path:src --hints:off --outdir:build/tests " & t
  done "test"

task testRelease, "Nim tests (release, contracts compiled away)":
  for t in unitTests:
    exec "nim c -r -d:release --path:src --hints:off --outdir:build/tests " & t
  done "testRelease"

task testCi, "Nim tests (CI subset, debug)":
  exec gate("test")
  done "testCi"

task testCiRelease, "Nim tests (CI subset, release)":
  exec gate("testRelease")
  done "testCiRelease"

task testAll, "debug + release + C ABI":
  exec gate("test")
  exec gate("testRelease")
  exec gate("ctest")
  done "testAll"

task example, "Nim examples":
  exec "nim c -r --path:src --hints:off --outdir:build/examples examples/basic_example.nim"
  exec "nim c -r --path:src --hints:off --outdir:build/examples examples/traversal_example.nim"
  exec "nim c -r --path:src --hints:off --outdir:build/examples examples/kernel_comparison.nim"
  done "example"

task benchmark, "Performance oracle: CsrKernel.edges() O(V+E) fix vs the old O(V*E)":
  exec "nim c -r -d:release --path:src --hints:off --outdir:build/examples" &
       " examples/benchmark_csr_edges.nim"
  done "benchmark"

task benchmarkCross, "Build the Nim side of the cross-library benchmark suite":
  exec "nim c -d:release --threads:on --path:src --hints:off -o:benchmarks/nim/bench_unigraph" &
       " benchmarks/nim/bench_unigraph.nim"
  echo "Run: benchmarks/nim/bench_unigraph <data_dir> <output_csv> -- see benchmarks/README.md"
  done "benchmarkCross"

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
  exec "nim c --app:lib -d:noAutoInit --noMain --mm:arc -d:release -o:" & sharedLib & macArgs &
       " src/UniGraph/c_api.nim"
  done "clib"

task clibStatic, "C static library":
  exec "nim c --app:staticlib -d:noAutoInit --noMain --mm:arc -d:release -o:" & staticLib &
       " src/UniGraph/c_api.nim"
  done "clibStatic"

task clibMsvc, "C static library, MSVC ABI (Windows Python extension)":
  when defined(windows):
    # CPython on Windows is MSVC-built and cannot link MinGW output.
    exec "nim c --cc:vcc --app:staticlib -d:noAutoInit --noMain --mm:arc -d:release" &
         " -o:UniGraph.lib src/UniGraph/c_api.nim"
  else:
    echo "clibMsvc: Windows-only task; no artifact on this host."
  done "clibMsvc"

# Nim's MinGW toolchain names it mingw32-make.
let makeExe = if findExe("mingw32-make").len > 0: "mingw32-make" else: "make"

# `make -C`, not `cd dir && make`: nimble's exec runs no shell on Windows.
task ctest, "C ABI tests":
  exec gate("clibStatic")
  exec makeExe & " -C tests/c"
  done "ctest"

task cexample, "C demo":
  exec gate("clibStatic")
  exec makeExe & " -C examples/c"
  done "cexample"

task pyDeps, "Install Python build deps (setuptools, Cython, pytest) if missing":
  exec "python3 -m pip install --break-system-packages --quiet setuptools wheel \"Cython>=3.0.0\" pytest"
  # Ubuntu ships a setuptools that predates PEP 639 and cannot parse the SPDX
  # licence pyproject.toml declares. pip refuses to uninstall a distro- or
  # brew-managed package, so install over it rather than --upgrade it.
  # packaging comes with it: setuptools 77 reads packaging.licenses, which the
  # distro's older copy does not have, and it shadows the vendored one.
  exec "python3 -m pip install --break-system-packages --quiet --ignore-installed \"setuptools>=77\" \"packaging>=24.2\""
  done "pyDeps"

# The extension links the vcc static lib on Windows, the shared lib elsewhere.
task pyLib, "Build the library the Python extension links against":
  when defined(windows):
    exec gate("clibMsvc")
  else:
    exec gate("clib")
  done "pyLib"

task buildCython, "Cython extension in-place":
  exec gate("pyLib")
  exec gate("pyDeps")
  # nimscript `cd` (lib/system/nimscript.nim) changes the VM cwd for the next
  # exec without a shell, so the task works under nimble's no-shell exec on Windows.
  cd "py"
  exec "python3 setup.py build_ext --inplace"
  cd ".."
  done "buildCython"

task pyTest, "Cython extension + pytest":
  exec gate("buildCython")
  cd "py"
  exec "python3 -m pytest -q"
  cd ".."
  done "pyTest"

task pyWheel, "wheel":
  exec gate("pyLib")
  exec gate("pyDeps")
  cd "py"
  exec "python3 setup.py bdist_wheel"
  cd ".."
  done "pyWheel"

task docsDeps, "Install the docs toolchain (nimib + nimibook)":
  # This task's own taskRequires (above) is what actually fetches
  # nimib/nimibook -- nimble resolves and installs them before running the
  # body below, same as it already does for `book`/`docs` themselves. A
  # bare `nimble install <url>` here would hit an unrelated global
  # SAT-solver failure on this nimble version outside project scope.
  echo "nimib/nimibook installed."
  done "docsDeps"

task book, "Build the nimib book (needs nimib+nimibook)":
  withDir "book":
    exec "nim c -r --hints:off nbook.nim init"
    exec "nim c -r --hints:off nbook.nim build"
  done "book"

task docs, "API reference + book into pages/ — what CI publishes":
  rmDir "pages"
  exec gate("book")
  cpDir "book/__site", "pages"
  # book.json is nimibook's build state -- no page fetches it -- and it carries
  # the absolute path of the machine that built it. It does not get published.
  rmFile "pages/book.json"
  exec "nim doc --index:on --outdir:pages/api --project --hints:off src/UniGraph.nim"
  # ...and the reference wears the same theme. `nim doc` has no stylesheet
  # option, so the palette is appended to the one it just wrote. Left alone,
  # that reference ships six tokens below their contrast bar.
  exec "nim c -r --hints:off --outdir:build tools/theme_api.nim " &
       "pages/api/nimdoc.out.css"
  done "docs"

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
       " --include \"*/src/UniGraph/*\" --output-file lcov.info --quiet --ignore-errors mismatch"
  # gcov can attribute a final generated expression to EOF + 1, and that one
  # artefact answers to two names: lcov 2.0, the version ubuntu-latest installs,
  # calls it `unmapped` and rejects `range` as a category outright, while 2.5
  # calls it `range` and can filter those lines away. Ask which one is there
  # rather than assume; both were measured.
  let genhtmlRange =
    if gorgeEx("genhtml --version").output.contains("LCOV version 2.0"):
      " --ignore-errors unmapped"
    else: " --filter range --ignore-errors range"
  exec "genhtml lcov.info" & genhtmlRange &
       " --output-directory coverage --legend --quiet"
  exec "lcov --summary lcov.info"
  done "coverage"
