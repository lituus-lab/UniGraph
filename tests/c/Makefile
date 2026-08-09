# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# Portable paths use $(CURDIR); cleanup selects del /q on Windows.
ifeq ($(origin CC),default)
  ifeq ($(OS),Windows_NT)
    CC := gcc
  else
    CC := cc
  endif
endif

ROOT   := $(CURDIR)/../..
CFLAGS := -I$(ROOT)/include -O2 -Wall -Wextra -std=c11
LIB    := $(ROOT)/libUniGraph.a

ifeq ($(OS),Windows_NT)
  BIN  := test_unigraph.exe
  RUN  := $(BIN)
  RM_F := del /q
else
  BIN  := test_unigraph
  RUN  := ./$(BIN)
  RM_F := rm -f
endif

.PHONY: all run test clean
all: run
run: $(BIN)
	$(RUN)
test: run
$(BIN): test_unigraph.c $(ROOT)/include/UniGraph.h $(LIB)
	$(CC) $(CFLAGS) -o $(BIN) test_unigraph.c $(LIB)
# File target, not phony: `nimble ctest` already built the lib, don't redo it.
$(LIB):
	cd $(ROOT) && nimble clibStatic
clean:
	$(RM_F) $(BIN)
