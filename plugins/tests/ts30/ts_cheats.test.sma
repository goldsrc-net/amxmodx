// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the original The Specialists 3.0's "powerup <n>" cheat: it works only when the map started
// with sv_cheats 1, and its table is 1 slow pause, 2 a grenade, 3 kung fu and superjump together,
// 4 more clips, 5 double fire rate, anything else slow motion. ../ts_cheats.test.sma is the same on
// reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <amxxbench>

new g_Map[32]

public plugin_init()
{
	register_plugin("TS Cheat Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	get_mapname(g_Map, charsmax(g_Map))
}

// The type the PwUp message last told the player he holds, or -1.
LastHeld(id)
{
	new BenchMsg:msg = bench_msg_last(id, "PwUp")
	if (msg == BenchMsg:0)
		return -1
	return bench_msg_int(msg, 0)
}

public test_powerup_needs_cheats()
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	new id = bench_puppet("nocheat")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "nocheat_spawned", 20.0, "respawn")
}

public nocheat_spawned(id)
{
	bench_puppet_cmd(id, "powerup 1")
	bench_puppet_cmd(id, "powerup 3")
	bench_next("nocheat_after", 0.5, id)
}

public nocheat_after(id)
{
	ASSERT(LastHeld(id) != TSPWUP_SLOWPAUSE)
	ASSERT_EQ(ts_has_fupowerup(id), 0)
	ASSERT_EQ(ts_has_superjump(id), 0)
	bench_pass()
}

// The game reads sv_cheats when the map starts, so the cheats are turned on with a map change, and
// off again with another.
public test_powerup_table()
{
	bench_set_timeout(120.0)
	set_cvar_num("sv_cheats", 1)
	bench_change_map(g_Map, "table_map")
}

public table_map()
{
	new id = bench_puppet("cheater")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "table_spawned", 20.0, "respawn")
}

public table_spawned(id)
{
	bench_puppet_cmd(id, "powerup 3")
	bench_next("table_kungfu", 0.5, id)
}

public table_kungfu(id)
{
	ASSERT_EQ(ts_has_fupowerup(id), 1)
	ASSERT_EQ(ts_has_superjump(id), 1)
	bench_puppet_cmd(id, "powerup 6")
	bench_next("table_six", 0.5, id)
}

public table_six(id)
{
	// 6 is not in the table: slow motion, held.
	ASSERT_EQ(LastHeld(id), TSPWUP_SLOWMO)
	bench_puppet_cmd(id, "powerup 7")
	bench_next("table_seven", 0.5, id)
}

public table_seven(id)
{
	ASSERT_EQ(LastHeld(id), TSPWUP_SLOWMO)
	bench_puppet_cmd(id, "powerup 1")
	bench_next("table_one", 0.5, id)
}

public table_one(id)
{
	ASSERT_EQ(LastHeld(id), TSPWUP_SLOWPAUSE)
	set_cvar_num("sv_cheats", 0)
	bench_change_map(g_Map, "table_restored")
}

public table_restored()
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	bench_pass()
}
