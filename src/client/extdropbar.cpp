// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 ext fork contributors

#include "extdropbar.h"

#include "client/client.h"
#include "client/fontengine.h"
#include "gui/guiFormSpecMenu.h"
#include "gui/guiInventoryList.h"
#include "gui/mainmenumanager.h" // guienv, guiroot, g_menumgr
#include "gui/modalMenu.h" // GUIModalMenu
#include "inventorymanager.h"
#include "log.h"
#include "settings.h"

#include <IGUIElement.h>
#include <IGUIFont.h>
#include <IVideoDriver.h>
#include <IrrlichtDevice.h>

#include <algorithm>

namespace {

	// The player inventory as an inventory location string.
	const char *PLAYER_LOCATION = "current_player";
	const char *PLAYER_LIST = "main";

	// How many slots are moved/dropped at most (the client does not know the
	// real size of a foreign inventory -- the server ignores the empty ones).
	const s32 MAX_SLOTS = 32;

	// Finds every inventory list in the GUI tree (the container may be
	// rendered by any menu).
	void collect_inventory_lists(gui::IGUIElement *element,
			std::vector<GUIInventoryList *> &out)
	{
		if (!element)
			return;
		if (auto *list = dynamic_cast<GUIInventoryList *>(element)) {
			out.push_back(list);
			return;
		}
		for (gui::IGUIElement *child : element->getChildren())
			collect_inventory_lists(child, out);
	}

	// The lua-style location string of an inventory ("current_player",
	// "nodemeta:x,y,z", ...)
	std::string serialize_location(const InventoryLocation &loc)
	{
		switch (loc.type) {
		case InventoryLocation::CURRENT_PLAYER:
			return PLAYER_LOCATION;
		case InventoryLocation::PLAYER:
			return "player:" + loc.name;
		case InventoryLocation::NODEMETA:
			return "nodemeta:" + std::to_string(loc.p.X) + ","
				+ std::to_string(loc.p.Y) + "," + std::to_string(loc.p.Z);
		case InventoryLocation::DETACHED:
			return "detached:" + loc.name;
		default:
			return "";
		}
	}
} // namespace

bool extdropbar_handle_event(const SEvent &event)
{
	return ExtDropBar::get().handle_mouse_event(event);
}

ExtDropBar &ExtDropBar::get()
{
	static ExtDropBar instance;
	return instance;
}

void ExtDropBar::update(Client *client, bool sneak)
{
	m_client = client;
	m_sneak = sneak;

	// Find every inventory list that is currently on screen. The search runs
	// over the GUI tree, so it works no matter which menu renders the
	// container.
	std::vector<GUIInventoryList *> lists;
	collect_inventory_lists(guienv->getRootGUIElement(), lists);
	// The chest (a foreign inventory) and the player inventory.
	bool have_chest = false, have_player = false;
	InventoryLocation chest_loc, player_loc;
	std::string chest_list, player_list;
	for (GUIInventoryList *list : lists) {
		if (!list)
			continue;
		const InventoryLocation &loc = list->getInventoryloc();
		if (loc.type == InventoryLocation::UNDEFINED)
			continue;
		const bool is_player = (loc.type == InventoryLocation::CURRENT_PLAYER);
		if (is_player) {
			if (!have_player) {
				have_player = true;
				player_loc = loc;
				player_list = list->getListname();
			}
		} else if (!have_chest) {
			have_chest = true;
			chest_loc = loc;
			chest_list = list->getListname();
		}
	}

	// Nothing open -> no buttons
	if (!have_chest && !have_player) {
		m_buttons.clear();
		m_active = false;
		return;
	}

	// Which buttons? The chest gets its own actions, the player inventory
	// gets the drop actions (the offhand is a separate list and is never
	// touched).
	struct Action {
		const wchar_t *label;
		ActionKind kind;
		std::string location;
		std::string listname;
	};
	std::vector<Action> actions;
	if (have_chest) {
		actions.push_back({L"Drop chest", ACTION_DROP,
				serialize_location(chest_loc), chest_list});
		actions.push_back({L"Bump", ACTION_TO_CHEST,
				serialize_location(chest_loc), chest_list});
		actions.push_back({L"Steal", ACTION_FROM_CHEST,
				serialize_location(chest_loc), chest_list});
	}
	if (have_player) {
		actions.push_back({L"Drop all", ACTION_DROP,
				serialize_location(player_loc), player_list});
		actions.push_back({L"Drop main", ACTION_DROP_MAIN,
				serialize_location(player_loc), player_list});
	}

	// The window the buttons belong to
	gui::IGUIElement *host = nullptr;
	if (GUIModalMenu *menu = g_menumgr.tryGetTopMenu())
		host = menu;
	if (!host)
		host = guiroot;
	const core::rect<s32> host_rect = host->getAbsolutePosition();

	// Position: right next to the window, so the chest slots stay visible.
	const s32 btn_w = std::clamp<s32>(host_rect.getWidth() / 4, 110, 260);
	const s32 btn_h = 34;
	const s32 gap = 6;
	const s32 x = host_rect.LowerRightCorner.X + 10;

	m_buttons.clear();
	s32 y = host_rect.UpperLeftCorner.Y;
	for (const Action &a : actions) {
		Button b;
		b.label = a.label;
		b.kind = a.kind;
		b.location = a.location;
		b.listname = a.listname;
		b.rect = core::rect<s32>(x, y, x + btn_w, y + btn_h);
		m_buttons.push_back(b);
		y += btn_h + gap;
	}
	m_active = true;
}

