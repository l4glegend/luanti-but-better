-- ext_menu — rendered-panel menu for the ext fork.
-- Visual system: fully rendered graphics (tools/gen_menu_bg.py) with invisible
-- clickable zones on top (layout.lua geometry). Animations use timed
-- re-render frames driven by core.after (entrance stagger + switch slide).
-- v4: rendering moved to the native C++ ExtPanel (src/client/extpanel.cpp);
-- this mod is only a bridge shim: .menu sets ext_menu.open=true. The legacy
-- formspec path below is kept as fallback and only active when
-- DISABLED_FORMSPEC = false.
local DISABLED_FORMSPEC = true

-- fail-safe: never wake up with the panel open across restarts
core.settings:set_bool("ext_menu.open", false)

if DISABLED_FORMSPEC then
	core.log("action", "[ext_menu] native bridge v=4 (formspec disabled)")
	core.register_chatcommand("menu", {
		description = "Ext settings panel (XRay, Fullbright, No-Night, ChestDupe)",
		func = function()
			-- toggle: the engine closes the panel when the flag goes false
			local open = core.settings:get_bool("ext_menu.open", false)
			core.log("action", "[ext_menu] .menu command -> ext_menu.open=" ..
				tostring(not open))
			core.settings:set_bool("ext_menu.open", not open)
			return true
		end,
	})
	-- AutoTotem: legt einen Totem automatisch in die Offhand, wenn dort
	-- keiner liegt.
	local TOTEM = "mcl_totems:totem"
	local totem_move = nil
	if type(InventoryAction) == "function" then
		totem_move = InventoryAction("move")
		totem_move:to("current_player", "offhand", 1)
	end
	core.register_globalstep(function()
		if not totem_move then return end
		if not core.settings:get_bool("autototem", false) then return end
		local inv = core.get_inventory("current_player")
		if not inv then return end
		local offhand = inv.offhand
		local main = inv.main
		if not offhand or not main then return end
		local in_offhand = offhand[1]
		if in_offhand and not in_offhand:is_empty()
				and in_offhand:get_name() == TOTEM then
			return -- der Totem ist schon in der Offhand
		end
		for idx, stack in ipairs(main) do
			if stack and not stack:is_empty() and stack:get_name() == TOTEM then
				totem_move:from("current_player", "main", idx)
				totem_move:apply()
				return
			end
		end
	end)

	-- eigene Kommandos je Option: direkter Toggle, ohne Panel
	local function make_toggle(key)
		return function()
			core.settings:set_bool(key, not core.settings:get_bool(key))
			return true
		end
	end
	core.register_chatcommand("xray",      { description = "Toggle XRay",        func = make_toggle("xray") })
	core.register_chatcommand("fullbright",{ description = "Toggle Fullbright",  func = make_toggle("fullbright") })
	core.register_chatcommand("nonight",   { description = "Toggle No-Night",    func = make_toggle("no_night") })
	core.register_chatcommand("chestdupe", { description = "Toggle ChestDupe",   func = make_toggle("chest_dupe") })
	core.register_chatcommand("freecam",   { description = "Toggle FreeCam",     func = make_toggle("freecam") })
	core.register_chatcommand("autototem", { description = "Toggle AutoTotem",   func = make_toggle("autototem") })
	-- Register a description only when this fork provides the cheat registry.
	if core.register_cheat_description then
		core.register_cheat_description("FreeCam", "Render", "freecam",
			"Fly the camera freely (key F4)")
	end
	return
end

local FS_NAME = "ext_menu:menu"
local L = dofile(core.get_modpath("ext_menu") .. "/layout.lua")

-- ---------- state ----------
-- vis[i] describes what frame each main row is currently showing.
--   ent_k  = entrance frame index (nil once settled)
--   sw     = "on" | "off"      (settled switch visual)
--   sw_dir = "off_to_on" | "on_to_off" | nil (slide in progress)
--   sw_f   = frame index of the slide
local vis = {}
for i in ipairs(L.MAIN) do
	vis[i] = { ent_k = 0, sw = "off", sw_dir = nil, sw_f = nil }
