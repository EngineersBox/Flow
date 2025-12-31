#!/usr/bin/env bash

set -ex

OPERATION=${1:-"build"}

case "$OPERATION" in
    clean_build)
        pushd external/PieceChain
        echo "[INFO] Initialising cmake"
        cmake .
        echo "[INFO] Building PieceChain static library"
        make
        popd
        ;;
    build) ;;
    *)
        echo "Error: unknown operation $OPERATION"
        exit 1
        ;;
esac

echo "[INFO] Building Flow executable"
c3c build flow
