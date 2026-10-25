// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 ext fork contributors

#include "extpanel.h"

#include "settings.h"
#include "log.h"
#include "irr_ptr.h"
#include "util/string.h"
#include "client/fontengine.h"

#include <IVideoDriver.h>
#include <IGUIButton.h>
#include <IGUICheckBox.h>
#include <IGUIEditBox.h>
#include <IGUIStaticText.h>

#include "gui/mainmenumanager.h" // guienv, guiroot, g_menumgr

#include <algorithm>
#include <vector>

namespace {

	enum EPanelIDs {
		EP_CLOSE = 3001,
		EP_ID_BASE = 1000,        // main toggle button for row i: base+i
		EP_SETTINGS_BASE = 2000,  // "Settings..." button for row i: base+i
		EP_BACK = 4001,
		EP_XRAY_EDIT = 5000,
		EP_XRAY_APPLY = 5001,
		EP_CHESTD_MODE_AUTO = 5002,
		EP_CHESTD_MODE_CROSS = 5003,
		EP_CHESTD_CHECK_BASE = 6000,
	};

	struct MainRow {
		const char *label;
		const char *desc;
		const char *key;   // setting key that toggles the feature
		const char *page;  // subpage id, "" = none
	};

	// NOTE: the keys must stay in sync with the implementations that read
	// them: the engine (mapblock_mesh.cpp: xray, fullbright, no_night) and
	// the chest_dupe client mod (chest_dupe, chest_dupe.mode, ...).
	// The test clientmods-ext/ext_menu/tests/ext_keys_consistency.lua
	// enforces this across panel, bridge and mod.
	const MainRow MAIN_ROWS[6] = {
		// clang-format off
		{"XRay",        "See through blocks to show ores.",    "xray",        "xray"},
		{"Fullbright",  "Makes the whole world fully bright.", "fullbright",  ""},
		{"No-Night",    "Stops day/night from changing.",      "no_night",    ""},
		{"ChestDupe",   "Chest-crosshair dupe automation.",    "chest_dupe",  "chest_dupe"},
		{"FreeCam",     "Fly the camera freely (key F4).",     "freecam",     ""},
		{"AutoTotem",   "Puts a totem in your offhand.",        "autototem",    ""},
		// clang-format on
	};

	struct CheckboxRow {
		const char *label;
		const char *key;
		bool def;
	};

	const CheckboxRow CHESTD_CHECKS[4] = {
		// Use the existing client setting-registration convention.
		// clang-format off
		{"Auto-Collect", "chest_dupe.autotake",  false},
		{"Auto-Drop",     "chest_dupe.autodrop",  false},
		{"Log",          "chest_dupe.log",       true},
		{"Hold-Mode",    "chest_dupe.hold_mode", true},
		// clang-format on
	};

	// number of checkbox rows on the ChestDupe page -- the render loop, the
	// event bound and the row layout must ALL use this (a hardcoded 3 hid
	// the last row, Hold-Mode, from the UI)
	constexpr s32 CHESTD_CHECK_COUNT =
			(s32)(sizeof(CHESTD_CHECKS) / sizeof(CHESTD_CHECKS[0]));

	inline std::wstring w(const char *s) { return utf8_to_wide(s); }

	// thin horizontal separator line (non-interactive)
	inline void add_sep(gui::IGUIEnvironment *env, gui::IGUIElement *parent,
			const core::rect<s32> &rect) {
		auto *sep = env->addStaticText(L"", rect, false, false,
				parent, 0, false);
		sep->setDrawBackground(true);
		sep->setBackgroundColor(video::SColor(255, 64, 74, 94));
	}

	// Cheat toggles are optional settings: they only exist after they were
	// written once. The NoThrow getters return the default instead of
	// throwing a SettingNotFoundException.
	inline bool read_bool(const std::string &key, bool def) {
		return g_settings->getBoolNoThrow(key, def);
	}

	inline std::string read_str(const std::string &key, const char *def) {
		return g_settings->getNoThrow(key, def);
	}
}

// ---------------------------------------------------------------------------
// ExtPanelMenu: modal menu root
// ---------------------------------------------------------------------------

class ExtPanelMenu : public GUIModalMenu {
public:
	ExtPanelMenu(gui::IGUIEnvironment *env, gui::IGUIElement *parent,
			IMenuManager *menumgr) :
			GUIModalMenu(env, parent, -1, menumgr)
	{
	}

	// The modal element itself must cover the whole screen: its children are
	// positioned in screen coordinates and would otherwise be clipped away by
	// the default 100x100 rect of GUIModalMenu.
	void layout(const core::rect<s32> &screen)
	{
		DesiredRect = screen;
		recalculateAbsolutePosition(false);
	}

	// Called by GUIModalMenu::draw() when the screen size changed.
	void regenerateGui(v2u32 screensize) override
	{
		core::rect<s32> screen(core::position2d<s32>(0, 0),
				core::dimension2d<s32>((s32)screensize.X, (s32)screensize.Y));
		layout(screen);
		ExtPanel::get().rebuild();
	}

	void drawMenu() override
	{
		video::IVideoDriver *driver = Environment->getVideoDriver();
		if (!driver)
			return;
		core::rect<s32> screen(core::position2d<s32>(0, 0),
				driver->getScreenSize());
		driver->draw2DRectangle(video::SColor(110, 0, 0, 0), screen, nullptr);
		driver->draw2DRectangle(video::SColor(245, 18, 22, 30),
				m_panel_rect, nullptr);
		gui::IGUIElement::draw();
	}

	std::wstring getLabelByID(s32 id) override { return L""; }
	std::string getNameByID(s32 id) override { return ""; }

