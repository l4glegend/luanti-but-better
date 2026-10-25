#!/bin/bash
# Automatisierter End-to-End-Test des ChestDupe (inkl. Auto-Drop).
#
# Der Test laeuft vollstaendig headless (SDL_VIDEODRIVER=offscreen, DISPLAY
# geleert): es geht KEIN Fenster auf.
#
# Aufbau:
#   * Server-Mod (dupetest): legt eine mcl_chests:chest_small vor den Spieler,
#     gibt 64 Stein in Slot 1 (Wield-Slot) und beobachtet Brust + Boden.
#   * Client-CSM (chest_dupe): macht den eigentlichen Dupe.
#   * Lauf 1 (Auto-Drop aus): die Brust fuellt sich mit duplizierten Stacks
#     (der listring-Exploit des Servers hat gegriffen).
#   * Lauf 2 (Auto-Drop an): die duplizierten Stacks fallen sofort auf den
#     Boden (permanently) -- der Boden-Item-Zaehler muss wachsen.
#
# Aufruf: bash tools/verify-chestdupe.sh [weltpfad]
# Exit: 0 = alles ok, 1 = Fehler, 2 = Setup-Fehler
set -uo pipefail
DEBUG_LOG="${DEBUG_LOG:-0}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ -x "$REPO/bin/luanti" ] || { echo "Nicht gebaut: $REPO/bin/luanti"; exit 2; }

WORLD_SRC="${1:-$HOME/.minetest/worlds/world2}"
[ -d "$WORLD_SRC" ] || { echo "Testwelt fehlt: $WORLD_SRC"; exit 2; }

