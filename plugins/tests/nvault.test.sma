// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

#include <amxmodx>
#include <nvault>
#include <amxxbench>

public plugin_init()
{
	register_plugin("nVault Test", "1.0", "BAILOPAN")
}

public test_nvault_open_invalid_name()
{
	new v = nvault_open("://:/1/R!?#@41345$%:$")

	if (v != -1)
	{
		nvault_close(v)
	}

	ASSERT_EQ(v, -1);
	bench_pass()
}