	core::rect<s32> m_panel_rect;

private:
	void handleBack()
	{
		ExtPanel &p = ExtPanel::get();
		p.m_page = "main";
		p.rebuild();
	}

	bool handleGuiEvent(const SEvent &event)
	{
		gui::IGUIElement *caller = event.GUIEvent.Caller;
		const s32 id = caller ? caller->getID() : -1;
		ExtPanel &p = ExtPanel::get();

		// The rebuild below removes the widget that is currently dispatching
		// the event. Hold a reference to it, so it is not destroyed while its
		// own event handler is still running.
		irr_ptr<gui::IGUIElement> caller_holder;
		if (caller)
			caller_holder.grab(caller);

		switch (event.GUIEvent.EventType) {
		case gui::EGET_BUTTON_CLICKED: {
			if (id == EP_CLOSE) {
				p.close(true);
				return true;
			}
			if (id == EP_BACK) {
				handleBack();
				return true;
			}
			if (id >= EP_SETTINGS_BASE && id < EP_SETTINGS_BASE + 6) {
				const MainRow &row = MAIN_ROWS[id - EP_SETTINGS_BASE];
				if (row.page && *row.page) {
					p.m_page = row.page;
					p.rebuild();
				}
				return true;
			}
			if (id == EP_XRAY_APPLY) {
				p.apply_xray_nodes();
				return true;
			}
			if (id == EP_CHESTD_MODE_AUTO || id == EP_CHESTD_MODE_CROSS) {
				g_settings->set("chest_dupe.mode",
						id == EP_CHESTD_MODE_AUTO ? "Auto" : "Crosshair only");
				infostream << "[ExtPanel] chest_dupe.mode set" << std::endl;
				p.rebuild(); // rebuild immediately: the switch has to be visible
				return true;
			}
			if (id >= EP_ID_BASE && id < EP_ID_BASE + 6) {
				const MainRow &row = MAIN_ROWS[id - EP_ID_BASE];
				bool newval = !read_bool(row.key, false);
				g_settings->setBool(row.key, newval);
				infostream << "[ExtPanel] toggle " << row.key
					<< " -> " << (newval ? "on" : "off") << std::endl;
				if (p.m_btn_main[id - EP_ID_BASE])
					p.m_btn_main[id - EP_ID_BASE]->setText(
							newval ? L"On" : L"Off");
				return true;
			}
			break;
		}
		case gui::EGET_EDITBOX_ENTER: {
			if (id == EP_XRAY_EDIT) {
				p.apply_xray_nodes();
				return true;
			}
			break;
		}
		case gui::EGET_CHECKBOX_CHANGED: {
			if (id >= EP_CHESTD_CHECK_BASE &&
					id < EP_CHESTD_CHECK_BASE + CHESTD_CHECK_COUNT) {
				auto *box = static_cast<gui::IGUICheckBox *>(caller);
				const CheckboxRow &row =
						CHESTD_CHECKS[id - EP_CHESTD_CHECK_BASE];
				g_settings->setBool(row.key, box->isChecked());
				infostream << "[ExtPanel] checkbox " << row.key
					<< " -> " << (box->isChecked() ? "on" : "off")
					<< std::endl;
			}
			return true;
		}
		default:
			break;
		}
		return gui::IGUIElement::OnEvent(event);
	}

	// Esc has to be caught here: after a click the focus sits on a widget
	// (button, checkbox, editbox), and the environment only sends key events
	// to the focused element -- the panel would not see the key any more.
	bool preprocessEvent(const SEvent &event) override
	{
		// close() releases the last reference of this menu, so hold one until
		// the call is done
		irr_ptr<ExtPanelMenu> holder;
		holder.grab(this);

		if (event.EventType == EET_KEY_INPUT_EVENT &&
				event.KeyInput.PressedDown &&
				event.KeyInput.Key == KEY_ESCAPE) {
			ExtPanel::get().close(true);
			return true;
		}
		return GUIModalMenu::preprocessEvent(event);
	}

	bool OnEvent(const SEvent &event) override
	{
		irr_ptr<ExtPanelMenu> holder;
		holder.grab(this); // quitMenu() during this call is safe

		if (event.EventType == EET_KEY_INPUT_EVENT &&
				event.KeyInput.PressedDown &&
				event.KeyInput.Key == KEY_ESCAPE) {
			ExtPanel::get().close(true);
			return true;
		}

		if (event.EventType == EET_GUI_EVENT)
			return handleGuiEvent(event);

		return gui::IGUIElement::OnEvent(event);
	}
};

// ---------------------------------------------------------------------------
// ExtPanel
// ---------------------------------------------------------------------------

ExtPanel &ExtPanel::get()
{
	static ExtPanel singleton;
	return singleton;
}

bool ExtPanel::is_open() const
{
	// A menu that got detached from the GUI (e.g. on shutdown) is not open
	// anymore, even though the pointer is still alive.
	return m_menu.get() != nullptr && m_menu->getParent() != nullptr;
}

void ExtPanel::clear_widgets()
{
	for (auto *&h : m_btn_main)
		h = nullptr;
	for (auto *&h : m_btn_settings)
		h = nullptr;
	for (auto *&h : m_btn_mode)
		h = nullptr;
	for (auto *&h : m_cb_chest)
		h = nullptr;
	m_edt_xray = nullptr;
	m_widgets.clear();
	m_texts.clear();
	if (!m_menu)
		return;
	// copy first, then remove (removal mutates the list we iterate)
	gui::IGUIElement *root = m_menu.get();
	std::vector<gui::IGUIElement *> children;
	for (gui::IGUIElement *child : root->getChildren())
		children.push_back(child);
	for (gui::IGUIElement *child : children)
		child->remove();
}

