// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for ts/statssounds.sma (TS Sounds Precache). The plugin only precaches the stats sounds,
// before any test runs, so all that is left to check is that it loaded and runs.
//

#include <amxmodx>
#include <amxxbench>

public plugin_init()
{
	register_plugin("TS Sounds Precache Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public test_plugin_is_running()
{
	new index = find_plugin_byfile("statssounds.amxx")
	ASSERT(index >= 0)

	new file[64], name[64], version[32], author[32], status[16]
	get_plugin(index, file, charsmax(file), name, charsmax(name), version, charsmax(version), author, charsmax(author), status, charsmax(status))
	ASSERT_STR_EQ(name, "TS Sounds Precache")
	ASSERT_STR_EQ(author, "AMXX Dev Team")
	// "debug" when the bench runs with coverage.
	ASSERT(equal(status, "running") || equal(status, "debug"))
	bench_pass()
}
