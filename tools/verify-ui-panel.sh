#!/bin/bash
# Prueft das UI-Utils-Panel headless (SDL_VIDEODRIVER=offscreen, DISPLAY
# geleert -> es geht KEIN Fenster auf).
#
# Erwartet:
#   * das Panel laesst sich einschalten (uiutils_enabled)
#   * die Panel-Zeichnung laeuft ohne Absturz und ohne Fehler
#   * die Drop-Funktionen sind vorhanden (core.drop_inventory_list)
#   * das Ext-Panel laesst sich ueber ext_menu.open oeffnen
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ -x "$REPO/bin/luanti" ] || { echo "Nicht gebaut: $REPO/bin/luanti"; exit 2; }

TMP="$(mktemp -d /tmp/uiutils-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
U="$TMP/user"
mkdir -p "$U/clientmods/probe"

# Die DEPLOYTEN CSMs pruefen (das ist, was der Client wirklich laedt).
DEPLOYED="${HOME}/.minetest/clientmods"
if [ ! -d "$DEPLOYED/ext_menu" ]; then
	echo "VERIFY=FAIL -- keine deployten CSMs ($DEPLOYED). Bitte deployen."
	exit 2
fi
cp -r "$DEPLOYED/ext_menu" "$U/clientmods/"
cat > "$U/clientmods/mods.conf" <<'EOF'
load_mod_ext_menu = true
load_mod_probe = true
EOF
cat > "$U/clientmods/probe/mod.conf" <<'EOF'
name = probe
EOF
cat > "$U/clientmods/probe/init.lua" <<'EOF'
-- Prueft die Ext-Bruecke und die Drop-API
core.after(5, function()
	core.log("action", "[probe] drop_inventory_list="
		.. tostring(core.drop_inventory_list ~= nil))
	core.log("action", "[probe] register_cheat="
		.. tostring(core.register_cheat ~= nil))
	-- das Ext-Panel ueber die Bruecke oeffnen
	core.settings:set_bool("ext_menu.open", true)
	core.after(1, function()
		core.log("action", "[probe] ext_menu.open gesetzt")
		core.settings:set_bool("ext_menu.open", false)
	end)
end)
EOF

cp -r "$HOME/.minetest/worlds/world2" "$TMP/world"
for d in games mods textures; do
	[ -e "$HOME/.minetest/$d" ] && ln -s "$HOME/.minetest/$d" "$U/$d"
done
cat > "$U/minetest.conf" <<'EOF'
name = uiutils-test
uiutils_enabled = true
EOF

export LUANTI_USER_PATH="$U" SDL_VIDEODRIVER=offscreen LIBGL_ALWAYS_SOFTWARE=1
unset DISPLAY
timeout 90 "$REPO/bin/luanti" --world "$TMP/world" --go > "$TMP/client.log" 2>&1
LOG="$U/debug.txt"

FAILED=0
grep -a "\[probe\]" "$LOG" | sed 's/^.*\[probe\]/[probe]/' | head -4
if grep -aq "drop_inventory_list=true" "$LOG"; then
	echo "  Drop-API: vorhanden"
else
	echo "  Drop-API: FEHLT"
	FAILED=1
fi
if grep -aq "ExtPanel. open page=main" "$LOG"; then
	echo "  Ext-Panel: oeffnet ueber ext_menu.open"
else
	echo "  Ext-Panel: oeffnet NICHT"
	FAILED=1
fi
if grep -aqE "ERROR|MODERROR" "$LOG"; then
	echo "  Fehler im Log:"
	grep -aE "ERROR|MODERROR" "$LOG" | head -5
	FAILED=1
else
	echo "  Keine Fehler im Log"
fi
exit $FAILED
