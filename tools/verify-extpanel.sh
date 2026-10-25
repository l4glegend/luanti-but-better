#!/bin/bash
# Automatisierter Smoke-Test des ExtPanels.
#
# ACHTUNG: Der Test startet Luanti-Instanzen. Damit dabei KEIN Fenster auf
# dem Desktop des Nutzers aufgeht, laeuft er vollstaendig offscreen
# (SDL_VIDEODRIVER=offscreen, DISPLAY geleert) -- es wird kein Fenster
# erzeugt und kein X-Server gestartet. Ohne das Argument --run passiert
# gar nichts (nur Dry-Run).
#
# Aufruf:
#   bash tools/verify-extpanel.sh            # Dry-Run: zeigt nur, was laufen wuerde
#   bash tools/verify-extpanel.sh --run      # headless ausfuehren (1 Kombination)
#   bash tools/verify-extpanel.sh --run full # headless ausfuehren (volle Matrix)
#
# Exit-Codes: 0 = alles ok, 1 = Probleme, 2 = Setup/Blocker
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

MODE="dry"
for a in "$@"; do
	case "$a" in
		--run) MODE="run" ;;
		full) MODE="full" ;;
	esac
done

WORLD_SRC="${WORLD_SRC:-$HOME/.minetest/worlds/world2}"

if [ "$MODE" = "dry" ]; then
	echo "Dry-Run. Ausgefuehrt wuerde:"
	echo "  Welt:      $WORLD_SRC (Kopie)"
	echo "  Display:   offscreen (kein Fenster, kein X-Server)"
	echo "  Matrix:    1280x720/1920x1080/1024x768 x gui_scaling 1.0/1.5"
	echo "  Aufruf:    bash tools/verify-extpanel.sh --run"
	exit 0
fi

[ -x "$REPO/bin/luanti" ] || { echo "Nicht gebaut: $REPO/bin/luanti"; exit 2; }
[ -d "$WORLD_SRC" ] || { echo "Testwelt fehlt: $WORLD_SRC"; exit 2; }

# Der Test laeuft komplett offscreen (SDL_VIDEODRIVER=offscreen): es geht
# KEIN Fenster auf, weder auf dem Desktop noch unter Xvfb. DISPLAY wird
# zusaetzlich geleert, damit der Client keinen X-Server braucht.
export SDL_VIDEODRIVER=offscreen
unset DISPLAY

if [ "$MODE" = "full" ]; then
	RESOLUTIONS="${RESOLUTIONS:-1280x720 1920x1080 1024x768}"
	SCALINGS="${SCALINGS:-1.0 1.5}"
else
	RESOLUTIONS="${RESOLUTIONS:-1920x1080}"
	SCALINGS="${SCALINGS:-1.0}"
fi

FAILED=0
for RES in $RESOLUTIONS; do
	for SCALE in $SCALINGS; do
		TMP="$(mktemp -d /tmp/extpanel-selftest.XXXXXX)"
		cp -r "$WORLD_SRC" "$TMP/world"
		LOG="$TMP/client.log"

		export LIBGL_ALWAYS_SOFTWARE=1
		export EXT_PANEL_SELFTEST=1
		export LUANTI_USER_PATH="$TMP/userpath"
		mkdir -p "$LUANTI_USER_PATH"
		for d in games mods clientmods textures; do
			[ -e "$HOME/.minetest/$d" ] && ln -s "$HOME/.minetest/$d" "$LUANTI_USER_PATH/$d"
		done
		cat > "$LUANTI_USER_PATH/minetest.conf" <<EOF
gui_scaling = $SCALE
screen_w = ${RES%x*}
screen_h = ${RES#*x}
EOF

		# offscreen: der Client zeichnet in einen Offscreen-Buffer,
		# es wird kein Fenster erzeugt.
		timeout 180 "$REPO/bin/luanti" --world "$TMP/world" --go >"$LOG" 2>&1
		RC=$?

		if ! grep -q "SELFTEST problems=" "$LOG"; then
			echo "[$RES scale=$SCALE] SELFTEST: kein Ergebnis (Client rc=$RC)"
			tail -12 "$LOG"
			FAILED=1
			rm -rf "$TMP"
			continue
		fi

		RESULT="$(grep -a 'SELFTEST problems=' "$LOG" | tail -1)"
		CHECK="$(grep -a 'SELFCHECK' "$LOG" | tail -1)"
		PROBLEMS="$(printf '%s' "$RESULT" | sed -n 's/.*problems=\([0-9]*\).*/\1/p')"
		if [ "${PROBLEMS:-1}" = "0" ]; then
			echo "[$RES scale=$SCALE] PASS  ${CHECK#*ExtPanel] }"
		else
			echo "[$RES scale=$SCALE] FAIL ($PROBLEMS Probleme)"
			grep -aE "SELFCHECK|SELFTEST" "$LOG" | head -12
			FAILED=1
		fi
		# Log behalten (Diagnose)
		cp "$LOG" /tmp/extpanel-last.log 2>/dev/null || true
		rm -rf "$TMP"
	done
done

if [ "$FAILED" = "0" ]; then
	echo "VERIFY=PASS (alle Widgets klickbar)"
	exit 0
fi
echo "VERIFY=FAIL"
exit 1
