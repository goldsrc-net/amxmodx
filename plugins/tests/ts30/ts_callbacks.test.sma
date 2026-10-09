// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the engine callbacks of the original The Specialists 3.0 with what a plugin can hand
// them. A trace with no entity to skip passes the engine a NULL edict to the game's ShouldCollide,
// which lets the touched entity's own ShouldCollide decide (0x9b7b4), so the trace hits a player in
// its way.
// ../ts_callbacks.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <amxxbench>

new g_P

public plugin_init()
{
	register_plugin("TS Callback Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

// A line and a point hull from just above a player's head down through him, skipping no entity,
// both stop at him.
public test_trace_with_no_skip_entity_hits_a_player()
{
	g_P = bench_puppet("traced")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "traced_spawned", 20.0, "respawn")
}

public traced_spawned(id)
{
	new Float:origin[3], Float:start[3], Float:end[3]
	pev(id, pev_origin, origin)
	start = origin
	start[2] += 64.0
	end = origin
	end[2] -= 16.0

	new tr = create_tr2()
	engfunc(EngFunc_TraceLine, start, end, DONT_IGNORE_MONSTERS, 0, tr)
	new hit = get_tr2(tr, TR_pHit)
	new Float:fraction
	get_tr2(tr, TR_flFraction, fraction)
	server_print("ts_callbacks: line hit %d (player %d), fraction %f", hit, id, fraction)
	ASSERT_EQ(hit, id)
	ASSERT(fraction < 1.0)

	engfunc(EngFunc_TraceHull, start, end, DONT_IGNORE_MONSTERS, HULL_POINT, 0, tr)
	hit = get_tr2(tr, TR_pHit)
	server_print("ts_callbacks: hull hit %d", hit)
	free_tr2(tr)
	ASSERT_EQ(hit, id)
	bench_pass()
}
