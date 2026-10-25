-- E2E-Verifikation ext_menu (v4: native ExtPanel bridge shim)
local SCRIPT = debug.getinfo(1, "S").source:sub(2)
local MODDIR = assert(SCRIPT:match("^(.*)/tests/[^/]+$"),
	"Could not determine ext_menu directory from test path")
local SETTINGS, SHOWN, INPUT_CB, COMMANDS = {}, {}, nil, {}
local AFTER, LOG, GLOBALSTEPS = {}, {}, {}
local core = {
	log = function(a, b) LOG[#LOG + 1] = (b ~= nil) and b or a end,
	settings = {
		get_bool = function(_, k, d)
			local v = SETTINGS[k]
			if v == nil then return d or false end
			return v
		end,
		set_bool = function(_, k, v) SETTINGS[k] = v and true or false end,
		get = function(_, k) return SETTINGS[k] end,
		set = function(_, k, v) SETTINGS[k] = v end,
	},
	show_formspec = function(n, f) SHOWN[n] = (SHOWN[n] or 0) + 1 end,
	register_on_formspec_input = function(cb) INPUT_CB = cb end,
	register_chatcommand = function(n, c) COMMANDS[n] = c end,
	register_globalstep = function(fn) GLOBALSTEPS[#GLOBALSTEPS + 1] = fn end,
	get_modpath = function() return MODDIR end,
	after = function(t, fn) AFTER[#AFTER + 1] = fn end,
}
_G.core, _G.minetest = core, core
local failed = 0
local function check(cond, label)
	if cond then print("PASS " .. label) else failed = failed + 1; print("FAIL " .. label) end
end

assert(loadfile(MODDIR .. "/init.lua"))()

-- Fail-safe: nach dem Laden darf kein alter Zustand das Panel aufmachen
check(SETTINGS["ext_menu.open"] == false, "fail-safe: ext_menu.open=false beim Laden")

check(COMMANDS["menu"] ~= nil, ".menu registriert")
local ok, err = pcall(function() COMMANDS["menu"].func() end)
check(ok, "func() without error: " .. tostring(err))
check(ok and err == nil, "kein Zweitfehler")

check(SETTINGS["ext_menu.open"] == true, ".menu setzt ext_menu.open=true")
check(next(SHOWN) == nil, "keine show_formspec mehr (natives Panel)")
check(#AFTER == 0, "kein after-Queue (keine Animationen mehr)")
local ok2, err2 = pcall(function() COMMANDS["menu"].func() end)
check(ok2, "second call without error")
check(SETTINGS["ext_menu.open"] == false, "zweiter Aufruf togglet wieder zu (false)")

-- per-option commands: eigene Kommandos je Option
local want = { xray = "xray", fullbright = "fullbright", nonight = "no_night",
	chestdupe = "chest_dupe", freecam = "freecam" }
for cmd, key in pairs(want) do
	local c = COMMANDS[cmd]
	check(c ~= nil, "." .. cmd .. " registriert")
	if c then
		check(core.settings:get_bool(key) == false, key .. " initial false")
		local okc, errc = pcall(function() c.func() end)
		check(okc, "." .. cmd .. " without error: " .. tostring(errc))
		check(core.settings:get_bool(key) == true, key .. " nach Toggle true")
		okc, errc = pcall(function() c.func() end)
		check(okc and core.settings:get_bool(key) == false,
			key .. " Toggling rueckwaerts")
		SETTINGS[key] = nil
	end
end

local has_v4 = false
for _, m in ipairs(LOG) do
	if m:find("ext_menu", 1, true) and m:find("v=4", 1, true) then has_v4 = true end
end
check(has_v4, "Load-Stempel im Log (v=4)")

if failed > 0 then os.exit(1) end
print("ALL PASS")
