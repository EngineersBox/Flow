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
    echo "Usage: ./run.sh [<options>] [-- [<build options>]]"
    echo "Options:"
    echo "    -h | --help            Print this help message"
    echo "    -t | --target=<target> Target architecture [Default: macos_aarch64] (See project.json)"
    echo "Build Options:"
    echo ""
    ./build.sh --help
}

# Note that options with a ':' require an argument
LONGOPTS=help,target:
OPTIONS=ht:
#
# 1. Temporarily store output to be able to check for errors
# 2. Activate quoting/enhanced mode (e.g. by writing out “--options”)
# 3. Pass arguments only via   -- "$@"   to separate them correctly
# 4. If getopt fails, it complains itself to stdout
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@") || exit 2
# Read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

target="macos_aarch64"
# Handle options in order and nicely split until we see --
while true; do
    case "$1" in
        -h|--help)
            printHelp
            exit 1
            ;;
        -t|--target)
            target="$2"
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

echo "[INFO] Building executable"
./build.sh --target="$target" "$@"

echo "[INFO] Running executable"
exec "build/$target/flow"