void ExtPanel::close(bool write_setting)
{
	// tear the menu down first; the ext_menu.open write below then finds
	// is_open() == false and becomes a no-op (no settings callback loop)
	if (!m_menu) {
		if (write_setting)
			g_settings->setBool("ext_menu.open", false);
		return;
	}
	m_page = "main";
	// extra reference so quitMenu() inside click handlers does not delete us
	irr_ptr<ExtPanelMenu> holder;
	holder.grab(m_menu.get());
	m_menu->quitMenu();
	clear_widgets();
	m_menu.reset();
	if (write_setting)
		g_settings->setBool("ext_menu.open", false);
	warningstream << "[ExtPanel] close" << std::endl;
}

void ExtPanel::open()
{
	if (is_open() || !guienv || !guiroot)
		return;
	// stale menu from a previous session (e.g. after a reconnect):
	// unregister it properly instead of leaking it in the menu manager
	if (m_menu) {
		irr_ptr<ExtPanelMenu> holder;
		holder.grab(m_menu.get());
		m_menu->quitMenu();
		m_menu.reset();
	}
	m_menu.reset(new ExtPanelMenu(guienv, guiroot, &g_menumgr));
	m_page = "main";
	rebuild();
	warningstream << "[ExtPanel] open page=" << m_page << std::endl;
}

void ExtPanel::rebuild()
{
	if (!m_menu)
		return;
	const core::rect<s32> screen(core::position2d<s32>(0, 0),
			guienv->getRootGUIElement()->getAbsoluteClippingRect().getSize());
	m_menu->layout(screen);
	clear_widgets();
	if (m_page == "xray")
		build_xray();
	else if (m_page == "chest_dupe")
		build_chestdupe();
	else
		build_main();

	// The rebuild removed the widget that had the keyboard focus. Without
	// this the menu would no longer receive key events and Esc would stop
	// closing the panel.
	guienv->setFocus(m_menu.get());
}

int ExtPanel::run_self_check()
{
	if (!m_menu || m_widgets.empty())
		return 0;
	const core::rect<s32> &panel = m_menu->m_panel_rect;
	s32 outside = 0, unclickable = 0;
	for (gui::IGUIElement *w : m_widgets) {
		if (!w)
			continue;
		const core::rect<s32> r = w->getAbsolutePosition();
		if (!panel.isPointInside(r.UpperLeftCorner) ||
				!panel.isPointInside(r.LowerRightCorner)) {
			outside++;
			warningstream << "[ExtPanel] SELFCHECK widget outside panel id="
				<< w->getID() << " rect=" << r.LowerRightCorner.X << ","
				<< r.LowerRightCorner.Y << std::endl;
			continue;
		}
		// hit test: the widget (or a descendant of it) must be found
		gui::IGUIElement *hit = guienv->getRootGUIElement()
				->getElementFromPoint(r.getCenter());
		bool found = false;
		for (gui::IGUIElement *e = hit; e; e = e->getParent()) {
			if (e == w) {
				found = true;
				break;
			}
		}
		if (!found) {
			unclickable++;
			warningstream << "[ExtPanel] SELFCHECK widget not clickable id="
				<< w->getID() << std::endl;
		}
	}
	// overlapping widgets/texts (e.g. a description running into the next
	// row) would still be clickable, so they are checked separately
	s32 overlapping = 0;
	auto overlaps = [](const core::rect<s32> &a, const core::rect<s32> &b) {
		return a.UpperLeftCorner.X < b.LowerRightCorner.X &&
				b.UpperLeftCorner.X < a.LowerRightCorner.X &&
				a.UpperLeftCorner.Y < b.LowerRightCorner.Y &&
				b.UpperLeftCorner.Y < a.LowerRightCorner.Y;
	};
	for (size_t i = 0; i < m_widgets.size(); i++) {
		if (!m_widgets[i])
			continue;
		const core::rect<s32> a = m_widgets[i]->getAbsolutePosition();
		for (size_t j = i + 1; j < m_widgets.size(); j++) {
			if (!m_widgets[j])
				continue;
			if (overlaps(a, m_widgets[j]->getAbsolutePosition())) {
				overlapping++;
				warningstream << "[ExtPanel] SELFCHECK widgets overlap id="
					<< m_widgets[i]->getID() << " / " << m_widgets[j]->getID()
					<< std::endl;
			}
		}
		for (gui::IGUIElement *t : m_texts) {
			if (!t)
				continue;
			if (overlaps(a, t->getAbsolutePosition())) {
				overlapping++;
				warningstream << "[ExtPanel] SELFCHECK widget overlaps text id="
					<< m_widgets[i]->getID() << std::endl;
			}
		}
	}
	for (size_t i = 0; i < m_texts.size(); i++) {
		if (!m_texts[i])
			continue;
		const core::rect<s32> a = m_texts[i]->getAbsolutePosition();
		for (size_t j = i + 1; j < m_texts.size(); j++) {
			if (!m_texts[j])
				continue;
			if (overlaps(a, m_texts[j]->getAbsolutePosition())) {
				overlapping++;
				warningstream << "[ExtPanel] SELFCHECK texts overlap" << std::endl;
			}
		}
	}

	warningstream << "[ExtPanel] SELFCHECK " << m_widgets.size()
		<< " widgets, " << outside << " outside panel, " << unclickable
		<< " not clickable, " << overlapping << " overlapping"
		<< " | panel=" << panel.LowerRightCorner.X << "x"
		<< panel.LowerRightCorner.Y << " u=" << g_fontengine->getTextHeight()
		<< std::endl;
	return outside + unclickable + overlapping;
}

