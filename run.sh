#/usr/bin/env bash

zig build && zig-out/bin/Flow test.txt 2> stderr.log || true && reset