end
local page = nil -- nil = closed, "main", or a module key

local function esc(s) return core.formspec_escape(tostring(s)) end

local function bool_setting(key, default)
	local ok, v = pcall(function() return core.settings:get_bool(key, default) end)
	return ok and (v == true)
end

local function set_bool_setting(key, want)
	pcall(function() core.settings:set_bool(key, want) end)
end

local function get_time()
	-- 33ms steps for ~30fps animations (crisp but cheap)
	return 0.033
end

-- ---------- formspec builders ----------
local INVIS = ("style_type[button;border=false;bg_color=#00000000;"
	.. "bgimg=ext_menu_blank.png;bgimg_hovered=ext_menu_blank.png;"
	.. "bgimg_pressed=ext_menu_blank.png;textcolor=#00000000]")

local function build_form()
	local fs = {}
	if page == nil or page == "main" then
		fs[#fs + 1] = ("formspec_version[4]size[%.2f,%.2f]"):format(L.W, L.H)
		fs[#fs + 1] = ("image[0,0;%.2f,%.2f;ext_menu_menu_bg.png]"):format(L.W, L.H)
		fs[#fs + 1] = INVIS
		for i, r in ipairs(L.MAIN) do
			local v = vis[i]
			local rowimg = (v.ent_k ~= nil)
				and ("ext_menu_row_%d_in_f%d.png"):format(i - 1, v.ent_k)
				or ("ext_menu_row_%d_set.png"):format(i - 1)
			fs[#fs + 1] = ("image[%.2f,%.2f;%.2f,%.2f;%s]"):format(r.x0, r.y, r.w, r.h, rowimg)
			local swfile
			if v.sw_dir ~= nil then
				swfile = ("ext_menu_sw_%s_f%d.png"):format(v.sw_dir, v.sw_f)
			elseif v.sw == "on" then
				swfile = "ext_menu_sw_off_to_on_f5.png"
			else
				swfile = "ext_menu_sw_on_to_off_f5.png"
			end
			fs[#fs + 1] = ("image[%.2f,%.2f;%.2f,%.2f;%s]"):format(
				r.sw_x, r.sw_y, r.sw_w, r.sw_h, swfile)
			-- click zones
			fs[#fs + 1] = ("button[%.2f,%.2f;%.2f,%.2f;btn_row_%s; ]"):format(
				r.x0, r.y, r.w, r.h, r.key)
			fs[#fs + 1] = ("button[%.2f,%.2f;%.2f,%.2f;btn_gear_%s; ]"):format(
				r.gear_x, r.y + (r.h - r.sw_h) / 2, r.gear_w, r.sw_h, r.key)
		end
		fs[#fs + 1] = ("button[%.2f,%.2f;%.2f,%.2f;btn_close; ]"):format(
			L.CLOSE_X, L.CLOSE_Y, L.CLOSE_S + 0.12, L.CLOSE_S + 0.12)
		return table.concat(fs)
	end

	-- module settings page
	local sub = L.SUB[page]
	local fs2 = {}
	fs2[#fs2 + 1] = ("formspec_version[4]size[%.2f,%.2f]"):format(sub.w, sub.h)
	fs2[#fs2 + 1] = ("image[0,0;%.2f,%.2f;ext_menu_sub_%s_bg.png]"):format(sub.w, sub.h, page)
	fs2[#fs2 + 1] = INVIS
	fs2[#fs2 + 1] = ("button[0.06,0.14;0.62,0.58;btn_back; ]")
	if page == "chest_dupe" then
		-- segmented mode control (left half select / right half select)
		local mode = core.settings:get("chest_dupe.mode", "Auto")
		if mode == "Auto" then
			fs2[#fs2 + 1] = "image[0.35,1.20;2.30,0.88;ext_menu_seg_sel_0.png]"
		else
			fs2[#fs2 + 1] = "image[2.65,1.20;2.30,0.88;ext_menu_seg_sel_1.png]"
		end
		fs2[#fs2 + 1] = "button[0.35,1.20;2.30,0.88;btn_mode_auto; ]"
		fs2[#fs2 + 1] = "button[2.65,1.20;2.30,0.88;btn_mode_cross; ]"
	end
	for j, row in ipairs(sub.rows) do
		local on = bool_setting(row.setting, false)
		fs2[#fs2 + 1] = ("image[%.2f,%.2f;%.2f,%.2f;%s]"):format(
			row.x0 + row.w - 1.10 - 0.22, row.y + (row.h - 0.55) / 2, 1.10, 0.55,
			on and "ext_menu_sw_off_to_on_f5.png" or "ext_menu_sw_on_to_off_f5.png")
		fs2[#fs2 + 1] = ("button[%.2f,%.2f;%.2f,%.2f;btn_sub_%d; ]"):format(
			row.x0, row.y, row.w, row.h, j)
	end
	return table.concat(fs2)
end

-- ---------- animation drivers ----------
local function show()
	pcall(function()
		core.log("action", "[ext_menu] render page=" .. tostring(page)
			.. " v=3 (menu_bg + stagger)")
	end)
	core.show_formspec(FS_NAME, build_form())
end

local function step_entrance(i, k)
	if page ~= "main" or vis[i].ent_k == nil then return end
	vis[i].ent_k = k
	if k >= L.ANIM - 1 then
		vis[i].ent_k = nil -- settled
		show()
		return
	end
	show()
	core.after(get_time(), function() step_entrance(i, k + 1) end)
end

local function play_entrance()
	for i in ipairs(L.MAIN) do
		vis[i].ent_k = 0
		core.after(i * 0.09, function() step_entrance(i, 0) end)
	end
end

local function do_toggle(i)
	local row = L.MAIN[i]
	local v = vis[i]
	local old = (v.sw == "on")
	local new = not old
	local dir = new and "off_to_on" or "on_to_off"
	set_bool_setting(row.key, new)
	v.sw = new and "on" or "off"
	v.sw_dir, v.sw_f = dir, 0
	show()
	local function step(f)
		if v.sw_dir ~= dir then return end -- unterbrochen durch neuen Toggle
		v.sw_f = f
		if f >= L.ANIM - 1 then
			v.sw_dir, v.sw_f = nil, nil
			show()
			return
		end
		show()
		core.after(get_time(), function() step(f + 1) end)
	end
	core.after(get_time(), function() step(1) end)
end

-- ---------- public entry ----------
local function open_main()
	page = "main"
	show()
	play_entrance()
end

local function open_module(key)
	page = key
	show()
end

-- ---------- input ----------
core.register_on_formspec_input(function(formname, fields)
	if formname ~= FS_NAME then return end
	if page == "main" then
		if fields.btn_close or fields.quit then
			page = nil
			core.show_formspec(FS_NAME, "")
			return
		end
		for i, r in ipairs(L.MAIN) do
			if fields["btn_row_" .. r.key] ~= nil then do_toggle(i) end
			if fields["btn_gear_" .. r.key] ~= nil then open_module(r.key) end
		end
	else
		local sub = L.SUB[page]
		if sub == nil then return end
		if fields.btn_back or fields.quit then
			open_main()
			return
		end
		if fields.btn_mode_auto ~= nil then
			pcall(function() core.settings:set("chest_dupe.mode", "Auto") end)
			show()
		end
		if fields.btn_mode_cross ~= nil then
			pcall(function() core.settings:set("chest_dupe.mode", "Crosshair only") end)
			show()
		end
		for j, row in ipairs(sub.rows) do
			if fields["btn_sub_" .. j] ~= nil then
				set_bool_setting(row.setting, not bool_setting(row.setting, false))
				show()
			end
		end
	end
end)

core.register_chatcommand("menu", {
	description = "Ext settings panel (XRay, Fullbright, No-Night, ChestDupe)",
	func = function() open_main() return true end,
})
