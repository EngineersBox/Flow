#/usr/bin/env bash

set -o errexit -o pipefail -o noclobber -o nounset

TRUNC_LOG="${TRUNC_LOG:-true}"

if [ $TRUNC_LOG ]; then
    rm stderr.log || true
fi

zig build $@
zig-out/bin/Flow test_file.zig 2> stderr.log || true
reset
