// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/fakemeta_tests.sma. The original prints the game time in
// ServerDeactivate() and in plugin_end(), for a person to see that the hook runs and runs first
// when the map ends. A test run stops when the map changes, so only the hook's registration is
// checked here; the prints are kept.
//

#include <amxmodx>
#include <fakemeta>
#include <amxxbench>

new g_ServerDeactivateFwd = -1

public plugin_init()
{
	register_plugin("Fakemeta Tests", "1.0", "BAILOPAN")
	g_ServerDeactivateFwd = register_forward(FM_ServerDeactivate, "Hook_ServerDeactivate")
}

public Hook_ServerDeactivate()
{
	server_print("[FAKEMETA TEST] ServerDeactivate() at %f", get_gametime())
}

public plugin_end()
{
	server_print("[FAKEMETA TEST] plugin_end() at %f", get_gametime())
}

public test_server_deactivate_hook_registered()
{
	ASSERT(g_ServerDeactivateFwd > 0)
	bench_pass()
}
