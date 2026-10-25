/*
luanti-ext fork
Which packets the UIUtils "block all packets" setting may suppress.

The setting is persisted in the config and the UIUtils panel keeps it
across reconnects, so a suppressed handshake packet is not a temporary
glitch: the client waits for a server reply that never arrives and hangs
on "Connecting to server..." until the config file is edited by hand.
*/

#pragma once

#include "../network/networkprotocol.h"

namespace uinutils
{

// Packets that carry the connection handshake. They must always reach
// the server, otherwise the client never finishes connecting.
inline bool is_handshake_command(u16 cmd)
{
	switch (cmd) {
	case TOSERVER_INIT:
	case TOSERVER_INIT2:
	case TOSERVER_SRP_BYTES_A:
	case TOSERVER_SRP_BYTES_M:
	case TOSERVER_CLIENT_READY:
		return true;
	default:
		return false;
	}
}

// True if the command must be dropped because "block all" is enabled.
inline bool blocks_command(u16 cmd, bool block_all)
{
	if (!block_all)
		return false;
	if (is_handshake_command(cmd))
		return false;
	return cmd != TOSERVER_CHAT_MESSAGE;
}

} // namespace uinutils
