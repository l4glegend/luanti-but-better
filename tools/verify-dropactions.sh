#!/bin/bash
# Funktionstest der Drop-Buttons: prueft, dass die Aktionen wirklich
# bewegen (Bump = Spielerinventar -> Truhe, Steal = Truhe -> Inventar,
# Drop all = Inventar auf den Boden).
#
# Das Server-Mod (dupetest) ist der Zeuge: es legt eine Truhe (nodemeta)
# mit Inhalt an, gibt dem Spieler Items und loggt den Zustand.
# Der Client klickt die Buttons per EXT_PANEL_SELFTEST an.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ -x "$REPO/bin/luanti" ] || { echo "Nicht gebaut: $REPO/bin/luanti"; exit 2; }

TMP="$(mktemp -d /tmp/dropact-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
U="$TMP/user"
mkdir -p "$U/mods/dupetest"

cat > "$U/mods/dupetest/mod.conf" <<'EOF'
name = dupetest
EOF
cat > "$U/mods/dupetest/init.lua" <<'EOF'
-- Zeuge: Truhe mit Inhalt anlegen, Spieler Items geben, Zustand loggen
local CHEST_POS = {x = 43, y = 33, z = -86}
local ITEM = "mcl_core:stone"
local CHEST_INV = "dupetest_chest"
local last_sig = ""

core.register_on_joinplayer(function(player)
	core.after(3, function()
		-- Echte Truhe (Node-Meta) mit 64 Stein, direkt neben dem Spieler
		-- (sonst verwirft der Server die Inventar-Aktionen wegen der
		-- Interaktionsdistanz)
		local ppos = player:get_pos()
		CHEST_POS = {x = math.floor(ppos.x) + 1, y = math.floor(ppos.y),
				z = math.floor(ppos.z)}
		core.log("action", "[dupetest] Spieler bei " .. ppos.x .. ","
			.. ppos.y .. "," .. ppos.z .. ", Truhe bei " .. CHEST_POS.x
			.. "," .. CHEST_POS.y .. "," .. CHEST_POS.z)
		minetest.set_node(CHEST_POS, {name = "mcl_chests:chest_small"})
		local nodeinv = minetest.get_inventory({type = "node", pos = CHEST_POS})
		if not nodeinv then
			core.log("action", "[dupetest] FEHLER: Truhe hat kein Inventar")
			return
		end
		local field = "main"
		for _, f in ipairs({"chest", "main"}) do
			if nodeinv:get_list(f) then field = f break end
		end
		nodeinv:set_stack(field, 1, ItemStack(ITEM .. " 64"))
		-- das Formspec explizit senden (sonst kommt beim Client nichts an)
		core.show_formspec(player:get_player_name(), "dupetest_chest",
			"size[8,9]"
			.. "list[current_player;main;0,0.5;9,4;]"
			.. "list[nodemeta:" .. CHEST_POS.x .. "," .. CHEST_POS.y .. ","
			.. CHEST_POS.z .. ";" .. field .. ";0,4.5;9,4;]")
		-- 32 Stein in das Spielerinventar
		player:get_inventory():set_stack("main", 1, ItemStack(ITEM .. " 32"))
		core.log("action", "[dupetest] Truhe mit 64x " .. ITEM
			.. " und 32x " .. ITEM .. " im Spielerinventar angelegt")
	end)
end)

core.register_globalstep(function()
	local players = core.get_connected_players()
	for _, p in ipairs(players) do
		-- Zustand loggen (nur bei Aenderung)
		local pinv = p:get_inventory()
		local pcount = 0
		for i = 1, pinv:get_size("main") do
			local st = pinv:get_stack("main", i)
			if not st:is_empty() and st:get_name() == ITEM then
				pcount = pcount + st:get_count()
			end
		end
		local ccount = 0
		local cinv = core.get_inventory({type = "node", pos = CHEST_POS})
		if cinv then
			for _, f in ipairs({"chest", "main"}) do
				if cinv:get_list(f) then
					for i = 1, cinv:get_size(f) do
						local st = cinv:get_stack(f, i)
						if not st:is_empty() and st:get_name() == ITEM then
							ccount = ccount + st:get_count()
						end
					end
				end
			end
		end
		-- Items auf dem Boden zaehlen (in der Naehe des Spielers)
		local ppos = p:get_pos()
		local bcount = 0
		local pmin = {x = ppos.x - 6, y = ppos.y - 6, z = ppos.z - 6}
		local pmax = {x = ppos.x + 6, y = ppos.y + 6, z = ppos.z + 6}
		for _, node in ipairs(minetest.find_nodes_in_area(pmin, pmax, {ITEM})) do
			local meta = minetest.get_meta(node)
			bcount = bcount + (tonumber(meta:get_string("count")) or 1)
		end
		local sig = "player=" .. pcount .. " chest=" .. ccount .. " ground=" .. bcount
		if sig ~= last_sig then
			last_sig = sig
			core.log("action", "[dupetest] " .. sig)
		end
	end
end)
EOF

