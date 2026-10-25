// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 ext fork contributors

// ExtPanel: native in-game settings panel for the ext fork modules
// (XRay, Fullbright, No-Night, ChestDupe). Plain standard widgets,
// opened via the `ext_menu.open` setting (set by the ext_menu client mod
// on the .menu chat command).
// The panel is a GUIModalMenu (same plumbing as the pause menu / chat
// console / formspecs): the engine routes mouse+keyboard events to it,
// freezes game input and shows the cursor while it is open, and the world
// keeps running because pausesGame() is false.

#pragma once

#include "irrlichttypes.h"
#include <IGUIEnvironment.h>
#include "irr_ptr.h"
#include <string>
#include <vector>

namespace gui {
	class IGUIElement;
	class IGUIButton;
	class IGUICheckBox;
	class IGUIEditBox;
}
class ExtPanelMenu;

class ExtPanel {
public:
	static ExtPanel &get();
	// Opens (creates the modal menu and builds widgets from settings).
	void open();
	// Closes. write_setting=false must be used from caller paths that were
	// triggered by ext_menu.open changing to false itself (avoids write loop).
	void close(bool write_setting);
	// True while the panel is open and attached to the GUI.
	bool is_open() const;
	// Runs the runtime self check (widgets inside the panel and hit-testable)
	// and returns the number of problems found.
	int run_self_check();
	// Automated smoke test: clicks through the panel (toggle, subpage, Esc)
	// and verifies that everything reacts. Returns the number of problems.
	int run_self_test();

private:
	friend class ExtPanelMenu;
	irr_ptr<ExtPanelMenu> m_menu;
	std::string m_page = "main";
	// widgets of the current page
	gui::IGUIButton *m_btn_main[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
	gui::IGUIButton *m_btn_settings[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
	gui::IGUIEditBox *m_edt_xray = nullptr;
	gui::IGUIButton *m_btn_mode[2] = {nullptr, nullptr};
	gui::IGUICheckBox *m_cb_chest[4] = {nullptr, nullptr, nullptr, nullptr};
	// all interactive widgets of the current page (for the self check)
	std::vector<gui::IGUIElement *> m_widgets;
	// static texts (labels/descriptions) of the current page
	std::vector<gui::IGUIElement *> m_texts;

	void build_main();
	void build_xray();
	void build_chestdupe();
	void clear_widgets();

	// Rebuilds the current page (clears and recreates the widgets).
	void rebuild();
	// Writes the XRay node list from the edit box into the setting.
	void apply_xray_nodes();
	// Synthesizes a left click at the center of the widget.
	bool click_widget(gui::IGUIElement *widget);
	// Synthesizes an Esc key press (the modal menu closes itself).
	bool simulate_escape();

};
