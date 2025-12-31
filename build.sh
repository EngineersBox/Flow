#!/usr/bin/env bash

LD_LIBRARY_PATH="$(pwd)/external/PieceTable/:$LD_LIBRARY_PATH"
c3c build flow
