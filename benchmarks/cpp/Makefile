# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# Boost Graph Library is header-only for the algorithms used here (BFS/DFS/
# Dijkstra/Prim/Kruskal/strong_components): no linking, just -I the Boost
# include path.
ifeq ($(origin CXX),default)
  ifeq ($(OS),Windows_NT)
    CXX := g++
  else
    CXX := c++
  endif
endif

# Resolve the Boost include dir: pkg-config first (most distros don't ship
# one for Boost, but honor it if present), else the first common location
# that actually has a boost/ subdirectory. Override with
# `make BOOST_INC=/path/to/include` if Boost lives elsewhere.
ifndef BOOST_INC
  PKG_BOOST_INC := $(shell pkg-config --cflags-only-I boost 2>/dev/null | sed 's/^-I//')
  ifneq ($(PKG_BOOST_INC),)
    BOOST_INC := $(PKG_BOOST_INC)
  else
    BOOST_CANDIDATE := $(firstword $(wildcard /opt/homebrew/include/boost /usr/local/include/boost /usr/include/boost))
    BOOST_INC := $(patsubst %/boost,%,$(BOOST_CANDIDATE))
  endif
endif

CXXFLAGS := -O2 -Wall -Wextra -std=c++17
ifneq ($(strip $(BOOST_INC)),)
  CXXFLAGS += -I$(BOOST_INC)
endif

ifeq ($(OS),Windows_NT)
  BIN  := bench_boost.exe
  RM_F := del /q
else
  BIN  := bench_boost
  RM_F := rm -f
endif

.PHONY: all clean
all: $(BIN)
$(BIN): bench_boost.cpp
	$(CXX) $(CXXFLAGS) -o $(BIN) bench_boost.cpp
clean:
	$(RM_F) $(BIN)
