// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 ext fork contributors

// ExtDropBar: buttons next to an open inventory.
//
// While a window with an inventory is open (a chest, the player
// inventory), a column of buttons appears next to it:
//   Drop all    -- the whole player inventory falls on the ground
//                  (the offhand is a separate list and is never touched)
//   Drop main   -- only the main inventory rows (no hotbar)
//   Drop chest  -- the whole chest content falls on the ground
//   Bump        -- the whole player inventory goes into the chest
//   Steal       -- the whole chest content comes into the player inventory
//
// The buttons are drawn and hit-tested by the form spec itself (like the
// UI Utils panel): a GUI button would never receive the click,
// because the open form spec consumes the mouse event before the GUI
// elements see it.

#pragma once

#include "irrlichttypes.h"
#include "IEventReceiver.h"
#include <IGUIEnvironment.h>
#include "irr_ptr.h"
#include <string>
#include <vector>

namespace gui {
	class IGUIElement;
	class IGUIFont;
}
class Client;
class GUIInventoryList;

enum ActionKind {
	ACTION_DROP,        // drop the whole inventory list
	ACTION_DROP_MAIN,   // drop only the main inventory rows (no hotbar)
	ACTION_TO_CHEST,    // move the player inventory into the chest
	ACTION_FROM_CHEST,  // move the chest content into the player inventory
};

// Free function for the input handler (like uiutils_handle_event).
bool extdropbar_handle_event(const SEvent &event);

class ExtDropBar {
public:
	static ExtDropBar &get();

	// Collects the open inventories and rebuilds the button list.
	void update(Client *client, bool sneak);

	// Draws the buttons (called in the overlay pass, next to the UI Utils
	// panel).
	void draw(video::IVideoDriver *driver, gui::IGUIFont *font);

	// Hit test for a mouse click.
	bool handle_click(s32 x, s32 y);

	// Consumes the mouse events that belong to the buttons. Must be called
	// BEFORE the menu gets the event: a click outside the window is turned
	// into a synthetic ESC by GUIModalMenu::remapClickOutside and would close
	// the open window.
	bool handle_mouse_event(const SEvent &event);

	// Updates the hover state (for the drawing).
	void update_hover(s32 x, s32 y);

	// Test helper: clicks the first button as if the mouse had clicked it.
	bool simulate_click(int index = 0);

	// The middle of a button (test helper).
	core::position2d<s32> get_button_center(int index) const;
	// Performs one of the actions.
	void do_action(ActionKind kind, const std::string &location,
			const std::string &listname);

private:
	struct Button {
		const wchar_t *label = nullptr;
		ActionKind kind = ACTION_DROP;
		std::string location;
		std::string listname;
		core::rect<s32> rect;
		bool hovered = false;
	};

	std::vector<Button> m_buttons;
	Client *m_client = nullptr;
	bool m_sneak = false;
	bool m_active = false;
	bool m_captured = false;
};
