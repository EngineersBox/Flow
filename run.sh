#/usr/bin/env bash

TRUNC_LOG="${TRUNC_LOG:-false}"

if [ $TRUNC_LOG ]; then
    rm stderr.log
fi

zig build && zig-out/bin/Flow test_file.zig 2> stderr.log || true && reset
