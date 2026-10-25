-- ChestDupe — CSM PACKAGE (clientmods/chest_dupe)
-- Same logic as builtin/cheats/chest_dupe.lua. Keep both files in sync!
-- CSM adaptations:
--   * Self-disables when the builtin version is loaded (same chatcommands
--     would double-run the globalsteps -> check core.registered_chatcommands).
--   * No 'register_cheat' requirement: it registers its own F8 panel entry
--     only when the builtin cheat is absent (otherwise command-only).
-- ChestDupe — "input" list dupe (Mineclonia mcl_chests, upstream issue #4934)
-- Root cause: the *_small chest registers a hidden 1-slot list "input" (listring
-- workaround). Its on_metadata_inventory_put copies the put stack into "main"
-- via inv:add_item("main", stack) but does NOT clear "input". So the stack
-- stays in input AND a copy lands in main.
-- Target classes (only vectors that work on ANY server get auto-cycled):
--   NATIVE - chest_small + trapped chest_small duplicates everywhere, unpatched
--   DOUBLE - double chests: input list exists natively, but the server may
--            clear it right after copying (mcl_chests line ~721/893). Probe
--            decides per server; doubles degrade to singles there.
--   (v3 scope removed the MOD class: barrels/shulkers/furnaces needed the
--    "dupe_workaround" SERVER mod and never worked on foreign servers.)
-- Exploit: legit TOSERVER_INVENTORY_ACTION moves only, targeting the hidden
-- "input" list (the chest GUI only ever touches "main", so this is client-only).
-- Per cycle: recovery-take input -> put wielded stack into input (server copies
-- to container main) -> take input back out. Net gain: +1 full stack per cycle.
-- Controls: Taste 0 toggles the whole module on/off.
-- Hold-Mode (default on): cycles only run while the MIDDLE MOUSE BUTTON is
-- held; without it nothing happens and nothing is logged.

-- ---- CSM bootstrap: conflict guard against the builtin version ----
-- (mid-chunk top-level return is ILLEGAL in Lua, so the whole body lives in
-- csm_main() and is invoked conditionally below.)
if core.registered_chatcommands and core.registered_chatcommands["chesttake"] then
	core.display_chat_message("ChestDupe CSM: builtin ChestDupe is already "
		.. "loaded - this clientmod stays disabled to avoid double runs.")
	return
end

local function csm_main()
local HAS_REGISTER_CHEAT = core.register_cheat ~= nil

-- capability guard: the dupe needs the fork client APIs (InventoryAction etc.)
if not HAS_REGISTER_CHEAT and type(InventoryAction) ~= "table"
		and type(InventoryAction) ~= "function" then
	core.display_chat_message("ChestDupe: this clientmod requires fork-specific "
		.. "client APIs (InventoryAction + input keys) - disabled here.")
	return
end

-- Node classes by dupe-vector availability on ANY server:
--  NATIVE  - the vanilla mcl_chests listring bug (works everywhere: singles)
--  DOUBLE  - input list exists, but the server may clear it after copying
--            (probe decides per server)
--  (v3 scope: ONLY vector classes that work on foreign/ORIG servers are kept;
local NATIVE_NODES = {
	"mcl_chests:chest_small",
	"mcl_chests:trapped_chest_small",
	"mcl_chests:trapped_chest_on_small",
}
local DOUBLE_NODES = {
	"mcl_chests:chest_left",
	"mcl_chests:chest_right",
	"mcl_chests:trapped_chest_left",
	"mcl_chests:trapped_chest_right",
	"mcl_chests:trapped_chest_on_left",
	"mcl_chests:trapped_chest_on_right",
}

local function classify_node(name)
	if not name or name == "" or name == "ignore" then return nil end
	for _, n in ipairs(NATIVE_NODES) do
		if name == n then return "native" end
	end
	for _, n in ipairs(DOUBLE_NODES) do
		if name == n then return "double" end
	end
	return nil
end

local SCAN_RADIUS = 9
local SETTING_TOGGLE = "chest_dupe"
local SETTING_MODE = "chest_dupe.mode"       -- "Auto" | "Crosshair only"
local SETTING_AUTOTAKE = "chest_dupe.autotake"
local SETTING_AUTODROP = "chest_dupe.autodrop"   -- drop the duped stacks right away
local SETTING_LOG = "chest_dupe.log"
local SETTING_HOLD = "chest_dupe.hold_mode"
local HOTKEY_KEY_0 = "KEY_KEY_0"

local function pos_string(pos)
	return string.format("%d,%d,%d", pos.x, pos.y, pos.z)
end

local function nodemeta_inv_name(pos)
	return "nodemeta:" .. pos_string(pos)
end

local function say(msg)
	core.display_chat_message(core.get_color_escape_sequence("#6AF78B")
		.. "ChestDupe: " .. core.get_color_escape_sequence("#FFFFFF") .. msg)
end

-- Diagnostics: the client builtin sandbox has NO io library (file write is
-- available on the server builtin env only). Keep an in-memory ring buffer
-- as the always-available sink; when io IS present it also appends to the
-- diag file. Gated by SETTING_LOG ("Log"): off = no buffer writes, no chat.
-- '.chestlog' prints the last buffered entries (works even without io).
local DIAG_FILE = core.get_user_path
	and (core.get_user_path() .. "/chest_dupe_diag.log") or "chest_dupe_diag.log"
local diag_t = 0 -- monotonic accumulator (os.clock is NOT in the sandbox)
local _IO = rawget(_G, "io")
local has_io = type(_IO) == "table" and type(_IO.open) == "function"
local has_osdate = type(os) == "table" and type(os.date) == "function"
local diag_buf = {}
local DIAG_BUF_MAX = 300
local function diag(msg)
	if not core.settings:get_bool(SETTING_LOG, true) then
		return
	end
	local ts
	if has_osdate then
		ts = os.date("%H:%M:%S ")
	elseif diag_t > 0 then
		ts = string.format("[%7.2fs] ", diag_t)
	else
		ts = ""
	end
	local line = ts .. tostring(msg)
	diag_buf[#diag_buf + 1] = line
	if #diag_buf > DIAG_BUF_MAX then table.remove(diag_buf, 1) end
	if not has_io then return end
	pcall(function()
			local f = _IO.open(DIAG_FILE, "a")
		if f then
			f:write(line .. "\n")
			f:close()
		end
	end)
end

local function player_inv()
	return core.get_inventory("current_player")
end

local function is_chest_node(name)
	return classify_node(name) ~= nil
end

-- What the crosshair saw when it was not a dupe-target (for the debug/scan
-- output only; idle is silent now).
local last_look_reason = nil

local function find_chest()
	local lp = core.localplayer
	if not lp then return nil end
	local lpos = lp:get_pos()
	-- Priority: native (works everywhere) -> doubles
	local passes = { NATIVE_NODES, DOUBLE_NODES }
	for _, list in ipairs(passes) do
		local nodes = core.find_nodes_near(lpos, SCAN_RADIUS, list)
		if nodes and #nodes > 0 then
			local best, best_d
			for _, p in ipairs(nodes) do
				local d = vector.distance(lpos, p)
				if not best_d or d < best_d then
					best, best_d = p, d
				end
			end
			return best
		end
	end
	return nil
end

-- Chest under the crosshair, if it is a dupe target
local function look_chest()
	local lp = core.localplayer
	if not lp then return nil end
	local pt = lp:get_pointed_thing()
	if not pt or pt.type ~= "node" or not pt.under then
		last_look_reason = "nothing"
		return nil
	end
	local name = core.get_node_name(pt.under)
	if not is_chest_node(name) then
		last_look_reason = name
		return nil
	end
	last_look_reason = nil
	return {x = pt.under.x, y = pt.under.y, z = pt.under.z}
end

local function send_move(from_inv, from_list, from_i, to_inv, to_list, to_i, count)
	local act = InventoryAction("move")
	act:from(from_inv, from_list, from_i)
	act:to(to_inv, to_list, to_i)
	if count then
		act:set_count(count)
	end
	act:apply()
end

-- One dupe cycle.
--
-- The order matters, and the target slot of M1 decides whether the dupe
-- duplicates the stack in the hand or a DIFFERENT one:
--
--   M1  chest "input" -> a FREE player slot
--       (never the wielded slot: the server would SWAP the two stacks and
--        the hand would hold a foreign item afterwards)
--   M2  wielded slot -> chest "input"
--       (the server copies the stack into "main" -- that is the exploit)
--   M3  chest "input" -> wielded slot
--       (the wielded slot is empty now, so the hand keeps its own stack)
--
-- All moves are validated server-side; clamps/rejections are harmless no-ops.
local function free_player_slot()
	local inv = player_inv()
	local list = inv and inv.main
	if not list then return nil end
	for pi, ps in pairs(list) do
		if ps:is_empty() then
			return pi
		end
	end
	return nil
end

local function dupe_cycle(chest, slot_idx, name, count)
	local dst = nodemeta_inv_name(chest)
	diag("cycle node=" .. (core.get_node_name(chest) or "?") .. " pos=" .. pos_string(chest)
		.. " slot=" .. slot_idx .. " item=" .. tostring(name) .. "x" .. tostring(count))
	-- M1: the leftover in the chest input goes to a free slot -- NOT to the
	-- wielded slot, that would swap the stacks and change the item in hand
	local free = free_player_slot()
	if free then
		send_move(dst, "input", 1, "current_player", "main", free)
		diag("  M1 (recover -> free slot " .. free .. ") sent")
	end
	-- M2: the stack in the hand goes into the chest input
	send_move("current_player", "main", slot_idx, dst, "input", 1, count)
	diag("  M2 (put) sent")
	-- M3: take it back into the (now empty) wielded slot
	send_move(dst, "input", 1, "current_player", "main", slot_idx)
	diag("  M3 (take-back) sent")
	return name, count
end

-- Stale-state insurance on toggle-off: pull whatever sits in the hidden input
-- list back out into a free player slot (worst case the server swaps it with
-- the wielded item - self-healing on the next enable, nothing can be lost).
local function flush_input(chest)
	if not chest then return end
	local lp = core.localplayer
	local inv = player_inv()
	if not lp or not inv then return end
	-- In the client the inventory reference is a plain lua table with the
	-- lists as fields (inv.main), not an object with get_list().
	local list = inv.main
	if not list then return end
	local target
	for pi, ps in pairs(list) do
		if ps:is_empty() then
			target = pi
			break
		end
	end
	-- The lua API is 1-based, the engine index is 0-based (see dupe_cycle)
	send_move(nodemeta_inv_name(chest), "input", 1, "current_player", "main",
		target or lp:get_wield_index())
end

-- Free chest-main capacity for one item type. nil = unknown (chest not synced).
local function chest_free_for(pos, itemname)
	local inv = core.get_inventory(nodemeta_inv_name(pos))
	if not inv or not inv.main then return nil end
	local list = inv.main
	-- core.registered_items only exists on the server. In the client-side mod
	-- it is nil, so fall back to the standard stack size.
	local reg_items = core.registered_items
	local def = reg_items and reg_items[itemname]
	local stack_max = (def and def.stack_max) or 64
	local free = 0
	for _, ps in ipairs(list) do
		if ps:is_empty() then
			free = free + stack_max
		elseif ps:get_name() == itemname then
			free = free + ps:get_free_space()
		end
	end
	return free
end

-- --------------------------------------------------------------------------
-- Auto-Drop: the duplicated stacks land in the chest "main" list. With
-- Auto-Drop on the chest content falls on the ground right away (the
-- duplicated stacks are gone for good, they are NOT collected into the
-- inventory) -- so the chest never fills up and the cycle keeps running.
--
-- The client only sees the chest content while the chest window is OPEN,
-- so a "only the new stacks" comparison is not possible while the dupe runs
-- headless. Therefore the whole chest content is dropped: that is also the
-- fastest way (all drop actions go out in the same frame).
-- --------------------------------------------------------------------------
local function autodrop_chest(pos)
	if not pos then return false end
	core.drop_inventory_list(nodemeta_inv_name(pos), "main")
	return true
end

-- Snapshot of the chest "main" list: { [slot] = {name=, count=} }
-- The client only sees the chest content while the chest window is OPEN
-- (then the server syncs it), so this needs an open chest.
local function chest_snapshot(pos)
	local inv = core.get_inventory(nodemeta_inv_name(pos))
	local list = inv and inv.main
	if not list then return nil end
	local snap = {}
	for i, st in ipairs(list) do
		if st and not st:is_empty() then
			snap[i] = {name = st:get_name(), count = st:get_count()}
		end
	end
	return snap
end

-- Drops the difference between the current chest state and the snapshot:
-- ONLY the duplicated stacks, one drop action per changed slot (dropping the
-- whole list would be 32 actions per cycle -- that floods the server and the
-- dupe itself stops working).
-- Returns the number of dropped items.
local function autodrop_diff(pos, before)
	local inv = core.get_inventory(nodemeta_inv_name(pos))
	local list = inv and inv.main
	if not list or not before then return 0 end
	local loc = nodemeta_inv_name(pos)
	local dropped = 0
	for i, st in ipairs(list) do
		if st and not st:is_empty() then
			local b = before[i]
			local diff
			if b and b.name == st:get_name() then
				diff = st:get_count() - b.count
			elseif not b then
				diff = st:get_count() -- slot was empty before
			else
				diff = 0 -- another item in that slot: not ours
			end
			if diff > 0 then
				-- the lua list is 1-based, the engine action index is 0-based
				core.drop_inventory_slot(loc, "main", i - 1, diff)
				dropped = dropped + diff
			end
		end
	end
	return dropped
end

-- Move all chest-main stacks into the player inventory. Reads the client-side
-- chest view, so the chest must have been opened once (it only syncs while
-- open). Planning updates the local view so no two moves race for one slot;
-- the server clamps overflows, nothing can be lost.
local function collect(chest)
	local pos = chest or find_chest()
	if not pos then
		return false, "no chest in reach"
	end
	local cinv = core.get_inventory(nodemeta_inv_name(pos))
	local linv = player_inv()
	-- in the client the inventory reference is a lua table with the lists
	-- as fields (inv.main)
	local clist = cinv and cinv.main
	if not clist then
		return false, "chest inventory not synced yet - open the chest once, then run again"
	end
	local llist = linv and linv.main
	if not llist then
		return false, "player inventory unavailable"
	end
	local dst = nodemeta_inv_name(pos)
	local moves = 0
	for ci, cstack in ipairs(clist) do
		if cstack and not cstack:is_empty() then
			local target
			for pi, pstack in pairs(llist) do
				if pstack:is_empty()
						or (pstack:get_name() == cstack:get_name()
						and pstack:get_free_space() > 0) then
					target = pi
					break
				end
			end
			if target then
				send_move(dst, "main", ci, "current_player", "main", target,
					cstack:get_count())
				moves = moves + 1
				local cur = llist[target]
				if cur and not cur:is_empty() and cur:get_name() == cstack:get_name() then
					cur:add_item(cstack)
				else
					llist[target] = cstack
				end
				-- the client inventory is a read-only view: no write-back
			end
		end
	end
	return true, moves == 0 and "chest is empty" or (moves .. " stack(s) requested")
end

-- --------------------------------------------------------------------------
-- Cheat registration + settings panel (bool / slider_int / selectionbox only)
-- --------------------------------------------------------------------------
-- register_cheat is builtin-Lua (not a C++ CSM API): guard it so a pure-CSM
-- client (builtin ChestDupe removed) still boots; command fallback remains.
if HAS_REGISTER_CHEAT then
core.register_cheat("ChestDupe", "Misc", SETTING_TOGGLE)
core.register_cheat_description("ChestDupe", "Misc", SETTING_TOGGLE,
	"Input-list dupe: chest-class targets (small chests, double chests) " ..
	"dupe continuously like small chests while held. A passive probe " ..
	"reports per server which ones actually dupe; unsupported containers " ..
	"are proven and skipped. Taste 0 toggles. Hold-Mode (default " ..
	"on): dupes only while the middle mouse button is held. 'Log' toggles " ..
	"chat lines + diag file. 'Auto-Drop' drops the duplicated stacks straight " ..
	"out of the chest (permanently on the ground, only the duped ones).")
core.register_cheat_setting("Mode", "Misc", SETTING_TOGGLE, SETTING_MODE,
	{type = "selectionbox", options = {"Auto", "Crosshair only"}})
core.register_cheat_setting("Hold-Mode", "Misc", SETTING_TOGGLE, SETTING_HOLD,
	{type = "bool"})
core.register_cheat_setting("Auto-Collect", "Misc", SETTING_TOGGLE, SETTING_AUTOTAKE,
	{type = "bool"})
core.register_cheat_setting("Auto-Drop", "Misc", SETTING_TOGGLE, SETTING_AUTODROP,
	{type = "bool"})
core.register_cheat_setting("Log", "Misc", SETTING_TOGGLE, SETTING_LOG,
	{type = "bool"})
end -- HAS_REGISTER_CHEAT

local cached_chest = nil
local rescan_timer = 0
local prev_enabled = false
local cycle_total = 0
local prev_key0 = false
local cycle_cd = 0 -- seconds until the next dupe cycle is allowed
local cycle_log_cd = 0 -- chat-log throttle when cycles run per-frame

-- ---- non-native container reality probe (double chests) -------------------
local probe_label = nil
local probe_fmt = {
	double = {
		hint = "double chest: duping now - verdict when the chest is opened "
			.. "once (unpatched servers fall back to singles)",
		obs = "double chest: verdict paused - open the chest once for a "
			.. "definitive check",
		fail = "double chest: THIS SERVER clears the input after copying - "
			.. "doubles can't dupe here. Single chests still dupe everywhere.",
	},
}
-- Idles are silent in Hold-Mode. IMPORTANT facts (probe results, blockers,
-- wield loss) are ALWAYS printed (force = canNOT be turned off) so a broken
-- run can always be diagnosed from chat AND the always-on diag file below.
local last_state_msg = ""
local function state_msg(kind, msg, force)
	if last_state_msg == kind then return end
	last_state_msg = kind
	if not force and core.settings:get_bool(SETTING_HOLD, true) then return end
	say(msg)
end
local function is_double_node(name)
	return classify_node(name) == "double"
end

local function chest_count(pos, item)
	local inv = core.get_inventory(nodemeta_inv_name(pos))
	if not inv or not inv.main then return nil end
	local list = inv.main
	local n = 0
	for _, s in ipairs(list) do
		if s:get_name() == item then n = n + s:get_count() end
	end
	return n
end

local double_probe = nil   -- {pos, item, before, t, noobs, tries}
local probe_failed = {}    -- [poskey] = true once proven unable to dupe
local probe_retry = {}     -- [poskey] = diag_t + cd after noobs give-up
local probe_noobs = {}     -- [poskey] = consecutive noobs give-up count
local probe_okall = {}     -- [poskey] = true once proven ABLE to dupe
local double_hint_done = {}

local DOUBLE_SETTLE = 0.8    -- wait for one full server roundtrip per try
local DOUBLE_MAX_FAILS = 2
local NOOBS_GRACE = 2.6      -- give-up window if the container is never synced
local PROBE_RETRY_CD = 8     -- re-try an unverified noobs target after this
-- CYCLE_INTERVAL = 0 → zero-width gate: cycles run every frame, no timer
-- (original full-speed behavior; the previous 0.25s pacing was review-era
-- spam-conservatism, user verdict: the dupe must have no delay in the ideal case)
local CYCLE_INTERVAL = 0

-- Probe bookkeeping; runs every frame while the module is enabled.
local function probe_tick(dtime)
	local pr = double_probe
	if not pr then return end
	pr.t = pr.t + dtime
	local pos = pr.pos
	if not pos or not pos.x then
		double_probe = nil -- world changed under us
		return
	end
	local pk = pos_string(pos)
	if probe_failed[pk] then
		double_probe = nil
		return
	end
	if pr.noobs then
		-- container view not synced yet (never opened / closed mid-probe)
		local now = chest_count(pos, pr.item)
		if now ~= nil then
			pr.before, pr.noobs = now, false
			pr.t = 0
		elseif pr.t >= NOOBS_GRACE then
			-- never got a synced view: cannot measure here. Park the probe
			-- with a cooldown (cycling continues regardless) - opening the
			-- container once re-arms the measurement on the next attempt.
			-- After 3 give-ups the container is considered un-dupeable here
			-- (e.g. patched doubles whose input list is cleared).
			local nc = (probe_noobs[pk] or 0) + 1
			probe_noobs[pk] = nc
			if nc >= 3 then
				probe_failed[pk] = true
				local fmt = probe_fmt[probe_label or "double"]
				state_msg("doublefail:" .. (probe_label or "double"),
					fmt.fail, true)
				diag("probe FAIL (never synced after 3 give-ups) "
					.. (probe_label or "?") .. " " .. pk)
			else
				local fmt = probe_fmt[probe_label or "double"]
				if double_hint_done[pk] and not probe_okall[pk] then
					state_msg("doubleobs:" .. (probe_label or "double"),
						fmt.obs, true)
				end
				diag("probe noobs give-up " .. (probe_label or "?") .. " " .. pk)
				probe_retry[pk] = diag_t + PROBE_RETRY_CD
			end
			double_probe = nil
		end
		return
	end
	-- synced view: live check
	local now = chest_count(pos, pr.item)
	if now == nil then
		-- view lost mid-probe (chest closed): switch to noobs handling
		pr.noobs, pr.t = true, 0
		return
	end
	if now >= (pr.before or 0) + 1 then
		-- count grew = the server kept the copy = dupeable here
		probe_okall[pk] = true
		diag("probe SUCCESS " .. (probe_label or "?") .. " " .. pk
			.. " before=" .. pr.before .. " after=" .. now)
		double_probe = nil
		return
	end
	-- a FULL main can never grow: pause measurement (no failure count),
	-- the generic capacity guard stops cycling in this state
	if chest_free_for(pos, pr.item) == 0 then
		pr.t = 0
		return
	end
	-- tries count settle WINDOWS, not frames: one observation per
	-- DOUBLE_SETTLE, so slow servers get a fair roundtrip each
	if pr.t >= DOUBLE_SETTLE then
		pr.tries = pr.tries + 1
		diag("probe nochange tries=" .. pr.tries .. " before=" .. pr.before
			.. " after=" .. now)
		if pr.tries >= DOUBLE_MAX_FAILS then
			probe_failed[pk] = true
			local fmt = probe_fmt[probe_label or "double"]
			state_msg("doublefail:" .. (probe_label or "double"), fmt.fail, true)
			diag("probe FAIL (server clears input) " .. (probe_label or "?")
				.. " " .. pk)
			double_probe = nil
		else
			pr.t = 0 -- another settle window
		end
	end
end

-- wielded-stack cache (see header comment): survives transient empty views
local wield_idx_prev = nil
local wield_name, wield_count = nil, nil
local wield_empty_time = 0

-- The step runs protected: a runtime error (e.g. a server-only API that the
-- client does not provide) must not kill the whole cheat every frame.
local step_errors = 0
-- Auto-Drop: 0 = one drop action per frame, rotating through the chest
-- slots. The server ignores empty slots, so this drains a full chest in
-- one sweep (one slot per frame) instead of the old 32-actions-per-frame
-- flooding -- and it can never starve: the block runs before the capacity
-- guard.
local AUTODROP_INTERVAL = 0
local autodrop_cd = 0
local autodrop_slot = 0 -- rotating drop cursor (0-based engine slot index)
local autodrop_dropped = 0
local function chest_dupe_step(dtime)
	local lp = core.localplayer
	if not lp then
		prev_enabled = false
		prev_key0 = false
		cached_chest = nil -- fresh join: last session's target is invalid
		wield_idx_prev = nil
		wield_name, wield_count = nil, nil
		wield_empty_time = 0
		return
	end

	-- probe bookkeeping + cycle pacing
	diag_t = diag_t + dtime
	cycle_cd = cycle_cd - dtime
	if cycle_cd < 0 then cycle_cd = 0 end
	cycle_log_cd = cycle_log_cd - dtime
	if cycle_log_cd < 0 then cycle_log_cd = 0 end
	if core.settings:get_bool(SETTING_TOGGLE, false) then
		probe_tick(dtime)
	end

	-- ---- Taste 0: toggle the module on/off (edge detected) ----
	local key0 = core.is_key_down and core.is_key_down(HOTKEY_KEY_0) or false
	if key0 and not prev_key0 then
		local want = not core.settings:get_bool(SETTING_TOGGLE, false)
		core.settings:set_bool(SETTING_TOGGLE, want)
	end
	prev_key0 = key0

	local enabled = core.settings:get_bool(SETTING_TOGGLE, false)
	if enabled ~= prev_enabled then
		prev_enabled = enabled
		if not enabled then
			flush_input(cached_chest) -- silent: self-healing pull-back
			if core.settings:get_bool(SETTING_AUTOTAKE, false) and cycle_total > 0 then
				local ok, res = collect(cached_chest)
				say(ok and ("Auto-Collect: " .. res) or ("Auto-Collect failed: " .. res))
			end
			say("off (" .. cycle_total .. " cycles)")

			cycle_total = 0
			cycle_cd = 0
			cached_chest = nil
			double_probe = nil -- pause an in-flight probe with the module
			probe_label = nil
			last_state_msg = ""
		else
			cycle_total = 0
			cycle_cd = 0
			last_state_msg = ""
			if core.settings:get_bool(SETTING_HOLD, true) then
				if core.settings:get_bool(SETTING_LOG, true) then
					say("on - hold the middle mouse button to dupe"
						.. " (log on, diag file: " .. DIAG_FILE .. ")")
				else
					say("on - hold the middle mouse button to dupe (log off)")
				end
			else
				say("on - crosshair on the container, stack in hand (idle "
					.. "messages print once per state change)")
			end
		end
		return
	end
	if not enabled then return end

	-- ---- Hold-Mode: only run cycles while the middle mouse button is held ----
	if core.settings:get_bool(SETTING_HOLD, true) then
		if core.is_mouse_down and core.is_mouse_down(1) then
			-- active: fresh target each press-hold
		else
			cached_chest = nil
			last_state_msg = ""
			return
		end
	end

	-- ---- wielded stack: engine getter + cache across transient views ----
	-- Server sends TOCLIENT_INVENTORY mid-burst (showing the hand empty while
	-- the stack sits in the chest input). Once the cache holds the stack we
	-- never depend on the transient view again. On hotbar change the cache
	-- resets: cycles pause, the server quiesces in the "hand full" state, the
	-- next sync re-locks the new stack automatically.
	local idx = lp:get_wield_index()
	if idx ~= wield_idx_prev then
		wield_idx_prev = idx
		wield_name, wield_count = nil, nil
		wield_empty_time = 0
	end
	-- live-first every frame: the duped item always follows the hand, even
	-- when the item is swapped within the same hotbar slot. The cache only
	-- bridges the transient server syncs that show the hand empty mid-cycle.
	local ok, stack = pcall(lp.get_wielded_item, lp)
	if ok and stack and not stack:is_empty() then
		wield_name = stack:get_name()
		wield_count = stack:get_count()
		wield_empty_time = 0
	else
		wield_empty_time = wield_empty_time + dtime
		if wield_empty_time > 1.0 and wield_name then
			state_msg("wield:empty", "wielded slot is empty - stopped (rearm to continue)", true)
			wield_name, wield_count = nil, nil
		end
	end
	if not wield_name then
		state_msg("wield:none", "no stack in the wielded hotbar slot", true)
		return
	end

	-- ---- target chest ----
	local crosshair_only = core.settings:get(SETTING_MODE, "Auto") == "Crosshair only"
	local looked = look_chest()
	if looked and (not cached_chest
			or vector.distance(looked, cached_chest) > 0.5) then
		cached_chest = looked
		state_msg("target:" .. pos_string(looked),
			"target: " .. pos_string(looked))
	elseif not cached_chest and not crosshair_only then
		rescan_timer = rescan_timer - dtime
		if rescan_timer <= 0 then
			cached_chest = find_chest()
			rescan_timer = 1
		end
	elseif crosshair_only then
		cached_chest = looked -- no fallback: strictly what is looked at
	end

	if not cached_chest then
		-- silent (Hold-Mode) or once per state change
		if last_look_reason and last_look_reason ~= "nothing" then
			state_msg("nochest:" .. last_look_reason,
				last_look_reason .. " is not a dupe target - look at a chest "
				.. "(or a server-patched container)")
		else
			state_msg("nochest:none", "no dupe target in reach - look at a chest "
				.. "(or stand within " .. SCAN_RADIUS .. " blocks)")
		end
		return
	end

	-- ---- doubles / mod containers: dupe like small chests, verdict passive ----
	-- Cycling is NOT gated on a probe verdict (exact small-chest behavior).
	-- A passive probe measures the container whenever its view is synced;
	-- only a PROVEN-clearing server stops that container (physical limit:
	-- without the server mod, no client cycle can dupe it).
	local target_key = pos_string(cached_chest)
	local node_name = core.get_node_name(cached_chest) or ""
	local target_class = classify_node(node_name)
	local is_probed = target_class == "double"
	if is_probed then
		if probe_failed[target_key] then
			local cls_word = target_class == "double" and "double chest"
				or "container"
			state_msg("doublebad:" .. target_class, cls_word
				.. " proven unable on this server - aim at a single chest "
				.. "(or use Auto mode)", true)
			return
		end
		if not probe_okall[target_key] then
			if not double_hint_done[target_key] then
				double_hint_done[target_key] = true
				local fmt = probe_fmt[target_class]
				state_msg("doublehint:" .. target_class, fmt.hint, true)
				diag("probe start " .. target_class .. " " .. target_key
					.. " node=" .. node_name)
			end
			if double_probe == nil
					and not (probe_retry[target_key]
						and diag_t < probe_retry[target_key]) then
				local before = chest_count(cached_chest, wield_name)
				probe_label = target_class
				double_probe = {
					pos = cached_chest, item = wield_name,
					before = before, t = 0, noobs = (before == nil), tries = 0,
				}
				diag("probe passive " .. target_class .. " " .. target_key
					.. " synced=" .. tostring(before ~= nil))
			end
			-- NO return: cycling continues below, exactly like small chests
		end
	end

	-- ---- Auto-Drop: BEFORE the capacity guard ----
	-- The drop is what frees the container again, so it must run even when
	-- the (client-cached) view reports "full". The old placement AFTER the
	-- guard returned before reaching the drop: a full chest never drained --
	-- a permanent deadlock (dupe blocked, drop starved), and the "full"
	-- view only resyncs while a formspec is open. With Auto-Drop enabled
	-- the capacity guard therefore no longer stops the cycle either: a
	-- rejected move costs nothing, a stale "full" reading must not freeze
	-- the module.
	local autodrop_on = core.settings:get_bool(SETTING_AUTODROP, false)
	if autodrop_on then
		autodrop_cd = autodrop_cd - dtime
		if autodrop_cd <= 0 then
			autodrop_cd = AUTODROP_INTERVAL
			-- Rotate through the slots: dropping slot 0 over and over only
			-- empties the FIRST stack, then stalls (empty slot = server
			-- no-op) and a pre-filled chest stays full forever. One slot per
			-- frame, wrapping -- a full chest drains in one sweep, empty
			-- slots are free no-ops. Size comes from the client view when
			-- synced, else the chest_small default (27).
			local invn = nodemeta_inv_name(cached_chest)
			local inv = core.get_inventory(invn)
			local size = (inv and inv.main and #inv.main) or 27
			if size < 1 then size = 27 end
			core.drop_inventory_slot(invn, "main", autodrop_slot, 0)
			autodrop_slot = (autodrop_slot + 1) % size
		end
	end

	-- ---- container-main capacity guard (best effort; needs synced view) ----
	local free = chest_free_for(cached_chest, wield_name)
	if free == 0 and not autodrop_on then
		state_msg("full", "container main is full for " .. wield_name
			.. " - collect or use another container", true)
		return
	end
	if cycle_cd > 0 then return end
	cycle_cd = CYCLE_INTERVAL

	-- Guard: the dupe move pulls the stack from the wielded hotbar slot. If
	-- that slot does not hold the expected stack right now, the move would
	-- duplicate a DIFFERENT item (the local view can be out of sync between
	-- the three moves, and the server may have swapped the slot meanwhile).
	-- In that case: wait for the next sync instead of duping the wrong item.
	-- The stack in the hand is the only source of truth for WHAT gets
	-- duplicated. The client-side inventory view (inv.main) must NOT be used
	-- for that: on some servers (VoxeLibre) the client view and the server
	-- inventory are not in sync slot by slot (the view showed a different
	-- item than the one in the hand), which blocked the dupe completely.
	-- The MOVE itself uses the server slot (wield index + 1), which is
	-- correct -- only the read was wrong.
	local ok, live = pcall(lp.get_wielded_item, lp)
	if not ok or not live or live:is_empty() then
		state_msg("sync", "no stack in the wielded slot ("
			.. tostring(wield_name) .. ")")
		return
	end

	-- The move index is lp:get_wield_index() -- that is already the 1-based
	-- lua index of the wielded slot. The lua InventoryAction API is 1-based
	-- too and subtracts the 1 internally, so the value is passed unchanged.
	-- With an extra +1 the dupe took the stack BEHIND the one in the hand.
	dupe_cycle(cached_chest, idx, live:get_name(), live:get_count())
	cycle_total = cycle_total + 1
	-- (Auto-Drop moved above the capacity guard -- see there)
	-- per-frame cycles flood chat at 60/s; throttle the line to 4/s
	if core.settings:get_bool(SETTING_LOG, true) and cycle_log_cd <= 0 then
		cycle_log_cd = 0.25
		say("cycle " .. cycle_total .. ": +" .. (wield_count or 1)
			.. " " .. wield_name .. " -> " .. pos_string(cached_chest))
	end
end

core.register_globalstep(function(dtime)
	local ok, err = pcall(chest_dupe_step, dtime)
	if not ok then
		step_errors = step_errors + 1
		-- report the first few errors only, then stay quiet
		if step_errors <= 3 then
			say("[chest_dupe] step error: " .. tostring(err))
		end
	end
end)

-- --------------------------------------------------------------------------
-- Commands
-- --------------------------------------------------------------------------
-- --------------------------------------------------------------------------
-- Drop helpers: drop the whole content of the player inventory or of the
-- chest in reach. The engine API sends the drop actions to the server,
-- which validates them -- the client never needs to know the content.
-- --------------------------------------------------------------------------
minetest.register_chatcommand("dropinv", {
	description = "Drop the whole player inventory",
	func = function()
		core.drop_inventory_list("current_player", "main")
		return true, "player inventory dropped"
	end,
})

local function drop_chest_content()
	local pos = find_chest()
	if not pos then
		return false, "no chest within " .. SCAN_RADIUS .. " blocks"
	end
	core.drop_inventory_list("nodemeta:" .. pos.x .. "," .. pos.y .. ","
		.. pos.z, "main")
	return true, "chest content dropped"
end

minetest.register_chatcommand("dropchest", {
	description = "Drop the whole content of the chest in reach",
	func = drop_chest_content,
})

-- --------------------------------------------------------------------------
-- Tools window: two buttons to drop a whole inventory / chest content.
-- --------------------------------------------------------------------------
-- NOTE: the ext_tools CSM (which owned the ".tools" chat command and its
-- improvised formspec panel) was removed -- the native UI Utils panel
-- (engine side, key "L") replaced it. The drop actions themselves live
-- in the commands below (.dropinv / .dropchest) and in the native drop
-- buttons over open inventories.

minetest.register_chatcommand("chesttake", {
	params = "[x y z]",
	description = "Move all items from a single chest's main list into your inventory",
	func = function(param)
		local pos
		if param and param ~= "" then
			local p = param:split(" ")
			if #p >= 3 then
				pos = {
					x = tonumber(p[1]) or 0,
					y = tonumber(p[2]) or 0,
					z = tonumber(p[3]) or 0
				}
			end
		end
		if not pos then
			pos = find_chest()
		end
		if not pos then
			return false, "No chest within " .. SCAN_RADIUS ..
				" blocks (use '.chesttake x y z')."
		end
		local ok, res = collect(pos)
		return ok, res
	end,
})

-- Diagnostic (also covered by .nscan for listed nodes): prints the REAL node
-- names in range, so a renamed/unknown chest variant can be identified.
minetest.register_chatcommand("chestscan", {
	params = "[radius]",
	description = "List distinct node names within [radius] blocks (default 9) " ..
		"that contain 'chest', plus the 15 most common names overall",
	func = function(param)
		local lp = core.localplayer
		if not lp then return end
		local radius = tonumber(param) or 9
		if radius < 1 then radius = 1 elseif radius > 24 then radius = 24 end
		local lpos = lp:get_pos()
		local counts, matched, total = {}, {}, 0
		for x = -radius, radius do
		for y = -radius, radius do
		for z = -radius, radius do
			local name = core.get_node_name({
				x = math.floor(lpos.x + x),
				y = math.floor(lpos.y + y),
				z = math.floor(lpos.z + z),
			}) or "ignore"
			counts[name] = (counts[name] or 0) + 1
			total = total + 1
			if name:find("chest", 1, true) then
				matched[name] = (matched[name] or 0) + 1
			end
		end
		end
		end

		say(string.format("scan radius %d (%d positions):", radius, total))
		local any_match = false
		for name, n in pairs(matched) do
			any_match = true
			say("  chest-like: " .. name .. " x" .. n)
		end
		if not any_match then
			say("  nothing containing 'chest' found!")
		end
		local list = {}
		for name, c in pairs(counts) do
			table.insert(list, {name = name, count = c})
		end
		table.sort(list, function(a, b)
			if a.count ~= b.count then return a.count > b.count end
			return a.name < b.name
		end)
		for i = 1, math.min(15, #list) do
			say(string.format("  %-42sx%d", list[i].name, list[i].count))
		end
	end,
})

-- One-shot state dump for the wield/cache/chest chain (user pastes output).
minetest.register_chatcommand("chestlog", {
	description = "Print the last ChestDupe diag entries (in-memory buffer)",
	func = function()
		if #diag_buf == 0 then
			return false, "diag buffer empty - enable 'Log' and run cycles"
		end
		say(has_io and ("diag (last " .. DIAG_BUF_MAX .. " max, file: "
			.. DIAG_FILE .. "):") or "diag (last, NO io in sandbox):")
		local n = math.min(#diag_buf, 40)
		for i = #diag_buf - n + 1, #diag_buf do
			say("  " .. diag_buf[i])
		end
	end,
})

minetest.register_chatcommand("chestdbg", {
	description = "Print ChestDupe internal state (wield, cache, chest, settings)",
	func = function()
		local lp = core.localplayer
		if not lp then return false, "not ingame" end
		local idx = lp:get_wield_index()
		local ok, stack = pcall(lp.get_wielded_item, lp)
		local inv = player_inv()
		say("dbg: wield_idx=" .. tostring(idx)
			.. " wielded=" .. (ok and stack and not stack:is_empty()
				and (stack:get_name() .. " x" .. stack:get_count()) or "EMPTY")
			.. " cache=" .. (wield_name and (wield_name .. " x" .. tostring(wield_count)) or "nil"))
		local dlist = inv and inv.main
		if dlist then
			-- the lua list is 1-based, get_wield_index() returns the
			-- 1-based lua index already
			local at = dlist[idx]
			say("dbg: main #" .. tostring(#dlist) .. " slots, view at idx: "
				.. (at and not at:is_empty() and (at:get_name() .. " x" .. at:get_count())
					or "EMPTY"))
		else
			say("dbg: client inventory view not available")
		end
		say("dbg: chest=" .. (cached_chest and pos_string(cached_chest) or "nil")
			.. " cycles=" .. cycle_total)
		for _, key in ipairs({SETTING_TOGGLE, SETTING_AUTOTAKE, SETTING_LOG, SETTING_HOLD}) do
			say("dbg: " .. key .. "=" .. tostring(core.settings:get_bool(key, false)))
		end
		say("dbg: mode=" .. tostring(core.settings:get(SETTING_MODE, "Auto"))
			.. " key0=" .. tostring(core.is_key_down and core.is_key_down(HOTKEY_KEY_0))
			.. " mmb=" .. tostring(core.is_mouse_down and core.is_mouse_down(1)))
	end,
})
end

csm_main()
