#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./dev.sh [run|test|fmt|fetch] [-- zig args]

Commands:
  run    Compile and run `zig build run`
  test   Execute all Zig tests
  fmt    Format Zig sources via `zig fmt`
  fetch  Download Zig dependencies (libvaxis)

Any arguments after `--` are forwarded to `zig build run`.
EOF
}

zig_bin="./zig-aarch64-macos-0.15.1/zig"
if [[ ! -x "$zig_bin" ]]; then
    zig_bin="zig"
fi

cmd="${1:-run}"
if [ $# -gt 0 ]; then
    shift
fi
case "$cmd" in
    run)
        if [[ "${1:-}" == "--" ]]; then
            shift
        fi
        "$zig_bin" build run -- "$@"
        ;;
    test)
        "$zig_bin" build test
        ;;
    fmt)
        "$zig_bin" build fmt
        ;;
    fetch)
        "$zig_bin" build --fetch
        ;;
    *)
        usage
        exit 1
        ;;
esac
