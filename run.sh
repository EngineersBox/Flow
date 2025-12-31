#!/usr/bin/env bash

OPERATION=${OPERATION:-"build"}

echo "[INFO] Building executable"
./build.sh "$OPERATION"

echo "[INFO] Running executable"
build/flow