bool ExtPanel::click_widget(gui::IGUIElement *widget)
{
	if (!widget || !guienv)
		return false;
	const core::position2d<s32> c = widget->getAbsolutePosition().getCenter();
	SEvent ev{};
	ev.EventType = EET_MOUSE_INPUT_EVENT;
	ev.MouseInput.X = c.X;
	ev.MouseInput.Y = c.Y;
	ev.MouseInput.Button = SDL_BUTTON_LEFT;
	ev.MouseInput.Shift = false;
	ev.MouseInput.Control = false;
	ev.MouseInput.Simulated = false;
	ev.MouseInput.Event = EMIE_LMOUSE_PRESSED_DOWN;
	ev.MouseInput.ButtonStates = SDL_BUTTON_MASK(SDL_BUTTON_LEFT);
	guienv->postEventFromUser(ev);
	ev.MouseInput.Event = EMIE_LMOUSE_LEFT_UP;
	ev.MouseInput.ButtonStates = 0;
	guienv->postEventFromUser(ev);
	return true;
}

bool ExtPanel::simulate_escape()
{
	if (!guienv)
		return false;
	SEvent ev{};
	ev.EventType = EET_KEY_INPUT_EVENT;
	ev.KeyInput.Key = KEY_ESCAPE;
	ev.KeyInput.PressedDown = true;
	ev.KeyInput.Char = 0;
	guienv->postEventFromUser(ev);
	return true;
}

int ExtPanel::run_self_test()
{
	int problems = 0;
	auto fail = [&](const char *what) {
		problems++;
		warningstream << "[ExtPanel] SELFTEST " << what << std::endl;
	};

	// 1) main page: all widgets must be clickable
	problems += run_self_check();

	// 2) a click on a toggle must flip the setting (and be reversible)
	const bool xray_before = read_bool("xray", false);
	if (m_btn_main[0]) {
		click_widget(m_btn_main[0]);
		if (read_bool("xray", false) == xray_before)
			fail("click on toggle had no effect");
		click_widget(m_btn_main[0]);
		if (read_bool("xray", false) != xray_before)
			fail("toggle did not revert");
	} else {
		fail("no toggle button");
	}

	// the FreeCam row (last row) must toggle its setting as well
	if (m_btn_main[4]) {
		const bool fc_before = read_bool("freecam", false);
		click_widget(m_btn_main[4]);
		if (read_bool("freecam", false) == fc_before)
			fail("freecam toggle had no effect");
		click_widget(m_btn_main[4]);
		if (read_bool("freecam", false) != fc_before)
			fail("freecam toggle did not revert");
	} else {
		fail("no freecam toggle button");
	}

	// 3) "Settings..." must open the XRay subpage
	if (m_btn_settings[0]) {
		click_widget(m_btn_settings[0]);
		if (m_page != "xray")
			fail("XRay subpage not opened");
		else
			problems += run_self_check();
	} else {
		fail("no settings button");
	}

	// 4) the XRay node list must be writable
	if (m_edt_xray) {
		const std::string nodes_before = read_str("xray.nodes", "");
		const std::string test_nodes = "default:stone,basenodes:dirt";
		m_edt_xray->setText(utf8_to_wide(test_nodes).c_str());
		// the Apply button is the last widget of the page
		gui::IGUIElement *apply_btn = nullptr;
		for (gui::IGUIElement *w : m_widgets)
			if (w && w->getID() == EP_XRAY_APPLY)
				apply_btn = w;
		if (apply_btn) {
			click_widget(apply_btn);
			if (read_str("xray.nodes", "") != test_nodes)
				fail("xray.nodes was not written");
			// restore
			g_settings->set("xray.nodes", nodes_before);
		} else {
			fail("no apply button");
		}
	} else {
		fail("no xray edit box");
	}

	// 5) Back must return to the main page
	{
		gui::IGUIElement *back = nullptr;
		for (gui::IGUIElement *w : m_widgets)
			if (w && w->getID() == EP_BACK)
				back = w;
		if (back) {
			click_widget(back);
			if (m_page != "main")
				fail("back did not return to the main page");
		} else {
			fail("no back button");
		}
	}

	// 6) the ChestDupe subpage and its options
	if (m_btn_settings[3]) {
		click_widget(m_btn_settings[3]);
		if (m_page != "chest_dupe")
			fail("ChestDupe subpage not opened");
		else
			problems += run_self_check();
	} else {
		fail("no chestdupe settings button");
	}

	if (m_cb_chest[0]) {
		const bool before = read_bool("chest_dupe.autotake", false);
		click_widget(m_cb_chest[0]);
		if (read_bool("chest_dupe.autotake", false) == before)
			fail("chestdupe checkbox had no effect");
		click_widget(m_cb_chest[0]);
	} else {
		fail("no chestdupe checkbox");
	}

	// the last row (Hold-Mode) must be rendered AND wired: without it the
	// setting is unreachable in the UI (render loop / event bound must
	// cover all CHESTD_CHECKS rows, not just the first three)
	const s32 last_row =
			(s32)(sizeof(CHESTD_CHECKS) / sizeof(CHESTD_CHECKS[0])) - 1;
	const bool row_covered =
			last_row >= 0 && last_row < (s32)(sizeof(m_cb_chest) /
					sizeof(m_cb_chest[0]));
	if (row_covered && m_cb_chest[last_row]) {
		const bool before = read_bool("chest_dupe.hold_mode", true);
		click_widget(m_cb_chest[last_row]);
		if (read_bool("chest_dupe.hold_mode", true) == before)
			fail("hold-mode checkbox had no effect");
		click_widget(m_cb_chest[last_row]);
		if (read_bool("chest_dupe.hold_mode", true) != before)
			fail("hold-mode checkbox did not revert");
	} else {
		fail("no hold-mode checkbox");
	}

	if (m_btn_mode[1]) {
		const std::string mode_before = read_str("chest_dupe.mode", "Auto");
		click_widget(m_btn_mode[1]);
		if (read_str("chest_dupe.mode", "Auto") != "Crosshair only")
			fail("chestdupe mode not written");
		// the switch has to be visible: the active mode is marked
		if (m_btn_mode[0] && m_btn_mode[1]) {
			const std::wstring t0 = m_btn_mode[0]->getText();
			const std::wstring t1 = m_btn_mode[1]->getText();
			if (t1.find(L"(active)") == std::wstring::npos)
				fail("mode button does not show the active mode");
			if (t0.find(L"(active)") != std::wstring::npos)
				fail("both mode buttons show as active");
		}
		// restore the previous mode
		g_settings->set("chest_dupe.mode", mode_before);
		click_widget(m_btn_mode[0]);
	} else {
		fail("no chestdupe mode buttons");
	}

	// 7) Back to the main page, then Esc must close the panel
	{
		gui::IGUIElement *back = nullptr;
		for (gui::IGUIElement *w : m_widgets)
			if (w && w->getID() == EP_BACK)
				back = w;
		if (back) {
			click_widget(back);
		}
	}
	simulate_escape();
	if (is_open())
		fail("Esc did not close the panel");

	// 8) the X button must close the panel as well
	open();
	{
		gui::IGUIElement *close_btn = nullptr;
		for (gui::IGUIElement *w : m_widgets)
			if (w && w->getID() == EP_CLOSE)
				close_btn = w;
		if (close_btn) {
			click_widget(close_btn);
			if (is_open())
				fail("X button did not close the panel");
		} else {
			fail("no close button");
		}
	}

	return problems;
}

