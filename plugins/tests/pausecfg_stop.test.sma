// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// A plugin for pausecfg.test.sma to stop. A stopped plugin cannot be started again, so this one
// does nothing, and stays stopped once a test stops it.
//

#include <amxmodx>

public plugin_init()
{
	register_plugin("Stop Target", AMXX_VERSION_STR, "AMXX Dev Team")
}