# run_test <autodrop 0|1> [preload 0|1] [timeout]
#   -> legt die Logdatei in $OUT_LOG und schreibt
#      "ERGEBNIS=<stacks>|<boden>|<brust_max>|<brust_ist>|<preload_size>"
#      in die Datei $OUT_RES
run_test() {
	local autodrop="$1"
	local preload="${2:-0}"
	local tmo="${3:-120}"
	local TMP U
	TMP="$(mktemp -d /tmp/chestdupe-test.XXXXXX)"
	U="$TMP/user"
	mkdir -p "$U/mods/dupetest" "$U/clientmods/chest_dupe"
	export DUPETEST_PRELOAD="$preload"

	cp -r "$WORLD_SRC" "$TMP/world"
	cp "$REPO/clientmods-ext/chest_dupe/init.lua" "$U/clientmods/chest_dupe/init.lua"
	cat > "$U/clientmods/chest_dupe/mod.conf" <<'EOF'
name = chest_dupe
EOF
	cat > "$U/clientmods/mods.conf" <<'EOF'
load_mod_chest_dupe = true
EOF

	cat > "$U/mods/dupetest/mod.conf" <<'EOF'
name = dupetest
EOF
	cat > "$U/mods/dupetest/init.lua" <<'EOF'
local ITEM = "mcl_core:stone"
local NODE = "mcl_chests:chest_small"
local PRELOAD = os.getenv("DUPETEST_PRELOAD") == "1"
local chest_pos = nil
local filled = false
local last_state = ""
local last_ground = ""
local last_ents = ""
local last_ist = ""
local max_ground = 0
local item_names = {}
local itemnode_names = {}
local scanned = false
local max_chest = 0

core.register_on_joinplayer(function(player)
	core.after(4, function()
		if not player:is_player() then return end
		local pos = player:get_pos()
		local dir = player:get_look_dir()
		-- 1 Block vor dem Spieler: der Server prueft bei Inventar-Aktionen
		-- die Interaktionsdistanz
		chest_pos = {
			x = math.floor(pos.x + dir.x * 1.2 + 0.5),
			y = math.floor(pos.y + dir.y * 1.2 + 0.5),
			z = math.floor(pos.z + dir.z * 1.2 + 0.5),
		}
		core.set_node(chest_pos, {name = NODE})
		player:get_inventory():set_stack("main", 1, ItemStack(ITEM .. " 64"))
		-- Lauf 3: die Truhe ist bereits VOLL -- genau der Zustand, in dem
		-- der Kapazitaets-Guard im Client die Schleife stoppt (und vor dem
		-- Fix ebenso den Auto-Drop, der die Truhe leeren wuerde).
		if PRELOAD then
			local ninv = minetest.get_inventory({type = "node", pos = chest_pos})
			if ninv then
				local size = ninv:get_size("main")
				for i = 1, size do
					ninv:set_stack("main", i, ItemStack(ITEM .. " 64"))
				end
				core.log("action", "[dupetest] preload: volle Truhe ("
					.. size .. " Stacks)")
			end
		end
		-- Das Formspec oeffnen: der Server erlaubt Inventar-Aktionen auf
		-- einen Node-Container nur, wenn der Spieler ihn geoeffnet hat
		-- (im echten Spiel ist die Truhe offen).
		core.after(1, function()
			core.show_formspec(player:get_player_name(), "dupetest_chest",
				"size[8,9]list[current_player;main;0,0.5;9,4;]"
				.. "list[nodemeta:" .. chest_pos.x .. "," .. chest_pos.y .. ","
				.. chest_pos.z .. ";main;0,4.5;9,4;]")
			core.log("action", "[dupetest] Truhen-Formspec geoeffnet")
		end)
		core.log("action", "[dupetest] Brust " .. NODE .. " bei "
			.. core.pos_to_string(chest_pos) .. ", 64x " .. ITEM .. " in Slot 1")
	end)
end)

core.register_globalstep(function()
	if not chest_pos then return end
	local inv = core.get_inventory({type = "node", name = NODE, pos = chest_pos})
	if not inv then return end
	local n = 0
	local wrong = 0
	for i = 1, inv:get_size("main") do
		local st = inv:get_stack("main", i)
		if st and not st:is_empty() then
			n = n + 1
			-- Es muss DERSELBE Stack sein, der in der Hand war: ein
			-- falscher Slot dupliziert das Item DAVOR oder DANACH.
			if st:get_name() ~= ITEM then wrong = wrong + 1 end
		end
	end
	if n > max_chest then
		max_chest = n
		core.log("action", "[dupetest] brust_max=" .. max_chest)
	end
	-- aktueller Fuellstand (nicht der Max): zeigt, ob Auto-Drop die
	-- vorbefuellte Truhe wirklich leert
	local ist_sig = "brust_ist=" .. n
	if ist_sig ~= last_ist then
		last_ist = ist_sig
		core.log("action", "[dupetest] " .. ist_sig)
	end
	if n > 0 and not filled then
		filled = true
		core.log("action", "[dupetest] ERGEBNIS: Brust enthaelt " .. n
			.. " Stacks, davon " .. wrong
			.. " falsche -- DUPE HAT GEKLAPPT"
			.. (wrong > 0 and " (FALSCHES ITEM!)" or " (richtiges Item)"))
	end
	-- Items auf dem Boden: Item-Nodes tragen die Meta "count" (ein
	-- Gesteins-Node hat keine) -- das sind die gedropten Items.
	local ground = 0
	for _, pl in ipairs(core.get_connected_players()) do
		local pp = pl:get_pos()
		local pmin = {x = pp.x - 8, y = pp.y - 8, z = pp.z - 8}
		local pmax = {x = pp.x + 8, y = pp.y + 8, z = pp.z + 8}
		-- Item-Nodes finden: alle Nodes mit der Meta "count" (ein Gesteins-
		-- Node hat keine). Einmalig ein Raster absuchen, um die Namen zu
		-- sehen.
		if not scanned then
			scanned = true
			for x = pmin.x, pmax.x do
				for y = pmin.y, pmax.y do
					for z = pmin.z, pmax.z do
						local pos = {x = x, y = y, z = z}
						local meta = minetest.get_meta(pos)
						local c = meta:get_string("count")
						local is = meta:get_string("itemstring")
						if c ~= "" or is ~= "" then
							local nm = core.get_node_name(pos) or "?"
							core.log("action", "[dupetest] ITEMNODE " .. nm
								.. " count=" .. c .. " itemstring=" .. is)
							itemnode_names[nm] = true
						end
					end
				end
			end
		end
		-- zaehlen: alle bekannten Item-Node-Namen
		for nm in pairs(itemnode_names) do
			for _, node in ipairs(minetest.find_nodes_in_area(pmin, pmax, {nm})) do
				local meta = minetest.get_meta(node)
				local c = meta:get_string("count")
				if c ~= "" then
					ground = ground + (tonumber(c) or 1)
				end
			end
		end
		if ground > max_ground then max_ground = ground end
		local gsig = "boden=" .. ground
		if gsig ~= last_ground then
			last_ground = gsig
			core.log("action", "[dupetest] " .. gsig)
		end
		-- Item-ENTITIES: der Server droppt ueber item_OnDrop (kein
		-- on_drop-Override in Mineclonia) -- das Ergebnis sind
		-- __builtin:item-Entities, KEINE Item-Nodes. Ohne diesen Zaehler
		-- waere boden immer 0, obwohl der Drop lief.
		local ents = 0
		for _, obj in ipairs(minetest.get_objects_in_area(pmin, pmax)) do
			local le = obj:get_luaentity()
			if le and (le.itemstring ~= nil or le.name == "__builtin:item"
				or le.name == "mcl_items:item") then
				ents = ents + 1
			end
		end
		if ents > max_ground then max_ground = ents end
		local esig = "ents=" .. ents
		if esig ~= last_ents then
			last_ents = esig
			core.log("action", "[dupetest] " .. esig)
		end
	end
	-- Der eigentliche Gewinn: der Spieler muss MEHR Items haben und das
	-- Item in der Hand muss unveraendert sein.
	for _, pl in ipairs(core.get_connected_players()) do
		local inv = pl:get_inventory()
		local wield = inv:get_stack("main", 1)
		local total = 0
		for i = 1, inv:get_size("main") do
			local st = inv:get_stack("main", i)
			if st and not st:is_empty() then total = total + st:get_count() end
		end
		local sig = "wield=" .. wield:get_name() .. "x" .. wield:get_count()
			.. " total=" .. total
		if sig ~= last_state then
			last_state = sig
			core.log("action", "[dupetest] Spieler: " .. sig)
		end
		-- Die Hand muss unveraendert bleiben: das Item in der Hand ist
		-- immer noch das Item, das dupliziert wurde.
		if wield:get_name() == ITEM and wield:get_count() == 64 then
			core.log("action", "[dupetest] HAND OK: " .. wield:get_name()
				.. "x" .. wield:get_count() .. " (unveraendert)")
		end
	end
end)
EOF

	cat > "$U/minetest.conf" <<EOF
chest_dupe = true
chest_dupe.log = true
chest_dupe.hold_mode = false
chest_dupe.mode = Auto
chest_dupe.autotake = true
chest_dupe.autodrop = $([ "$autodrop" = "1" ] && echo true || echo false)
name = chestdupe-test
EOF
	printf 'load_mod_dupetest = true\n' >> "$TMP/world/world.mt"
	for d in games mods textures; do
		[ -e "$HOME/.minetest/$d" ] && ln -s "$HOME/.minetest/$d" "$U/$d"
	done

	export LUANTI_USER_PATH="$U" SDL_VIDEODRIVER=offscreen LIBGL_ALWAYS_SOFTWARE=1
	unset DISPLAY
	timeout "$tmo" "$REPO/bin/luanti" --world "$TMP/world" --go > "$TMP/client.log" 2>&1
	LOG="$U/debug.txt"

	local boden=0 brust=0 ist=-1 size=0 entsmax=0
	# hoechster Bodenstand ueber den ganzen Lauf (Items koennen wieder
	# eingesammelt werden -- der Max belegt, dass ueberhaupt gedroppt wurde)
	boden=$(grep -ao "boden=[0-9]*" "$LOG" | cut -d= -f2 | sort -n | tail -1)
	[ -n "$boden" ] || boden=0
	# Drops landen als ENTITIES auf dem Boden (item_OnDrop) -- der Max ueber
	# beide Zhaehler ist die Wahrheit, ob gedroppt wurde.
	entsmax=$(grep -ao "ents=[0-9]*" "$LOG" | cut -d= -f2 | sort -n | tail -1)
	[ -n "$entsmax" ] || entsmax=0
	[ "$entsmax" -gt "$boden" ] && boden="$entsmax"
	brust=$(grep -ao "brust_max=[0-9]*" "$LOG" | tail -1 | cut -d= -f2)
	[ -n "$brust" ] || brust=0
	ist=$(grep -ao "brust_ist=[0-9]*" "$LOG" | tail -1 | cut -d= -f2)
	[ -n "$ist" ] || ist=-1
	size=$(grep -ao "volle Truhe ([0-9]*" "$LOG" | head -1 | sed -n 's/.*(\([0-9]*\).*/\1/p')
	[ -n "$size" ] || size=0
	# hoechster Bruststand aus dem Log
	local stacks
	stacks=$(grep -ac "DUPE HAT GEKLAPPT" "$LOG")
	echo "$stacks|$boden|$brust|$ist|$size" > "$OUT_RES"

	if [ "$autodrop" = "1" ]; then
		echo "  Auto-Drop an: Boden-Items = $boden, max. Truhenstand = $brust"
		grep -a "dupetest" "$LOG" | tail -4 | sed 's/^.*\[dupetest\]/  [dupetest]/'
	else
		echo "  Auto-Drop aus: Boden-Items = $boden, max. Truhenstand = $brust"
		grep -a "ERGEBNIS" "$LOG" | tail -1 | sed 's/^.*ERGEBNIS: /  /'
	fi
	# Keep diagnostic logs outside the temporary test directory.
	local log_dir="${LOG_DIR:-${TMPDIR:-/tmp}}"
	if ! mkdir -p "$log_dir" ||
			! cp "$LOG" "$log_dir/chestdupe-lauf${autodrop}-${preload}.log" ||
			! cp "$TMP/client.log" "$log_dir/chestdupe-client${autodrop}-${preload}.log"; then
		echo "Fehler beim Speichern der Diagnose-Logs in $log_dir" >&2
		return 1
	fi
	# Chat-Ausgabe des CSM (Debug)
	grep -a "DBG auto_drop" "$LOG" | tail -2 | sed 's/^.*ChestDupe: /    CSM: /'
	if [ "$DEBUG_LOG" = "1" ]; then
		echo "    --- Rohlog (letzte 25 Zeilen mit dupetest/ChestDupe/ERROR) ---"
		grep -a "dupetest\|ChestDupe\|ERROR\|error" "$LOG" | tail -25 | sed 's/^/      /'
	fi
	# Diagnose-Datei des CSM (falls vorhanden)
	if [ -f "$U/chest_dupe_diag.log" ]; then
		echo "  --- CSM-Diag (Auszug) ---"
		tail -6 "$U/chest_dupe_diag.log" | sed 's/^/    /'
	fi
	find "$U" -name "*diag*" -newer "$TMP/world" 2>/dev/null | head -3
	rm -rf "$TMP"
}