void ExtPanel::apply_xray_nodes()
{
	if (!m_edt_xray)
		return;
	g_settings->set("xray.nodes", wide_to_utf8(m_edt_xray->getText()));
	infostream << "[ExtPanel] xray.nodes applied" << std::endl;
	rebuild();
}

// ---------------------------------------------------------------------------
// Page builders
//
// All geometry is derived from the font height u, so the panel follows
// gui_scaling and the display density like every other engine GUI.
// ---------------------------------------------------------------------------

namespace {
	// Preferred panel width in font heights
	const s32 L_W = 42;
	// number of option rows on the main page
	const s32 L_ROWS = 6;

	enum EPage { PAGE_MAIN, PAGE_XRAY, PAGE_CHESTDUPE };

	struct Layout {
		core::rect<s32> panel;
		s32 u;        // font height (layout unit)
		s32 pad;      // inner padding
		s32 hdr_px;   // header height (title + separator)
		s32 label_h;  // height of a caption above the content (0 = none)
		s32 body_px;  // height for the content
		s32 row_px;   // row height (main page) / checkbox height (chestdupe)
		s32 hint_h;   // height of the hint line (chestdupe)
		bool desc;    // show the description line?
		bool title;   // show the title?
	};

	core::rect<s32> screen_rect(gui::IGUIEnvironment *env)
	{
		return core::rect<s32>(core::position2d<s32>(0, 0),
				env->getRootGUIElement()->getAbsoluteClippingRect()
						.getSize());
	}