void ExtDropBar::draw(video::IVideoDriver *driver, gui::IGUIFont *font)
{
	if (!m_active || !driver || !font)
		return;

	const video::SColor bg(255, 40, 44, 52);
	const video::SColor bg_hover(255, 70, 90, 120);
	const video::SColor text_col(255, 235, 238, 245);

	for (Button &b : m_buttons) {
		const bool hovered = b.hovered;
		driver->draw2DRectangle(hovered ? bg_hover : bg, b.rect);
		core::dimension2d<u32> dim = font->getDimension(b.label);
		const core::position2d<s32> pos(
				b.rect.getCenter().X - (s32)dim.Width / 2,
				b.rect.getCenter().Y - (s32)dim.Height / 2);
		font->draw(b.label, core::rect<s32>(pos.X, pos.Y,
				pos.X + (s32)dim.Width, pos.Y + (s32)dim.Height), text_col);
	}
}

bool ExtDropBar::handle_click(s32 x, s32 y)
{
	if (!m_active)
		return false;
	const core::position2d<s32> click(x, y);
	for (Button &b : m_buttons) {
		if (!b.rect.isPointInside(click))
			continue;
		warningstream << "[ExtPanel] drop bar: Aktion " << (int)b.kind
			<< " auf " << b.location << "/" << b.listname << std::endl;
		do_action(b.kind, b.location, b.listname);
		return true;
	}
	return false;
}

bool ExtDropBar::handle_mouse_event(const SEvent &event)
{
	if (event.EventType != EET_MOUSE_INPUT_EVENT)
		return false;
	if (!m_active)
		return false;

	switch (event.MouseInput.Event) {
	case EMIE_LMOUSE_PRESSED_DOWN:
	case EMIE_LMOUSE_DOUBLE_CLICK: {
		const core::position2d<s32> pos(event.MouseInput.X, event.MouseInput.Y);
		update_hover(pos.X, pos.Y);
		if (!handle_click(pos.X, pos.Y))
			return false;
		// The release belongs to the button as well -- it must not reach
		// the menu, or the window would close.
		m_captured = true;
		return true;
	}
	case EMIE_LMOUSE_LEFT_UP:
		if (m_captured) {
			m_captured = false;
			return true;
		}
		return false;
	case EMIE_MOUSE_MOVED:
		update_hover(event.MouseInput.X, event.MouseInput.Y);
		return m_captured;
	default:
		return false;
	}
}

void ExtDropBar::update_hover(s32 x, s32 y)
{
	if (!m_active)
		return;
	const core::position2d<s32> pos(x, y);
	for (Button &b : m_buttons)
		b.hovered = b.rect.isPointInside(pos);
}

core::position2d<s32> ExtDropBar::get_button_center(int index) const
{
	if (index < 0 || index >= (int)m_buttons.size())
		return core::position2d<s32>(-1, -1);
	return m_buttons[index].rect.getCenter();
}

bool ExtDropBar::simulate_click(int index)
{
	if (m_buttons.empty() || index < 0 || index >= (int)m_buttons.size()) {
		warningstream << "[ExtPanel] drop bar: kein Button zum Klicken"
			<< std::endl;
		return false;
	}
	const core::rect<s32> r = m_buttons[index].rect;
	const core::position2d<s32> c = r.getCenter();
	warningstream << "[ExtPanel] drop bar: Klick gesendet an "
		<< c.X << "," << c.Y << std::endl;
	return handle_click(c.X, c.Y);
}

void ExtDropBar::do_action(ActionKind kind, const std::string &location,
		const std::string &listname)
{
	Client *client = m_client;
	if (!client)
		return;

	InventoryLocation loc;
	loc.deSerialize(location);

	if (kind == ACTION_DROP || kind == ACTION_DROP_MAIN) {
		// Drop everything: one drop action per slot, the server ignores the
		// empty ones. ACTION_DROP_MAIN skips the hotbar (slots 0-8).
		// The offhand is a separate list and is never touched.
		const s32 first = (kind == ACTION_DROP_MAIN) ? 9 : 0;
		for (s32 i = first; i < MAX_SLOTS; i++) {
			IDropAction *a = new IDropAction();
			a->count = m_sneak ? 1 : 0; // 0 = everything in that slot
			a->from_inv = loc;
			a->from_list = listname;
			a->from_i = i;
			client->inventoryAction(a);
		}
		return;
	}

	// Moves: the whole content of one inventory into the other one.
	// The client does not need to know the content -- the server validates
	// every move and ignores the empty slots.
	InventoryLocation player;
	player.setCurrentPlayer();
	const bool to_chest = (kind == ACTION_TO_CHEST);

	for (s32 i = 0; i < MAX_SLOTS; i++) {
		IMoveAction *a = new IMoveAction();
		// count >= stack size moves the WHOLE stack: the engine only
		// clamps with `if (count > 0 && count < src_item.count)`, so any
		// value above the largest stack (64) means "everything". count = 1
		// would move ONE item per slot, count = 0 would move nothing (the
		// move_somewhere loop stops at count == 0). One click = all items,
		// same as Auto-Collect -- the server cuts the move at the free
		// space of the target stacks and ignores empty slots.
		a->count = 65535; // u16 max
		// move_somewhere: the server looks for a free slot itself. With a
		// fixed target slot every move is rejected as soon as that slot
		// holds another item.
		a->move_somewhere = true;
		if (to_chest) {
			a->from_inv = player;
			a->from_list = PLAYER_LIST;
			a->from_i = i;
			a->to_inv = loc;
			a->to_list = listname;
		} else {
			a->from_inv = loc;
			a->from_list = listname;
			a->from_i = i;
			a->to_inv = player;
			a->to_list = PLAYER_LIST;
		}
		client->inventoryAction(a);
	}
}
