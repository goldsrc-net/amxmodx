// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for what the original The Specialists 3.0 does with a player's powerup each frame: a dead
// player's powerup goes back into the world where he lies, and a running superjump powerup lowers his
// gravity. ../ts_powerup_state.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <amxxbench>

new bool:g_Had[2048]
new Float:g_Corpse[3]

public plugin_init()
{
	register_plugin("TS Powerup State Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_teardown()
{
	// The powerups the dead left behind.
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_powerup")))
		if (ent < sizeof(g_Had) && !g_Had[ent])
			engfunc(EngFunc_RemoveEntity, ent)
}

bool:Near(Float:a, Float:b)
{
	return floatabs(a - b) < 0.01
}

#define ASSERT_NEAR(%0,%1) if (!__near(%0, %1)) return

stock bool:__near(Float:received, Float:expected)
{
	new what[64]
	formatex(what, charsmax(what), "expected %.3f, received %.3f", expected, received)
	return bench_check(Near(received, expected), what)
}

// Notes the powerups already in the world (the map's).
MarkPowerups()
{
	arrayset(g_Had, false, sizeof(g_Had))
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_powerup")))
		if (ent < sizeof(g_Had))
			g_Had[ent] = true
}

// A powerup that was not in the world before, within reach of where the player died.
NewPowerupAtCorpse()
{
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_powerup")))
	{
		if (ent >= sizeof(g_Had) || g_Had[ent])
			continue
		new Float:origin[3]
		pev(ent, pev_origin, origin)
		if (get_distance_f(origin, g_Corpse) < 96.0)
			return ent
	}
	return 0
}

public bool:is_dead(id)
{
	return !is_user_alive(id)
}

public died(id)
{
	pev(id, pev_origin, g_Corpse)
	bench_next("after_death", 0.5, id)
}

public after_death(id)
{
	ASSERT(NewPowerupAtCorpse() != 0)
	bench_pass()
}

// A player who dies with a slow motion running leaves it where he lies.
public test_running_powerup_drops_where_he_dies()
{
	new id = bench_puppet("runner")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "runner_spawned", 20.0, "respawn")
}

public runner_spawned(id)
{
	ts_set_fakeslowmo(id, 10.0)
	bench_next("runner_running", 0.5, id)
}

public runner_running(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), TSPWUP_SLOWMO)
	MarkPowerups()
	user_kill(id)
	bench_wait_until("is_dead", "died", 3.0, id)
}

// So does one who dies holding a powerup he has not used.
public test_held_powerup_drops_where_he_dies()
{
	new id = bench_puppet("holder")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "holder_spawned", 20.0, "respawn")
}

public holder_spawned(id)
{
	bench_next("holder_settled", 0.5, id)
}

public holder_settled(id)
{
	// Just over his head: it lands on him.
	new Float:origin[3]
	pev(id, pev_origin, origin)
	origin[2] += 48.0
	ASSERT(ts_createpwup(TSPWUP_DFIRERATE, origin) > 0)
	bench_wait_message(id, "PwUp", "", "holder_holds", 4.0)
}

public holder_holds(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	MarkPowerups()
	user_kill(id)
	bench_wait_until("is_dead", "died", 3.0, id)
}

// A running superjump powerup, which only a plugin can start, gives low gravity until it ends.
public test_superjump_powerup_lowers_gravity()
{
	new id = bench_puppet("floater")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "floater_spawned", 20.0, "respawn")
}

public floater_spawned(id)
{
	ts_set_fakeslowmo(id, 3.0)
	ts_force_run_powerup(id, TSPWUP_SUPERJUMP)
	bench_next("floater_running", 0.5, id)
}

public floater_running(id)
{
	new Float:gravity
	pev(id, pev_gravity, gravity)
	ASSERT_NEAR(gravity, 0.15)
	bench_next("floater_over", 3.0, id)
}

public floater_over(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	new Float:gravity
	pev(id, pev_gravity, gravity)
	ASSERT_NEAR(gravity, 1.0)
	bench_pass()
}