	// Computes a layout that always fits into the screen.
	//
	// Everything is derived from the pixels that are actually available, not
	// from fixed multiples of the font: the panel grows with the font
	// (gui_scaling), but rows, buttons and text areas are distributed over
	// the space that is left. If even that does not fit, the content is
	// compressed step by step (descriptions off, rows shorter, title off,
	// padding smaller) so that every widget stays inside the panel.
	Layout compute_layout(gui::IGUIEnvironment *env, EPage page)
	{
		const s32 font_h = std::max<s32>(1, (s32)g_fontengine->getTextHeight());
		const core::rect<s32> screen = screen_rect(env);

		// space around the panel
		const s32 margin = std::max<s32>(0, std::min(font_h, screen.getWidth() / 10));
		const s32 avail_w = std::max<s32>(1, screen.getWidth() - 2 * margin);
		const s32 avail_h = std::max<s32>(1, screen.getHeight() - 2 * margin);

		Layout l;
		l.u = font_h;
		l.desc = false;
		l.title = true;
		l.row_px = 0;
		l.label_h = 0;
		l.hint_h = 0;

		// inner padding: shrinks on small screens
		l.pad = std::max<s32>(1,
				std::min(font_h, std::min(avail_w / 12, avail_h / 12)));
		// title + separator
		s32 title_h = std::min<s32>(font_h * 5 / 4, avail_h / 6);
		s32 hdr_px = title_h + 1;

		// minimum height of the content (one usable element per row)
		s32 body_min = 0;
		switch (page) {
		case PAGE_MAIN:
			body_min = L_ROWS * std::max<s32>(1, font_h / 2);
			break;
		case PAGE_XRAY:
			body_min = std::max<s32>(1, font_h / 2);
			break;
		case PAGE_CHESTDUPE:
			body_min = 4 * std::max<s32>(1, font_h / 2);
			break;
		}

		// distribute the available height: content first, header gets the rest
		s32 body_px = avail_h - hdr_px - 2 * l.pad;
		if (body_px < body_min) {
			// step 1: drop the title
			l.title = false;
			title_h = 0;
			hdr_px = 1;
			body_px = avail_h - hdr_px - 2 * l.pad;
			// step 2: drop the padding
			if (body_px < body_min) {
				l.pad = 0;
				body_px = avail_h - hdr_px;
			}
		}
		body_px = std::max<s32>(1, body_px);

		switch (page) {
		case PAGE_MAIN:
			l.row_px = std::max<s32>(1, body_px / L_ROWS);
			// label (1.5u) + description (1.5u) must fit into the row,
			// otherwise the description would run into the next row
			l.desc = l.row_px >= font_h * 3;
			body_px = L_ROWS * l.row_px;
			break;
		case PAGE_XRAY:
			// caption ("Nodelist") + edit box / apply button
			l.label_h = font_h;
			body_px = std::min<s32>(
					std::max<s32>(1, body_px - l.label_h - l.pad),
					font_h * 5 / 2);
			break;
		case PAGE_CHESTDUPE: {
			// mode buttons + hint + checkbox rows
			const s32 mode_h = std::min<s32>(body_px / 2, font_h * 5 / 2);
			// the hint ("only works while ChestDupe is enabled") is only
			// shown while the module is off
			l.hint_h = read_bool("chest_dupe", false) ? font_h : 0;
			l.row_px = std::max<s32>(1,
					(body_px - mode_h - l.hint_h - l.pad) /
							CHESTD_CHECK_COUNT);
			body_px = mode_h + l.hint_h + CHESTD_CHECK_COUNT * l.row_px;
			break;
		}
		}

		const s32 ph = std::min<s32>(
				hdr_px + l.label_h + body_px + 2 * l.pad, avail_h);
		const s32 pw = std::clamp<s32>(L_W * font_h,
				std::min<s32>(10 * font_h, avail_w), avail_w);

		l.hdr_px = hdr_px;
		l.body_px = body_px;
		l.panel = core::rect<s32>(
				core::position2d<s32>((screen.getWidth() - pw) / 2,
					(screen.getHeight() - ph) / 2),
				core::dimension2d<s32>(pw, ph));
		return l;
	}
}

void ExtPanel::build_main()
{
	const Layout lay = compute_layout(guienv, PAGE_MAIN);
	const core::rect<s32> &panel = lay.panel;
	const s32 u = lay.u;
	const s32 pad = lay.pad;
	m_menu->m_panel_rect = panel;

	const s32 inner_w = std::max<s32>(1, panel.getWidth() - pad * 2);
	const s32 title_h = lay.title ? u * 5 / 4 : 0;
	const s32 content_y = panel.UpperLeftCorner.Y + pad + lay.hdr_px;

	if (lay.title) {
		const std::wstring title_text = L"Ext Cheats";
		const s32 title_w = std::max<s32>(0, inner_w - u * 4);
		if ((s32)g_fontengine->getTextWidth(title_text) <= title_w) {
			auto *title = guienv->addStaticText(title_text.c_str(),
					core::rect<s32>(core::position2d<s32>(
									panel.UpperLeftCorner.X + pad,
									panel.UpperLeftCorner.Y + pad),
							core::dimension2d<s32>(title_w, title_h)),
					false, false, m_menu.get(), 0, false);
			title->setOverrideColor(video::SColor(255, 235, 238, 245));
			m_texts.push_back(title);
		}
	}

	// close button (top right)
	m_widgets.push_back(guienv->addButton(core::rect<s32>(
			core::position2d<s32>(panel.LowerRightCorner.X - pad - u * 3,
					panel.UpperLeftCorner.Y + pad),
			core::dimension2d<s32>(u * 3, std::max<s32>(1, title_h))),
			m_menu.get(), EP_CLOSE, L"X"));
	// separator under the header
	if (lay.title)
		add_sep(guienv, m_menu.get(),
				core::rect<s32>(core::position2d<s32>(
								panel.UpperLeftCorner.X + pad,
								panel.UpperLeftCorner.Y + pad + title_h),
						core::dimension2d<s32>(inner_w, 1)));

	// rows
	const s32 btn_h = std::max<s32>(1, std::min<s32>(u * 5 / 2, lay.row_px));
	// The controls must fit into the panel: shrink them proportionally if the
	// screen is too narrow for the preferred sizes.
	s32 btn_w = u * 6;
	s32 gear_w = u * 9;
	const s32 controls_max = std::max<s32>(u * 4, inner_w - u);
	if (btn_w + gear_w > controls_max) {
		const s32 total = btn_w + gear_w;
		const s32 min_btn = std::max<s32>(u * 2, controls_max / 4);
		btn_w = std::max(min_btn, (s32)((s64)btn_w * controls_max / total));
		gear_w = std::max(min_btn, controls_max - btn_w);
	}
	const s32 label_w = std::max<s32>(0, inner_w - btn_w - gear_w - u * 2);

	for (s32 i = 0; i < L_ROWS; i++) {
		const MainRow &row = MAIN_ROWS[i];
		const s32 y = content_y + i * lay.row_px;
		const s32 btn_y = y + std::max<s32>(0, (lay.row_px - btn_h) / 2);

		// Only draw the label if it fits into the column: static texts are
		// drawn without clipping and would run over the buttons.
		const std::wstring label_text = w(row.label);
		if (lay.row_px >= u * 3 / 2 &&
				(s32)g_fontengine->getTextWidth(label_text) <= label_w) {
			auto *label = guienv->addStaticText(label_text.c_str(),
					core::rect<s32>(core::position2d<s32>(
									panel.UpperLeftCorner.X + pad, y),
							core::dimension2d<s32>(label_w, u * 3 / 2)),
					false, false, m_menu.get(), 0, false);
			label->setOverrideColor(video::SColor(255, 224, 230, 238));
			m_texts.push_back(label);
		}

		if (lay.desc) {
			const std::wstring desc_text = w(row.desc);
			const s32 desc_h = std::min<s32>(u * 3 / 2, lay.row_px - u * 3 / 2);
			if (desc_h > 0 &&
					(s32)g_fontengine->getTextWidth(desc_text) <= label_w) {
				auto *desc = guienv->addStaticText(desc_text.c_str(),
						core::rect<s32>(core::position2d<s32>(
										panel.UpperLeftCorner.X + pad,
										y + u * 3 / 2),
								core::dimension2d<s32>(label_w, desc_h)),
						false, false, m_menu.get(), 0, false);
				desc->setOverrideColor(video::SColor(255, 128, 138, 152));
				m_texts.push_back(desc);
			}
		}

		// On/Off
		const bool cur = read_bool(row.key, false);
		auto *btn = guienv->addButton(
				core::rect<s32>(core::position2d<s32>(
								panel.LowerRightCorner.X - pad - btn_w, btn_y),
						core::dimension2d<s32>(btn_w, btn_h)),
				m_menu.get(), EP_ID_BASE + i, cur ? L"On" : L"Off");
		m_btn_main[i] = btn;
		m_widgets.push_back(btn);

		// Settings (only for rows with a subpage)
		if (row.page && *row.page) {
			auto *gear = guienv->addButton(
					core::rect<s32>(core::position2d<s32>(
									panel.LowerRightCorner.X - pad - btn_w -
											gear_w - u, btn_y),
							core::dimension2d<s32>(gear_w, btn_h)),
					m_menu.get(), EP_SETTINGS_BASE + i, L"Settings...");
			m_btn_settings[i] = gear;
			m_widgets.push_back(gear);
		}
	}
}

