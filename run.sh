#/usr/bin/env bash

zig build && zig-out/bin/Flow test_file.zig 2> stderr.log || true && reset
