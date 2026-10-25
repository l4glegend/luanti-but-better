-- Key-Konsistenz zwischen C++-Panel, Lua-Bridge, chest_dupe-Mod und Engine.
--
-- Zweck: Ein Tippfehler in einem Setting-Namen (z. B. "chest_dupe.toggle"
-- statt "chest_dupe") macht eine Option wirkungslos, ohne dass ein Fehler
-- sichtbar wird -- genau die Klasse von Bug, die das native Panel nicht
-- selbst abdecken kann. Dieser Test vergleicht die Key-Tabellen aller
-- beteiligten Seiten.
--
-- Aufruf: luajit clientmods-ext/ext_menu/tests/ext_keys_consistency.lua
-- Repo-Wurzel: Argument > ENV > aus dem Speicherort dieses Tests ermitteln.
local SCRIPT = debug.getinfo(1, "S").source:sub(2)
local ROOT = (arg and arg[1]) or os.getenv("EXT_REPO")
	or SCRIPT:match("^(.*)clientmods%-ext/ext_menu/tests/[^/]+$")
if ROOT == "" then ROOT = "." end
assert(ROOT, "Could not determine repository root; pass it as an argument or set EXT_REPO")

local failed = 0
local function check(cond, label)
	if cond then
		print("PASS " .. label)
	else
		failed = failed + 1
		print("FAIL " .. label)
	end
end

local function read_file(path)
	local f = assert(io.open(path, "r"))
	local content = f:read("*a")
	f:close()
	return content
end

local function match_all(text, pattern)
	local out = {}
	for m in text:gmatch(pattern) do
		out[#out + 1] = m
	end
	return out
end

-- --- 1) C++-Panel: MAIN_ROWS (Label, Desc, Toggle-Key, Subpage) ---
local cpp = read_file(ROOT .. "/src/client/extpanel.cpp")
local rows = {}
for label, desc, key, page in cpp:gmatch(
	'{"([^"]*)",%s*"([^"]*)",%s*"([^"]*)",%s*"([^"]*)"}') do
	rows[#rows + 1] = { label = label, desc = desc, key = key, page = page }
end
check(#rows == 6, "C++: 6 MAIN_ROWS gefunden (gefunden: " .. #rows .. ")")

local panel_keys = {}
for _, r in ipairs(rows) do
	panel_keys[r.key] = true
end

-- --- 2) Engine: welche Bool-Keys liest der Client tatsaechlich? ---
-- (mapblock_mesh: xray/fullbright/no_night; game/localplayer/client: freecam)
local engine_src = read_file(ROOT .. "/src/client/mapblock_mesh.cpp")
for _, f in ipairs({ "src/client/game.cpp", "src/client/localplayer.cpp",
		"src/client/client.cpp", "src/client/game_internal.h",
		"src/client/extdropbar.cpp" }) do
	engine_src = engine_src .. "\n" .. read_file(ROOT .. "/" .. f)
end
local engine_bools = {}
-- both variants: getBool("x") and getBoolNoThrow("x", false)
for k in engine_src:gmatch('getBool%("([a-z_]+)"') do
	engine_bools[k] = true
end
for k in engine_src:gmatch('getBoolNoThrow%("([a-z_]+)"') do
	engine_bools[k] = true
end
check(engine_bools["xray"] == true, "Engine liest 'xray'")
check(engine_bools["fullbright"] == true, "Engine liest 'fullbright'")
check(engine_bools["no_night"] == true, "Engine liest 'no_night'")

for _, r in ipairs(rows) do
	-- Jeder Panel-Toggle muss ein Key sein, den die Engine liest
	-- (Ausnahmen: ChestDupe wird vom Client-Mod ausgewertet,
	--  drop_buttons wird vom ExtPanel selbst gelesen).
	if r.key ~= "chest_dupe" and r.key ~= "autototem" then
		check(engine_bools[r.key] == true,
			"Panel-Toggle '" .. r.key .. "' wird von der Engine gelesen")
	end
end

-- --- 3) chest_dupe-Mod: Settings-Konstanten ---
local cd = read_file(ROOT .. "/clientmods-ext/chest_dupe/init.lua")
local cd_settings = {}
for name, key in cd:gmatch('local%s+(SETTING_[A-Z_]+)%s*=%s*"([^"]+)"') do
	cd_settings[name] = key
