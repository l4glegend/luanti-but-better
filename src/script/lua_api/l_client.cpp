// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>
// Copyright (C) 2017 nerzhul, Loic Blot <loic.blot@unix-experience.fr>

#include "l_client.h"
#include "chatmessage.h"
#include "client/client.h"
#include "client/inputhandler.h"
#include "client/sound.h"
#include "client/clientenvironment.h"
#include "common/c_content.h"
#include "common/c_converter.h"
#include "cpp_api/s_base.h"
#include "gettext.h"
#include "inventorymanager.h"
#include "itemdef.h"
#include "l_internal.h"
#include "lua_api/l_nodemeta.h"
#include "gui/mainmenumanager.h"
#include "map.h"
#include "util/string.h"
#include "nodedef.h"

#define checkCSMRestrictionFlag(flag) \
	( getClient(L)->checkCSMRestrictionFlag(CSMRestrictionFlags::flag) )

// Not the same as FlagDesc, which contains an `u32 flag`
struct CSMFlagDesc {
	const char *name;
	u64 flag;
};

/*
	FIXME: This should eventually be moved somewhere else
	It also needs to be kept in sync with the definition of CSMRestrictionFlags
	in network/networkprotocol.h
*/
const static CSMFlagDesc flagdesc_csm_restriction[] = {
	{"load_client_mods",  CSM_RF_LOAD_CLIENT_MODS},
	{"chat_messages",     CSM_RF_CHAT_MESSAGES},
	{"read_itemdefs",     CSM_RF_READ_ITEMDEFS},
	{"read_nodedefs",     CSM_RF_READ_NODEDEFS},
	{"lookup_nodes",      CSM_RF_LOOKUP_NODES},
	{"read_playerinfo",   CSM_RF_READ_PLAYERINFO},
	{NULL,      0}
};

// get_current_modname()
int ModApiClient::l_get_current_modname(lua_State *L)
{
	std::string s = ScriptApiBase::getCurrentModNameInsecure(L);
	if (!s.empty())
		lua_pushstring(L, s.c_str());
	else
		lua_pushnil(L);
	return 1;
}

// get_modpath(modname)
int ModApiClient::l_get_modpath(lua_State *L)
{
	std::string modname = readParam<std::string>(L, 1);
	// Client mods use a virtual filesystem, see ModVFS::scanModSubfolder()
	std::string path = modname + ":";
	lua_pushstring(L, path.c_str());
	return 1;
}

// print(text)
int ModApiClient::l_print(lua_State *L)
{
	NO_MAP_LOCK_REQUIRED;
	std::string text = luaL_checkstring(L, 1);
	rawstream << text << std::endl;
	return 0;
}

// display_chat_message(message)
int ModApiClient::l_display_chat_message(lua_State *L)
{
	if (!lua_isstring(L, 1))
		return 0;

	std::string message = luaL_checkstring(L, 1);
	getClient(L)->pushToChatQueue(new ChatMessage(utf8_to_wide(message)));
	lua_pushboolean(L, true);
	return 1;
}

// send_chat_message(message)
int ModApiClient::l_send_chat_message(lua_State *L)
{
	if (!lua_isstring(L, 1))
		return 0;

	// If server disabled this API, discard

	if (checkCSMRestrictionFlag(CSM_RF_CHAT_MESSAGES))
		return 0;

	std::string message = luaL_checkstring(L, 1);
	getClient(L)->sendChatMessage(utf8_to_wide(message));
	return 0;
}

// clear_out_chat_queue()
int ModApiClient::l_clear_out_chat_queue(lua_State *L)
{
	getClient(L)->clearOutChatQueue();
	return 0;
}

// get_player_names()
int ModApiClient::l_get_player_names(lua_State *L)
{
	if (checkCSMRestrictionFlag(CSM_RF_READ_PLAYERINFO))
		return 0;

	auto plist = getClient(L)->getConnectedPlayerNames();
	lua_createtable(L, plist.size(), 0);
	int newTable = lua_gettop(L);
	int index = 1;
	for (const std::string &name : plist) {
		lua_pushstring(L, name.c_str());
		lua_rawseti(L, newTable, index);
		index++;
	}
	return 1;
}

// disconnect()
int ModApiClient::l_disconnect(lua_State *L)
{
	// Stops badly written Lua code form causing boot loops
	if (getClient(L)->isShutdown()) {
		lua_pushboolean(L, false);
		return 1;
	}

	g_gamecallback->disconnect();
	lua_pushboolean(L, true);
	return 1;
}

// gettext(text)
int ModApiClient::l_gettext(lua_State *L)
{
	std::string text = strgettext(luaL_checkstring(L, 1));
	lua_pushstring(L, text.c_str());

	return 1;
}

// get_node_or_nil(pos)
// pos = {x=num, y=num, z=num}
int ModApiClient::l_get_node_or_nil(lua_State *L)
{
	// pos
	v3s16 pos = read_v3s16(L, 1);

	// Do it
	bool pos_ok;
	MapNode n = getClient(L)->CSMGetNode(pos, &pos_ok);
	if (pos_ok) {
		// Return node
		pushnode(L, n);
	} else {
		lua_pushnil(L);
	}
	return 1;
}