void ExtPanel::build_xray()
{
	const Layout lay = compute_layout(guienv, PAGE_XRAY);
	const core::rect<s32> &panel = lay.panel;
	const s32 u = lay.u;
	const s32 pad = lay.pad;
	m_menu->m_panel_rect = panel;

	const s32 inner_w = std::max<s32>(1, panel.getWidth() - pad * 2);
	const s32 title_h = lay.title ? u * 5 / 4 : 0;
	const s32 content_y = panel.UpperLeftCorner.Y + pad + lay.hdr_px;

	if (lay.title) {
		const std::wstring title_text = w("XRay — Node blocks");
		const s32 title_w = std::max<s32>(0, inner_w - u * 4);
		if ((s32)g_fontengine->getTextWidth(title_text) <= title_w) {
			auto *title = guienv->addStaticText(title_text.c_str(),
					core::rect<s32>(core::position2d<s32>(
									panel.UpperLeftCorner.X + pad,
									panel.UpperLeftCorner.Y + pad),
							core::dimension2d<s32>(title_w, title_h)),
					false, false, m_menu.get(), 0, false);
			title->setOverrideColor(video::SColor(255, 235, 238, 245));
			m_texts.push_back(title);
		}
	}

	m_widgets.push_back(guienv->addButton(core::rect<s32>(
			core::position2d<s32>(panel.LowerRightCorner.X - pad - u * 3,
					panel.UpperLeftCorner.Y + pad),
			core::dimension2d<s32>(u * 3, std::max<s32>(1, title_h))),
			m_menu.get(), EP_BACK, L"<"));

	if (lay.title)
		add_sep(guienv, m_menu.get(),
				core::rect<s32>(core::position2d<s32>(
								panel.UpperLeftCorner.X + pad,
								panel.UpperLeftCorner.Y + pad + title_h),
						core::dimension2d<s32>(inner_w, 1)));

	// "Nodelist" is the legacy name of this setting.
	{
		const std::wstring label_text = w("Nodelist");
		const s32 label_w = std::max<s32>(0, inner_w - u * 8);
		if ((s32)g_fontengine->getTextWidth(label_text) <= label_w) {
			auto *label = guienv->addStaticText(label_text.c_str(),
					core::rect<s32>(core::position2d<s32>(
									panel.UpperLeftCorner.X + pad,
									content_y),
							core::dimension2d<s32>(label_w, lay.label_h)),
					false, false, m_menu.get(), 0, false);
			label->setOverrideColor(video::SColor(255, 224, 230, 238));
			m_texts.push_back(label);
		}
	}

	// Edit box and Apply button share the body: side by side if there is
	// room, otherwise stacked.
	const s32 body_y = content_y + lay.label_h + pad;
	const s32 body_h = std::max<s32>(1, lay.body_px);
	const bool side_by_side = inner_w > u * 10;
	const s32 edit_w = side_by_side ? std::max<s32>(1, inner_w - u * 8) : inner_w;
	const s32 edit_h = side_by_side ? body_h : std::max<s32>(1, body_h / 2);

	core::rect<s32> edit_rect(
			core::position2d<s32>(panel.UpperLeftCorner.X + pad, body_y),
			core::dimension2d<s32>(edit_w, edit_h));
	m_edt_xray = guienv->addEditBox(utf8_to_wide(read_str("xray.nodes", "")).c_str(),
			edit_rect, true, m_menu.get(), EP_XRAY_EDIT);
	m_widgets.push_back(m_edt_xray);

	const s32 apply_w = std::min<s32>(u * 7, inner_w);
	const s32 apply_x = side_by_side
			? std::min<s32>(edit_rect.LowerRightCorner.X + pad,
					panel.LowerRightCorner.X - pad - apply_w)
			: panel.UpperLeftCorner.X + pad;
	const s32 apply_y = side_by_side ? body_y : body_y + edit_h + pad;
	m_widgets.push_back(guienv->addButton(core::rect<s32>(
			core::position2d<s32>(apply_x, apply_y),
			core::dimension2d<s32>(apply_w,
					side_by_side ? body_h : std::max<s32>(1, body_h - edit_h - pad))),
			m_menu.get(), EP_XRAY_APPLY, L"Apply"));
}