end
check(cd_settings["SETTING_TOGGLE"] ~= nil, "chest_dupe: SETTING_TOGGLE vorhanden")
check(cd_settings["SETTING_MODE"] ~= nil, "chest_dupe: SETTING_MODE vorhanden")
check(cd_settings["SETTING_AUTOTAKE"] ~= nil, "chest_dupe: SETTING_AUTOTAKE vorhanden")
check(cd_settings["SETTING_LOG"] ~= nil, "chest_dupe: SETTING_LOG vorhanden")
check(cd_settings["SETTING_HOLD"] ~= nil, "chest_dupe: SETTING_HOLD vorhanden")

-- Der Panel-Toggle der ChestDupe-Zeile muss exakt der Mod-Key sein
local panel_cd_key = nil
for _, r in ipairs(rows) do
	if r.page == "chest_dupe" then
		panel_cd_key = r.key
	end
end
check(panel_cd_key ~= nil, "Panel hat eine ChestDupe-Zeile")
check(panel_cd_key == cd_settings["SETTING_TOGGLE"],
	"Panel-ChestDupe-Key == Mod-Key ('" .. tostring(panel_cd_key) ..
	"' vs '" .. tostring(cd_settings["SETTING_TOGGLE"]) .. "')")

-- Die im Panel geschriebenen ChestDupe-Optionen muessen vom Mod gelesen werden.
-- Gesucht sind die Key-Literale im Panel-Code (Tabellen + set/setBool-Aufrufe).
local panel_option_keys = {}
for lit in cpp:gmatch('"([a-z_]+%.[a-z_]+)"') do
	panel_option_keys[lit] = true
end
for _, name in ipairs({ "SETTING_MODE", "SETTING_AUTOTAKE", "SETTING_LOG",
		"SETTING_HOLD" }) do
	local key = cd_settings[name]
	check(key ~= nil and panel_option_keys[key] == true,
		"Panel schreibt Mod-Key '" .. tostring(key) .. "'")
end

-- --- 4) Lua-Bridge: make_toggle(...) muss dieselben Keys nutzen ---
local bridge = read_file(ROOT .. "/clientmods-ext/ext_menu/init.lua")
local bridge_keys = {}
for k in bridge:gmatch('make_toggle%("([^"]+)"%)') do
	bridge_keys[k] = true
end
for _, r in ipairs(rows) do
	-- die Bridge schaltet die Cheats, nicht die reinen UI-Schalter
	if r.key ~= "drop_buttons" and r.key ~= "autototem" then
		check(bridge_keys[r.key] == true,
			"Bridge schaltet denselben Key wie das Panel ('" .. r.key .. "')")
	end
end
for k in pairs(bridge_keys) do
	check(panel_keys[k] == true,
		"Bridge-Key '" .. k .. "' existiert auch im Panel")
end

-- --- 5) Subpage-IDs: Settings-Buttons muessen ihre Seite erreichen ---
-- Erwartet wird die indexbasierte Zuordnung: der Button bekommt
-- EP_SETTINGS_BASE + <zeilenindex>, der Handler schlaegt ueber genau
-- denselben Index in MAIN_ROWS nach. Damit erreicht jede Zeile ihre Seite.
check(cpp:find("EP_SETTINGS_BASE + i", 1, true) ~= nil,
	"Settings-Button wird mit dem Zeilenindex erzeugt (EP_SETTINGS_BASE + i)")
check(cpp:find("MAIN_ROWS[id - EP_SETTINGS_BASE]", 1, true) ~= nil,
	"Handler ordnet die Button-ID ueber den Zeilenindex zu")
check(cpp:find("EP_ID_BASE + i", 1, true) ~= nil,
	"Toggle-Button wird mit dem Zeilenindex erzeugt (EP_ID_BASE + i)")
check(cpp:find("MAIN_ROWS[id - EP_ID_BASE]", 1, true) ~= nil,
	"Handler ordnet die Toggle-ID ueber den Zeilenindex zu")

print(failed == 0 and "ALL PASS" or ("FAILURES: " .. failed))
os.exit(failed == 0 and 0 or 1)
