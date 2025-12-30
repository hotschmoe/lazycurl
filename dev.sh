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

cmd="${1:-run}"
if [ $# -gt 0 ]; then
    shift
fi
case "$cmd" in
    run)
        if [[ "${1:-}" == "--" ]]; then
            shift
        fi
        zig build run -- "$@"
        ;;
    test)
        zig build test
        ;;
    fmt)
        zig build fmt
        ;;
    fetch)
        zig build --fetch
        ;;
    *)
        usage
        exit 1
        ;;
esac
