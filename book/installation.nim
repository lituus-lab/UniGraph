# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib, nimibook
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nbText: "# Installation"
nbText: """
To install **UniGraph**, you have several options depending on your needs.

## Prerequisites

- **Nim** >= 2.2.0
- **Nimble** (comes with Nim)

## Option 1: Clone and Install from Source

This is the recommended method for development and learning.

```bash
# Clone the repository
git clone https://github.com/lituus-lab/UniGraph
cd UniGraph

# Install globally
nimble install

# Or install locally (in project directory)
nimble develop
```

## Option 2: Add to Your Project

Add UniGraph as a dependency in your `.nimble` file:

```nim
# myproject.nimble
version       = "1.0.0"
author        = "Your Name"
description   = "My graph project"
requires "nim >= 2.2.0"
requires "UniGraph >= 1.0.0"
```

Then install:

```bash
nimble install
```

## Option 3: Use Nimble Directly

```bash
nimble install UniGraph
```

## Verify Installation

Create a test file `test.nim`:

```nim
import UniGraph

echo "UniGraph version: ", UniGraph.Version

var g = newImmutableGraph[string, float](Directed)
let (g2, v) = g.addVertex("Test")
echo "Successfully created graph with ", g2.vertexCount, " vertex"
```

Compile and run:

```bash
nim c -r test.nim
```

Expected output:
```
UniGraph version: 1.0.0
Successfully created graph with 1 vertex
```

## Building the Documentation

The book you are reading is written in Nim using nimib/nimibook — there is
one edition, in English.

```bash
nimble docsDeps  # install nimib + nimibook (needed once)
nimble book      # build the book -> book/__site/
nimble docs      # book + API reference -> pages/ (what CI publishes)
```

Open `book/__site/index.html` in your browser to view the book on its own,
or `pages/index.html` after `nimble docs` for the book plus the generated
API reference.

## Running Tests

```bash
# Run all tests (debug, contracts active)
nimble test

# Run a single test file directly
nim c -r --path:src tests/unit/test_kernels.nim

# Debug + release + C ABI together
nimble testAll

# Coverage report (needs lcov; linux/macOS)
nimble coverage
```

## Troubleshooting

### "Cannot find module 'UniGraph'"

Make sure UniGraph is installed:
```bash
nimble install UniGraph
```

Or add the src directory to your path (the directory *containing*
`UniGraph.nim`, not the `UniGraph/` subfolder itself):
```bash
nim c -p:src myprogram.nim
```

### Version Mismatch

If you get version errors, update UniGraph:
```bash
nimble update UniGraph
```

### Build Errors

Clean and rebuild (there is no `nimble clean` task; remove the build
directories directly):
```bash
rm -rf build/ nimcache/
nimble install -y
```

## Next Steps

Once installed, head to [Core Concepts](core_concepts.html) to learn the fundamentals, then to [Quickstart](quickstart.html) to create your first graph!
"""
nbSave