OUT_RES="$(mktemp /tmp/chestdupe-res.XXXXXX)"
trap 'rm -f "$OUT_RES"' EXIT

echo "=== Lauf 1: Dupe ohne Auto-Drop ==="
run_test 0 0 120
RES1="$(cat "$OUT_RES")"
S1="${RES1%%|*}"; R="${RES1#*|}"; B1="${R%%|*}"; R="${R#*|}"; C1="${R%%|*}"

echo
echo "=== Lauf 2: Dupe MIT Auto-Drop ==="
run_test 1 0 120
RES2="$(cat "$OUT_RES")"
S2="${RES2%%|*}"; R="${RES2#*|}"; B2="${R%%|*}"; R="${R#*|}"; C2="${R%%|*}"
R="${R#*|}"; I2="${R%%|*}"

echo
echo "=== Lauf 3: Truhe ab START voll + Auto-Drop (Guard-Deadlock) ==="
run_test 1 1 60
RES3="$(cat "$OUT_RES")"
S3="${RES3%%|*}"; R="${RES3#*|}"; B3="${R%%|*}"; R="${R#*|}"; C3="${R%%|*}"
R="${R#*|}"; I3="${R%%|*}"; N3="${R#*|}"

echo
echo "=== Auswertung ==="
FAIL=0
if [ "$S1" -lt 1 ]; then
	echo "  FEHLER: der Dupe hat nicht geklappt (Brust blieb leer)"
	FAIL=1