// get_langauge()
int ModApiClient::l_get_language(lua_State *L)
{
#ifdef _WIN32
	char *locale = setlocale(LC_ALL, NULL);
#else
	char *locale = setlocale(LC_MESSAGES, NULL);
#endif
	std::string lang = gettext("LANG_CODE");
	if (lang == "LANG_CODE")
		lang.clear();

	lua_pushstring(L, locale);
	lua_pushstring(L, lang.c_str());
	return 2;
}

// get_meta(pos)
int ModApiClient::l_get_meta(lua_State *L)
{
	v3s16 p = read_v3s16(L, 1);

	// check restrictions first
	bool pos_ok;
	getClient(L)->CSMGetNode(p, &pos_ok);
	if (!pos_ok)
		return 0;

	NodeMetadata *meta = getEnv(L)->getMap().getNodeMetadata(p);
	NodeMetaRef::createClient(L, meta);
	return 1;
}

// drop_inventory_list(location, listname, [single])
// Drops the content of an inventory list. The client does not know how many
// slots a foreign inventory has, so every possible slot is requested; the
// server validates the drops and ignores empty ones.
// With single=true only one item per slot is dropped (like the normal drop
// with sneak held down).
int ModApiClient::l_drop_inventory_list(lua_State *L)
{
	Client *client = getClient(L);
	std::string location = readParam<std::string>(L, 1);
	std::string listname = readParam<std::string>(L, 2);
	const bool single = (lua_gettop(L) >= 3 && lua_toboolean(L, 3));

	InventoryLocation loc;
	loc.deSerialize(location);

	for (s32 i = 0; i < 32; i++) {
		IDropAction *a = new IDropAction();
		a->count = single ? 1 : 0; // 0 = everything in that slot
		a->from_inv = loc;
		a->from_list = listname;
		a->from_i = i;
		client->inventoryAction(a);
	}
	return 0;
}

// drop_inventory_slot(location, listname, index, [count])
// Drops one slot of an inventory list. index is 0-based (like the engine
// actions), count = 0 (default) drops the whole stack, count > 0 drops that
// many items. Used by the chest dupe to drop the duplicated stacks straight
// out of the chest without touching the rest of the chest content.
int ModApiClient::l_drop_inventory_slot(lua_State *L)
{
	Client *client = getClient(L);
	std::string location = readParam<std::string>(L, 1);
	std::string listname = readParam<std::string>(L, 2);
	const s32 index = readParam<s32>(L, 3);
	s32 count = 0;
	if (lua_gettop(L) >= 4)
		count = readParam<s32>(L, 4);

	InventoryLocation loc;
	loc.deSerialize(location);

	IDropAction *a = new IDropAction();
	a->count = count; // 0 = everything in that slot
	a->from_inv = loc;
	a->from_list = listname;
	a->from_i = index;
	client->inventoryAction(a);
	return 0;
}

// get_server_info()
int ModApiClient::l_get_server_info(lua_State *L)
{
	Client *client = getClient(L);
	Address serverAddress = client->getServerAddress();
	lua_newtable(L);
	lua_pushstring(L, client->getAddressName().c_str());
	lua_setfield(L, -2, "address");
	lua_pushstring(L, serverAddress.serializeString().c_str());
	lua_setfield(L, -2, "ip");
	lua_pushinteger(L, serverAddress.getPort());
	lua_setfield(L, -2, "port");
	lua_pushinteger(L, client->getProtoVersion());
	lua_setfield(L, -2, "protocol_version");
	return 1;
}

// get_item_def(itemstring)
int ModApiClient::l_get_item_def(lua_State *L)
{
	IGameDef *gdef = getGameDef(L);
	assert(gdef);

	IItemDefManager *idef = gdef->idef();
	assert(idef);

	if (checkCSMRestrictionFlag(CSM_RF_READ_ITEMDEFS))
		return 0;

	if (!lua_isstring(L, 1))
		return 0;

	std::string name = readParam<std::string>(L, 1);
	if (!idef->isKnown(name))
		return 0;
	const ItemDefinition &def = idef->get(name);

	push_item_definition_full(L, def);

	return 1;
}

// get_node_def(nodename)
int ModApiClient::l_get_node_def(lua_State *L)
{
	IGameDef *gdef = getGameDef(L);
	assert(gdef);

	const NodeDefManager *ndef = gdef->ndef();
	assert(ndef);

	if (!lua_isstring(L, 1))
		return 0;

	if (checkCSMRestrictionFlag(CSM_RF_READ_NODEDEFS))
		return 0;

	std::string name = readParam<std::string>(L, 1);
	const ContentFeatures &cf = ndef->get(ndef->getId(name));
	if (cf.name != name) // Unknown node. | name = <whatever>, cf.name = ignore
		return 0;

	push_content_features(L, cf);

	return 1;
}

