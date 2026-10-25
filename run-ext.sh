#!/bin/bash
# Startet die Ext-Fork-Binary mit dem normalen Luanti-Home (~/.minetest):
# gleiche Config, Games, Welten und clientmods wie System-Luanti.
# Optional isolierter Userpath: MINETEST_USER_PATH=~/.luanti-ext ./run-ext.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
BIN="$REPO/bin/luanti"
[ -x "$BIN" ] || { echo "Nicht gebaut: $BIN fehlt (build/ ausführen)"; exit 1; }
[ -n "${MINETEST_USER_PATH:-}" ] && export MINETEST_USER_PATH || true
exec "$BIN" "$@"