else
	echo "  OK: der Dupe hat geklappt (Brust gefuellt)"
fi
if [ "$B1" -gt 0 ]; then
	echo "  FEHLER: ohne Auto-Drop lagen schon Items auf dem Boden ($B1)"
	FAIL=1
else
	echo "  OK: ohne Auto-Drop liegen keine Items auf dem Boden"
fi
if [ "$C1" -lt 1 ]; then
	echo "  FEHLER: ohne Auto-Drop fuellte sich die Truhe nie (max $C1)"
	FAIL=1
else
	echo "  OK: ohne Auto-Drop fuellte sich die Truhe (max $C1 Stacks)"
fi
# Lauf 2: der Server-Poll sieht (anders als frueher -- Drop lief jetzt VOR
# dupe_cycle) den frischen Zyklus-Stack EINEN Frame, nachdem der Client ihn
# gelegt hat. C2 kann also C1 erreichen, aber nie UEBERSCHREITEN: mit
# Auto-Drop wird nichts mehr liegengelassen. C2 > C1 haette bedeutet, die
# Schleife laeuft weiter, waehrend der Drop sie leert (Dupe-Drop-Deadlock).
if [ "$C2" -gt "$C1" ]; then
	echo "  FEHLER: mit Auto-Drop ist die Truhe voller (max $C2 > $C1) --"
	echo "          der Drop haelt mit dem Dupe nicht Schritt"
	FAIL=1
