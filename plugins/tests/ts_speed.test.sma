// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for a plugin's move speed on The Specialists. The game sets a player's speed from what he
// carries only when that changes (a pickup, a drop, armor, the flag, a throw), so a maxspeed a plugin
// sets holds until then. Runs on reTS and on the original The Specialists 3.0 alike.
//

#include <amxmodx>
#include <fakemeta>
#include <fun>
#include <tsx>
#include <tsfun>
#include <amxxbench>

#define GLOCK18		1

new Float:g_Until
new Float:g_Fastest

public plugin_init()
{
	register_plugin("TS Speed Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

Float:GroundSpeed(id)
{
	new Float:velocity[3]
	pev(id, pev_velocity, velocity)
	return floatsqroot(velocity[0] * velocity[0] + velocity[1] * velocity[1])
}

public test_plugin_maxspeed_holds()
{
	new id = bench_puppet("walker")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "walker_spawned", 20.0, "respawn")
}

public walker_spawned(id)
{
	bench_next("walker_ready", 1.0, id)
}

public walker_ready(id)
{
	set_user_maxspeed(id, 250.0)
	bench_puppet_input(id, 0, 400.0)
	g_Fastest = 0.0
	g_Until = get_gametime() + 0.6
	bench_wait_until("walker_running", "walker_ran", 2.0, id)
}

public walker_running(id)
{
	g_Fastest = floatmax(g_Fastest, GroundSpeed(id))
	return get_gametime() >= g_Until
}

public walker_ran(id)
{
	bench_puppet_input(id, 0)
	new Float:maxspeed
	pev(id, pev_maxspeed, maxspeed)
	ASSERT_EQ(floatround(maxspeed), 250)
	// Moving, and no faster than the plugin's speed.
	ASSERT(g_Fastest > 200.0)
	ASSERT(g_Fastest < 260.0)
	bench_pass()
}

public test_a_pickup_sets_the_speed_again()
{
	new id = bench_puppet("picker")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "picker_spawned", 20.0, "respawn")
}

public picker_spawned(id)
{
	set_user_maxspeed(id, 250.0)
	ts_giveweapon(id, GLOCK18, 0, 0)
	// The pickup puts the speed back to what the player's load allows.
	new Float:maxspeed
	pev(id, pev_maxspeed, maxspeed)
	ASSERT(maxspeed > 250.0)
	bench_pass()
}
