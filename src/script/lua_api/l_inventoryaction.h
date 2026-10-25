// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2020 Elias Fleckenstein <eliasfleckenstein@web.de>

#pragma once

#include "lua_api/l_base.h"
#include "inventorymanager.h"

#define GET_MOVE_ACTION                                                                  \
	LuaInventoryAction *o = checkobject(L, 1);                                       \
	if (o->m_action->getType() == IAction::Craft)                                    \
		return 0;                                                                \
	MoveAction *act = dynamic_cast<MoveAction *>(o->m_action);

class LuaInventoryAction : public ModApiBase
{
private:
	InventoryAction *m_action;

	static void readFullInventoryLocationInto(lua_State *L, InventoryLocation *loc,
			std::string *list, s16 *index);

	static const luaL_Reg methods[];

	// Exported functions

	// garbage collector
	static int gc_object(lua_State *L);

	// __tostring metamethod
	static int mt_tostring(lua_State *L);

	// apply(self)
	static int l_apply(lua_State *L);

	// from(self, location, list, index)
	static int l_from(lua_State *L);

	// to(self, location, list, index)
	static int l_to(lua_State *L);

	// craft(self, location)
	static int l_craft(lua_State *L);

	// set_count(self, count)
	static int l_set_count(lua_State *L);

public:
	LuaInventoryAction(const IAction &type);
	~LuaInventoryAction();

	static const char className[];


	// LuaInventoryAction(inventory action type)
	// Creates a LuaInventoryAction and leaves it on top of the stack
	static int create_object(lua_State *L);
	// Not callable from Lua
	static int create(lua_State *L, const IAction &type);
	static LuaInventoryAction *checkobject(lua_State *L, int narg);
	static void Register(lua_State *L);
};
