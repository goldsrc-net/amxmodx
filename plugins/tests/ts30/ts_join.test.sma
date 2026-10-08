// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for how the original The Specialists 3.0 brings a player in: he joins alive and goes to
// spectate on his first frame, the spawn shimmer stays on him while he spectates, and the game never
// writes his pev_team. ../ts_join.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <amxxbench>

public plugin_init()
{
	register_plugin("TS Join Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bool:is_dead(id)
{
	return !is_user_alive(id)
}

// ClientPutInServer only spawns him; the game's InitHUD, on his first frame, puts him in spectate.
public test_joiner_is_alive_until_his_first_frame()
{
	new id = bench_puppet("joiner")
	ASSERT(id > 0)
	ASSERT(is_user_alive(id))
	ASSERT_EQ(pev(id, pev_deadflag), DEAD_NO)
	new Float:health
	pev(id, pev_health, health)
	ASSERT_EQ(floatround(health), 100)
	ASSERT_EQ(pev(id, pev_iuser1), 0)
	bench_wait_until("is_dead", "joiner_spectating", 2.0, id)
}

public joiner_spectating(id)
{
	ASSERT_EQ(pev(id, pev_deadflag), DEAD_RESPAWNABLE)
	ASSERT(pev(id, pev_iuser1) != 0)
	bench_pass()
}

// Spawn protection shows as a steady translucency (render fx 14) for a second; a player who
// spectates keeps it, since the game clears it past the spectator's part of the frame.
public test_joiner_keeps_the_spawn_shimmer()
{
	new id = bench_puppet("shimmer")
	ASSERT(id > 0)
	bench_next("shimmer_spectating", 3.0, id)
}

public shimmer_spectating(id)
{
	ASSERT(!is_user_alive(id))
	ASSERT_EQ(pev(id, pev_rendermode), kRenderTransColor)
	ASSERT_EQ(pev(id, pev_renderfx), kRenderFxNoDissipation)
	new Float:amt
	pev(id, pev_renderamt, amt)
	ASSERT_EQ(floatround(amt), 125)
	bench_pass()
}

public test_shimmer_ends_a_second_after_spawning()
{
	new id = bench_puppet("unshimmer")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "unshimmer_spawned", 20.0, "respawn")
}

public unshimmer_spawned(id)
{
	ASSERT_EQ(pev(id, pev_renderfx), kRenderFxNoDissipation)
	bench_next("unshimmer_later", 1.5, id)
}

public unshimmer_later(id)
{
	ASSERT_EQ(pev(id, pev_rendermode), kRenderNormal)
	ASSERT_EQ(pev(id, pev_renderfx), kRenderFxNone)
	bench_pass()
}

// The game keeps a player's team elsewhere; pev_team stays what it was, through the join, the
// spawn, a death and the spectating after it, and jointeam (a team change in teamplay).
public test_team_is_never_written()
{
	new id = bench_puppet("teamless")
	ASSERT(id > 0)
	set_pev(id, pev_team, 7)
	bench_next("teamless_joined", 0.5, id)
}

public teamless_joined(id)
{
	ASSERT_EQ(pev(id, pev_team), 7)
	bench_puppet_spawn(id, "teamless_spawned", 20.0, "respawn")
}

public teamless_spawned(id)
{
	ASSERT_EQ(pev(id, pev_team), 7)
	user_kill(id)
	bench_wait_until("spectating", "teamless_spectating", 10.0, id)
}

public bool:spectating(id)
{
	return pev(id, pev_iuser1) != 0
}

public teamless_spectating(id)
{
	ASSERT_EQ(pev(id, pev_team), 7)
	bench_puppet_cmd(id, "jointeam 1")
	bench_next("teamless_joined_team", 0.5, id)
}

public teamless_joined_team(id)
{
	ASSERT_EQ(pev(id, pev_team), 7)
	bench_pass()
}
