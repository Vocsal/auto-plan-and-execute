#!/usr/bin/env bash
# 根目录便捷入口 — 转发到 scripts/auto-flow.sh
exec "$(cd "$(dirname "$0")" && pwd)/scripts/auto-flow.sh" "$@"