cp -r "$HOME/.minetest/worlds/world2" "$TMP/world"
printf 'load_mod_dupetest = true\n' >> "$TMP/world/world.mt"
for d in games mods clientmods textures; do
	[ -e "$HOME/.minetest/$d" ] && ln -s "$HOME/.minetest/$d" "$U/$d"
done
printf 'name = dropact-test\n' > "$U/minetest.conf"

export LUANTI_USER_PATH="$U" SDL_VIDEODRIVER=offscreen LIBGL_ALWAYS_SOFTWARE=1
export EXT_PANEL_SELFTEST=1
unset DISPLAY
timeout 90 "$REPO/bin/luanti" --name DarkBuilder --world "$TMP/world" --go > "$TMP/client.log" 2>&1
LOG="$U/debug.txt"

echo "=== Zustandsmessung des Servers ==="
grep -a "dupetest" "$LOG" | sed 's/^.*\[dupetest\]/[dupetest]/' | tail -8
echo
echo "=== Klick-Protokoll des Clients ==="
grep -a "drop bar" "$LOG" | sed 's/^.*\[ExtPanel\]/[ExtPanel]/' | grep -v "Listen gefunden" | tail -12
echo
echo "=== Selbsttest: Klick + Fensterstatus ==="
grep -a "SELFTEST klick" "$LOG" | sed 's/^.*\[ExtPanel\]/[ExtPanel]/' | head -3
echo
echo "=== Formspec-Empfaenge (Client) ==="
grep -a -i "formspec" "$LOG" | tail -5
echo
echo "=== Serverfehler / Inventar-Meldungen ==="
grep -a -i "inventor\|not allowed\|denied\|error\|failed" "$LOG" | grep -v "dupetest" | tail -12

echo
echo "=== Auswertung: Bump/Steal muessen ALLES bewegen (ein Klick) ==="
# Der Server-Zaehler ist der Zeuge: player/chest/ground in mcl_core:stone.
# Erwartet wird der Volle-Effekt: Bump leert den Spieler komplett in die
# Truhe, Steal holt alles zurueck -- NICHT ein Item pro Klick.
SIGS="$(grep -a "\[dupetest\] player=" "$LOG" | sed 's/^.*\[dupetest\] //')"
if [ -z "$SIGS" ]; then
	echo "  FEHLER: keine Zustands-Signaturen im Server-Log"
	echo "VERIFY=FAIL"
	exit 1
fi
INIT="$(printf '%s\n' "$SIGS" | awk -F'chest=' '$2+0 > 0 {print; exit}')"
if [ -z "$INIT" ]; then
	echo "  FEHLER: dupetest-Setup fehlt (keine Signatur mit gefuellter Truhe)"
	echo "VERIFY=FAIL"
	exit 1
fi
P0="$(printf '%s' "$INIT" | sed -n 's/^player=\([0-9]*\).*/\1/p')"
C0="$(printf '%s' "$INIT" | sed -n 's/.*chest=\([0-9]*\).*/\1/p')"
G0="$(printf '%s' "$INIT" | sed -n 's/.*ground=\([0-9]*\).*/\1/p')"
P0="${P0:-0}"; C0="${C0:-0}"; G0="${G0:-0}"
ALLE=$((P0 + C0))
echo "  Initial: $INIT  -> Bump erwartet player=0 chest=$ALLE, Steal erwartet player=$ALLE chest=0"
printf '%s\n' "$SIGS" | sed 's/^/    /'
FAIL=0
if printf '%s\n' "$SIGS" | grep -qx "player=0 chest=$ALLE ground=$G0"; then
	echo "  OK: Bump bewegt ALLES (ein Klick leert das Spielerinventar)"
else
	echo "  FEHLER: Bump bewegt nicht alles -- erwartet 'player=0 chest=$ALLE ground=$G0'"
	FAIL=1
fi
if printf '%s\n' "$SIGS" | grep -qx "player=$ALLE chest=0 ground=$G0"; then
	echo "  OK: Steal bewegt ALLES (ein Klick leert die Truhe)"
else
	echo "  FEHLER: Steal bewegt nicht alles -- erwartet 'player=$ALLE chest=0 ground=$G0'"
	FAIL=1
fi
if [ "$FAIL" = "0" ]; then
	echo "VERIFY=PASS (Bump/Steal bewegen die vollen Stacks)"
	exit 0
fi
echo "VERIFY=FAIL"
exit 1