else
	echo "  OK: mit Auto-Drop bleibt die Truhe leerer (max $C2 <= $C1)"
fi
if [ "$S2" -lt 1 ]; then
	echo "  FEHLER: mit Auto-Drop lief der Dupe nicht (Brust blieb leer)"
	FAIL=1
else
	echo "  OK: mit Auto-Drop lief der Dupe weiter ($S2 gefuellte Stufen)"
fi
if [ "$I2" -ge 1 ]; then
	echo "  FEHLER: Lauf 2 endete mit gefuellter Truhe (brust_ist=$I2)"
	FAIL=1
else
	echo "  OK: Lauf 2 endete leer (brust_ist=$I2)"
fi
if [ "$B2" -lt 1 ]; then
	echo "  FEHLER: mit Auto-Drop lag nichts auf dem Boden (ents_max=$B2)" \
		"-- der Drop lief nie"
	FAIL=1
else
	echo "  OK: mit Auto-Drop fielen Items auf den Boden ($B2)"
fi
# Lauf 3: volle Truhe von Anfang an. OHNE Fix stoppt der Kapazitaets-Guard
# die Schleife UND (weil er VOR dem Auto-Drop returnt) ebenso den Drop --
# die Truhe bleibt voll und nichts faellt auf den Boden.
if [ "$N3" -lt 1 ]; then
	echo "  FEHLER: Lauf 3 Setup -- die Truhe wurde nicht vorbefuellt"
	FAIL=1
elif [ "$I3" -gt "$((N3 / 2))" ]; then
	# Nicht nur "irgendwie weniger": die Rotation muss die volle Truhe
	# in einem Sweep leeren. Ohne Rotation blieb brust_ist=26 von 27
	# (nur Slot 0 geleert, dann Stall) -- 26 > 13 faellt hier sauber rot.
	echo "  FEHLER: volle Truhe wurde nicht spuerbar entleert"
	echo "          (brust_ist=$I3 von $N3, zulaessig <= $((N3 / 2)))"
	FAIL=1
else
	echo "  OK: volle Truhe leert sich (brust_ist=$I3 von $N3)"
fi
if [ "$B3" -lt 1 ]; then
	echo "  FEHLER: volle Truhe + Auto-Drop: nichts auf dem Boden (boden_max=$B3)"
	FAIL=1
else
	echo "  OK: volle Truhe + Auto-Drop: Items auf dem Boden (boden_max=$B3)"
fi

if [ "$FAIL" = "0" ]; then
	echo "VERIFY=PASS -- Dupe + Auto-Drop funktionieren"
	exit 0
fi
echo "VERIFY=FAIL"
exit 1