// get_privilege_list()
int ModApiClient::l_get_privilege_list(lua_State *L)
{
	const Client *client = getClient(L);
	lua_newtable(L);
	for (const std::string &priv : client->getPrivilegeList()) {
		lua_pushboolean(L, true);
		lua_setfield(L, -2, priv.c_str());
	}
	return 1;
}

// get_builtin_path()
int ModApiClient::l_get_builtin_path(lua_State *L)
{
	std::string modname;
	if (getScriptApiBase(L)->getType() == ScriptingType::Client) {
		modname = BUILTIN_MOD_NAME;
	} else if (getScriptApiBase(L)->getType() == ScriptingType::SSCSM) {
		// get_builtin_path() is only called in builtin, so this is fine
		modname = ScriptApiBase::getCurrentModNameInsecure(L);
		if (modname != "*client_builtin*" && modname != "*server_builtin*")
			modname = "";
	}

	if (modname.empty())
		return 0;

	lua_pushstring(L, (modname + ":").c_str());
	return 1;
}

// get_csm_restrictions()
int ModApiClient::l_get_csm_restrictions(lua_State *L)
{
	u64 flags = getClient(L)->getCSMRestrictionFlags();
	const CSMFlagDesc *flagdesc = flagdesc_csm_restriction;

	lua_newtable(L);
	for (int i = 0; flagdesc[i].name; i++) {
		setboolfield(L, -1, flagdesc[i].name, !!(flags & flagdesc[i].flag));
	}
	return 1;
}

// get_inventory(location)
int ModApiClient::l_get_inventory(lua_State *L)
{
	Client *client = getClient(L);
	InventoryLocation inventory_location;
	Inventory *inventory;
	std::string location;

	location = readParam<std::string>(L, 1);

	try {
		inventory_location.deSerialize(location);
		inventory = client->getInventory(inventory_location);
		if (!inventory)
			throw SerializationError(std::string("Attempt to access nonexistant inventory (") + location + ")");
		push_inventory_lists(L, *inventory);
	} catch (SerializationError &) {
		lua_pushnil(L);
	}

	return 1;
}

// is_key_down(keyname)
// Returns true while the given key (e.g. "KEY_KEY_0") is physically held,
// independent of any keybindings
int ModApiClient::l_is_key_down(lua_State *L)
{
	KeyPress key(readParam<std::string>(L, 1));
	MyEventReceiver *receiver = getRawKeyReceiver();

	bool down = receiver && receiver->isKeyRawDown(key);
	lua_pushboolean(L, down);
	return 1;
}

// is_mouse_down(button)
// Returns true while the given mouse button is physically held
// (0 = left, 1 = middle, 2 = right)
int ModApiClient::l_is_mouse_down(lua_State *L)
{
	int button = readParam<int>(L, 1);
	MyEventReceiver *receiver = getRawKeyReceiver();

	bool down = receiver && button >= 0 && button < 3
			&& receiver->isMouseButtonDown((u8)button);
	lua_pushboolean(L, down);
	return 1;
}

// get_node_name(pos)
// Close to core.get_node but named; does not need a table
// Rather for CSM with read node defs
int ModApiClient::l_get_node_name(lua_State *L)
{
	v3s16 pos = read_v3s16(L, 1);

	Client *client = getClient(L);
	const NodeDefManager *nodedef = client->getNodeDefManager();

	bool pos_ok;
	MapNode n = client->CSMGetNode(pos, &pos_ok);
	if (pos_ok) {
		if (n.getContent() == CONTENT_IGNORE) {
			lua_pushstring(L, "ignore");
		} else if (nodedef->get(n).name == "unknown") {
			lua_pushstring(L, "unknown");
		} else {
			lua_pushstring(L, nodedef->get(n).name.c_str());
		}
	} else {
		lua_pushnil(L);
	}

	return 1;
}

void ModApiClient::Initialize(lua_State *L, int top)
{
	API_FCT(get_current_modname);
	API_FCT(get_modpath);
	API_FCT(print);
	API_FCT(display_chat_message);
	API_FCT(send_chat_message);
	API_FCT(clear_out_chat_queue);
	API_FCT(get_player_names);
	API_FCT(gettext);
	API_FCT(get_node_or_nil);
	API_FCT(disconnect);
	API_FCT(get_meta);
	API_FCT(drop_inventory_list);
	API_FCT(drop_inventory_slot);
	API_FCT(get_server_info);
	API_FCT(get_item_def);
	API_FCT(get_node_def);
	API_FCT(get_privilege_list);
	API_FCT(get_builtin_path);
	API_FCT(get_language);
	API_FCT(get_csm_restrictions);
	API_FCT(get_inventory);
	API_FCT(is_key_down);
	API_FCT(is_mouse_down);
	API_FCT(get_node_name);
}

void ModApiClient::InitializeSSCSM(lua_State *L, int top)
{
	API_FCT(get_current_modname);
	API_FCT(get_modpath);
	API_FCT(print);
	API_FCT(get_builtin_path);
}