void ExtPanel::build_chestdupe()
{
	const Layout lay = compute_layout(guienv, PAGE_CHESTDUPE);
	const core::rect<s32> &panel = lay.panel;
	const s32 u = lay.u;
	const s32 pad = lay.pad;
	m_menu->m_panel_rect = panel;

	const s32 inner_w = std::max<s32>(1, panel.getWidth() - pad * 2);
	const s32 title_h = lay.title ? u * 5 / 4 : 0;
	const s32 content_y = panel.UpperLeftCorner.Y + pad + lay.hdr_px;

	if (lay.title) {
		const std::wstring title_text = w("ChestDupe — Settings");
		const s32 title_w = std::max<s32>(0, inner_w - u * 4);
		if ((s32)g_fontengine->getTextWidth(title_text) <= title_w) {
			auto *title = guienv->addStaticText(title_text.c_str(),
					core::rect<s32>(core::position2d<s32>(
									panel.UpperLeftCorner.X + pad,
									panel.UpperLeftCorner.Y + pad),
							core::dimension2d<s32>(title_w, title_h)),
					false, false, m_menu.get(), 0, false);
			title->setOverrideColor(video::SColor(255, 235, 238, 245));
			m_texts.push_back(title);
		}
	}

	m_widgets.push_back(guienv->addButton(core::rect<s32>(
			core::position2d<s32>(panel.LowerRightCorner.X - pad - u * 3,
					panel.UpperLeftCorner.Y + pad),
			core::dimension2d<s32>(u * 3, std::max<s32>(1, title_h))),
			m_menu.get(), EP_BACK, L"<"));

	if (lay.title)
		add_sep(guienv, m_menu.get(),
				core::rect<s32>(core::position2d<s32>(
								panel.UpperLeftCorner.X + pad,
								panel.UpperLeftCorner.Y + pad + title_h),
						core::dimension2d<s32>(inner_w, 1)));

	// mode buttons + checkbox rows, distributed over the body
	const s32 body_h = std::max<s32>(1, lay.body_px);
	const s32 mode_h = std::max<s32>(1, std::min<s32>(body_h / 2, u * 5 / 2));
	const s32 mode_w = std::max<s32>(1, (inner_w - pad) / 2);

	// The active mode is marked with a check mark: the pressed state of a
	// standard button is barely visible, so the switch looked like it did
	// not work at all.
	const bool auto_active = read_str("chest_dupe.mode", "Auto") == "Auto";
	auto *btn_auto = guienv->addButton(core::rect<s32>(
			core::position2d<s32>(panel.UpperLeftCorner.X + pad, content_y),
			core::dimension2d<s32>(mode_w, mode_h)),
			m_menu.get(), EP_CHESTD_MODE_AUTO,
			auto_active ? L"Auto  (active)" : L"Auto");
	btn_auto->setPressed(auto_active);
	m_btn_mode[0] = btn_auto;
	m_widgets.push_back(btn_auto);

	auto *btn_cross = guienv->addButton(core::rect<s32>(
			core::position2d<s32>(panel.UpperLeftCorner.X + pad + mode_w + pad,
					content_y),
			core::dimension2d<s32>(mode_w, mode_h)),
			m_menu.get(), EP_CHESTD_MODE_CROSS,
			auto_active ? L"Crosshair only" : L"Crosshair only  (active)");
	btn_cross->setPressed(!auto_active);
	m_btn_mode[1] = btn_cross;
	m_widgets.push_back(btn_cross);

	// Hinweis: die Optionen wirken nur, wenn das Modul eingeschaltet ist
	if (lay.hint_h > 0) {
		const std::wstring hint = L"These settings only work while "
			L"ChestDupe is enabled.";
		const s32 hint_w = std::max<s32>(0, inner_w);
		if ((s32)g_fontengine->getTextWidth(hint) <= hint_w) {
			auto *label = guienv->addStaticText(hint.c_str(),
					core::rect<s32>(core::position2d<s32>(
									panel.UpperLeftCorner.X + pad,
									content_y + mode_h),
							core::dimension2d<s32>(hint_w, lay.hint_h)),
					false, false, m_menu.get(), 0, false);
			label->setOverrideColor(video::SColor(255, 200, 170, 110));
			m_texts.push_back(label);
		}
	}

	const s32 box_h = lay.row_px;
	const s32 box_y0 = content_y + mode_h + lay.hint_h + pad;
	for (s32 i = 0; i < CHESTD_CHECK_COUNT; i++) {
		const CheckboxRow &row = CHESTD_CHECKS[i];
		auto *cb = guienv->addCheckBox(read_bool(row.key, row.def),
				core::rect<s32>(
						core::position2d<s32>(
								panel.UpperLeftCorner.X + pad,
								box_y0 + i * box_h),
						core::dimension2d<s32>(inner_w, box_h)),
				m_menu.get(), EP_CHESTD_CHECK_BASE + i,
				w(row.label).c_str());
		m_cb_chest[i] = cb;
		m_widgets.push_back(cb);
	}
}
