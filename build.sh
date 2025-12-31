#!/usr/bin/env bash

set -o errexit -o pipefail -o noclobber -o nounset

PWD="$(pwd)"
PROJECT_DIR_NAME="flow"

# Ensure we work from the project base dir to avoid
# weird mounting behaviour when running container
case "$(basename "$PWD")" in
  "$PROJECT_DIR_NAME") ;;
  *)
    echo "[ERROR] This script must be run from the $PROJECT_DIR_NAME directory, not $PWD"
    exit 1
    ;;
esac

# Ignore errexit with `&& true`
getopt --test > /dev/null && true
if [[ $? -ne 4 ]]; then
    echo '[ERROR] getopt invocation failed.'
    exit 1
fi

function printHelp() {
    echo "Usage: ./build.sh [<options>]"
    echo "Options:"
    echo "    -h | --help            Print this help message"
    echo "    -r | --rebuild         Build dependencies and executable (default: false)"
    echo "    -t | --target=<target> Target architecture [Default: macos_aarch64] (See project.json)"

}

# Note that options with a ':' require an argument
LONGOPTS=help,rebuild,target:
OPTIONS=hrt:

# 1. Temporarily store output to be able to check for errors
# 2. Activate quoting/enhanced mode (e.g. by writing out “--options”)
# 3. Pass arguments only via   -- "$@"   to separate them correctly
# 4. If getopt fails, it complains itself to stdout
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@") || exit 2
# Read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

rebuild=0
target="macos_aarch64"
# Handle options in order and nicely split until we see --
while true; do
    case "$1" in
        -h|--help)
            printHelp
            exit 1
            ;;
        -r|--rebuild)
            rebuild=1
            shift
            ;;
        -t|--target)
            target=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "[ERROR] Unknown option encountered: $1"
            exit 3
            ;;
    esac
done

static_lib_extension="a"

case "$OSTYPE" in
    darwin*)
        static_lib_extension="a"
        ;;
    linux*|mysys*|cygwin*|bsd*)
        static_lib_extension="a"
        ;;
    *)
        echo "[ERROR] Unsupported OS: $OSTYPE"
        exit 1
        ;;
esac

libs_dir="$(pwd)/lib"
include_dir="$(pwd)/include"

function build_piece_chain() {
    pushd external/PieceChain
    echo "[INFO] Initialising cmake"
    cmake .
    echo "[INFO] Building PieceChain static library"
    make
    echo "[INFO] Install libraries and headers into project"
    local __libs_dir="$libs_dir/piece_chain"
    local __include_dir="$include_dir/PieceChain"
    mkdir -p "$__libs_dir"
    mkdir -p "$__include_dir"
    cp "libPieceChain.$static_lib_extension" "$__libs_dir/."
    cp "include/PieceChain/PieceChain.h" "$__include_dir/."
    popd
}

function build_notcurses() {
    pushd external/notcurses
    echo "[INFO] Creating build output directory"
    rm -rf build
    mkdir -p build
    pushd build
    echo "[INFO] Initialising cmake"
    cmake -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DBUILD_EXECUTABLES=OFF \
        -DBUILD_FFI_LIBRARY=ON \
        -DUSE_DOCTEST=OFF \
        -DUSE_PANDOC=OFF \
        -DUSE_CXX=OFF \
        -DUSE_STATIC=ON \
        -DUSE_POC=OFF \
        -DUSE_DOXYGEN=OFF \
        -DUSE_MULTIMEDIA=ffmpeg \
        ..
    echo "[INFO] Building notcurses libraries"
    make notcurses-core-static notcurses-static
    echo "[INFO] Installing libraries and headers into project"
    local __libs_dir="$libs_dir/notcurses"
    local __include_dir="$include_dir/notcurses"
    mkdir -p "$__libs_dir"
    mkdir -p "$__include_dir"
    cp *.a "$__libs_dir/."
    cp -r ../include/notcurses/ "$__include_dir/."
    cp include/version.h "$__include_dir/."
    popd
    popd
}

function build_tree_sitter {
    pushd external/tree-sitter
    echo "[INFO] Building static library"
    make "libtree-sitter.$static_lib_extension"
    echo "[INFO] Install libraries and headers into project"
    local __libs_dir="$libs_dir/tree_sitter"
    mkdir -p "$__libs_dir"
    cp "libtree-sitter.$static_lib_extension" "$__libs_dir/."
    cp -r lib/include/tree_sitter "$include_dir/."
    popd
}

if [ $rebuild -eq 1 ]; then
    build_piece_chain
    build_notcurses
    build_tree_sitter
fi

echo "[INFO] Building Flow executable"
c3c build "$target"
