-- E2E-Verifikation ext_menu (v4: native ExtPanel bridge shim)
local SCRIPT = debug.getinfo(1, "S").source:sub(2)
local MODDIR = assert(SCRIPT:match("^(.*)/tests/[^/]+$"),
	"Could not determine ext_menu directory from test path")
local ROOT = SCRIPT:match("^(.*)/clientmods%-ext/ext_menu/tests/[^/]+$") or "."
local SETTINGS, SHOWN, INPUT_CB, COMMANDS = {}, {}, nil, {}
local AFTER, LOG, GLOBALSTEPS = {}, {}, {}
local SENDING_CHAT, CHAT_MESSAGES
local core = {
	registered_chatcommands = COMMANDS,
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
	register_on_sending_chat_message = function(cb) SENDING_CHAT = cb end,
	run_callbacks = function() return false end,
	display_chat_message = function(message)
		CHAT_MESSAGES = CHAT_MESSAGES or {}
		CHAT_MESSAGES[#CHAT_MESSAGES + 1] = message
	end,
	gettext = function(message) return message end,
	set_last_run_mod = function() end,
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
assert(loadfile(ROOT .. "/builtin/client/chatcommands.lua"))()

-- Fail-safe: nach dem Laden darf kein alter Zustand das Panel aufmachen
check(SETTINGS["ext_menu.open"] == false, "fail-safe: ext_menu.open=false beim Laden")

check(COMMANDS["menu"] ~= nil, ".menu registriert")
local ok, consumed = pcall(function() return SENDING_CHAT(".menu") end)
check(ok and consumed, ".menu im Chat wird lokal verarbeitet: " .. tostring(consumed))
check(SETTINGS["ext_menu.open"] == true, ".menu-Chataufruf öffnet das Panel")
check(next(SHOWN) == nil, "keine show_formspec mehr (natives Panel)")
check(#AFTER == 0, "kein after-Queue (keine Animationen mehr)")
local ok2, consumed2 = pcall(function() return SENDING_CHAT(".menu") end)
check(ok2 and consumed2, "zweiter .menu-Chataufruf wird lokal verarbeitet")
check(SETTINGS["ext_menu.open"] == false, "zweiter Chataufruf togglet wieder zu (false)")
local ok3, consumed3 = pcall(function() return SENDING_CHAT(".not_a_command") end)
check(ok3 and consumed3, "unbekannter Clientbefehl wird lokal abgefangen")
check(CHAT_MESSAGES[#CHAT_MESSAGES]:find("Invalid command: not_a_command", 1, true) ~= nil,
	"unbekannter Clientbefehl zeigt lokale Fehlermeldung")

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
