#!/bin/bash
# Misst die Drop-Buttons: startet den Client headless, oeffnet ein
# Inventar-Fenster (wie eine Truhe) und prueft, ob die Buttons erzeugt und
# gezeichnet werden.
#
# Log-Auswertung ueber die Marker "[ExtPanel] drop bar: ...".
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ -x "$REPO/bin/luanti" ] || { echo "Nicht gebaut: $REPO/bin/luanti"; exit 2; }

TMP="$(mktemp -d /tmp/dropbar-test.XXXXXX)"
KEEP=0
trap '[ "$KEEP" = "1" ] || rm -rf "$TMP"' EXIT
U="$TMP/user"
mkdir -p "$U/clientmods/probe"

DEPLOYED="${HOME}/.minetest/clientmods"
cp -r "$DEPLOYED/ext_menu" "$U/clientmods/" 2>/dev/null
cat > "$U/clientmods/mods.conf" <<'EOF'
load_mod_ext_menu = true
load_mod_probe = true
EOF
cat > "$U/clientmods/probe/mod.conf" <<'EOF'
name = probe
EOF
cat > "$U/clientmods/probe/init.lua" <<'EOF'
-- Oeffnet ein Fenster mit dem Spielerinventar (wie ein Truhen-Formspec)
core.after(2, function()
	core.show_formspec("probe:inv",
		"formspec_version[4]size[10,7]"
		.. "list[current_player;main;0,0.5;9,5;]")
	core.log("action", "[probe] Inventar-Fenster geoeffnet")
end)
EOF

cp -r "$HOME/.minetest/worlds/world2" "$TMP/world"
for d in games mods textures; do
	[ -e "$HOME/.minetest/$d" ] && ln -s "$HOME/.minetest/$d" "$U/$d"
done
printf 'name = dropbar-test\n' > "$U/minetest.conf"

export LUANTI_USER_PATH="$U" SDL_VIDEODRIVER=offscreen LIBGL_ALWAYS_SOFTWARE=1
export EXT_PANEL_SELFTEST=1
unset DISPLAY
timeout 90 "$REPO/bin/luanti" --name DarkBuilder --world "$TMP/world" --go > "$TMP/client.log" 2>&1
LOG="$U/debug.txt"

KEEP=1
echo "=== Was meldet die Drop-Leiste? ==="
grep -a "buttons erzeugt" "$LOG" | sed 's/^.*\[ExtPanel\]/[ExtPanel]/' | tail -2
echo
grep -a "\[probe\]" "$LOG" | sed 's/^.*\[probe\]/[probe]/' | tail -2
echo
BTN_W=$(grep -ao "button=[0-9]*x" "$LOG" | tail -1 | tr -d 'button=' | tr -d 'x')
if grep -aq "Aktion .* auf" "$LOG"; then
	echo "VERIFY=OK -- der Klick auf den Button kam an"
	grep -a "Klick auf" "$LOG" | sed 's/^.*\[ExtPanel\]/[ExtPanel]/' | tail -1
	exit 0
fi
echo "VERIFY=FAIL -- der Button hat den Klick nicht bekommen"
if grep -aq "buttons erzeugt" "$LOG" && grep -aq "sichtbar" "$LOG" \
		&& [ -n "$BTN_W" ] && [ "$BTN_W" -ge 50 ]; then
	echo "VERIFY=OK -- Buttons erzeugt, sichtbar und ${BTN_W}px breit"
	exit 0
fi
if [ -n "$BTN_W" ] && [ "$BTN_W" -lt 50 ]; then
	echo "VERIFY=FAIL -- die Buttons sind nur ${BTN_W}px breit (unsichtbar)"
	exit 1
fi
if grep -aq "VERSTECKT" "$LOG"; then
	echo "VERIFY=FAIL -- die Buttons liegen ausserhalb des Parent-Elements"
	exit 1
fi
echo "VERIFY=FAIL -- keine Buttons erzeugt"
grep -a "drop bar" "$LOG" | tail -3
exit 1
