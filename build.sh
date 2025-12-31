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

if [ $rebuild -eq 1 ]; then
    pushd external/PieceChain
    echo "[INFO] Initialising cmake"
    cmake .
    echo "[INFO] Building PieceChain static library"
    make
    popd

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
    make
    echo "[INFO] Removing dynamic libraries"
    case "$OSTYPE" in
        darwin*)
            rm *.dylib || true
            ;;
        linux*|mysys*|cygwin*)
            rm *.so || true
            ;;
        *)
            echo "[ERROR] Unsupported OS: $OSTYPE"
            exit 1
            ;;
    esac
    popd

    popd
fi

echo "[INFO] Building Flow executable"
c3c build "$target"
