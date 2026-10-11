// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the fire events The Specialists 3.0 sends with each shot, which reTS has to match:
// events/fire.sc and events/firelinked.sc carry the shot's spread in both fparam1 and fparam2
// (StandardFire @0x728cd, ShotgunFire @0x72405, AkimboFire @0x7321e push it twice). The client's
// fire core spreads the pellets across by fparam1 and up by fparam2, and kicks the aim from its own
// prediction.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1
#define BERETTA		2
#define UZI			3
#define BENELLIM3	4

new g_P
new g_EvFire
new g_EvLinked
new g_Shots[2]
new g_Mismatch
new g_Zero
new Float:g_Spread[2]
new g_After[32]
new g_Weapon

public plugin_precache()
{
	g_EvFire = precache_event(1, "events/fire.sc")
	g_EvLinked = precache_event(1, "events/firelinked.sc")
}

public plugin_init()
{
	register_plugin("TS 3.0 Fire Event Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_forward(FM_PlaybackEvent, "on_event")
}

public bench_setup()
{
	g_P = 0
	g_Shots[0] = g_Shots[1] = 0
	g_Mismatch = 0
	g_Zero = 0
	g_Spread[0] = g_Spread[1] = 0.0
}

// Each fire event the shooter sends: counted by kind, with any whose fparam2 is not its fparam1.
public on_event(flags, invoker, eventindex, Float:delay, Float:origin[3], Float:angles[3],
	Float:fparam1, Float:fparam2, iparam1, iparam2, bparam1, bparam2)
{
	if (!g_P || invoker != g_P)
		return FMRES_IGNORED
	new kind = -1
	if (eventindex == g_EvFire)
		kind = 0
	else if (eventindex == g_EvLinked)
		kind = 1
	if (kind < 0)
		return FMRES_IGNORED
	if (g_Shots[kind] == 0)
		g_Spread[kind] = fparam1
	g_Shots[kind]++
	if (fparam2 != fparam1)
	{
		g_Mismatch++
		server_print("ts_fire_event: %s weapon %d fparam1 %f fparam2 %f",
			kind ? "firelinked.sc" : "fire.sc", iparam1, fparam1, fparam2)
	}
	if (fparam1 <= 0.0)
		g_Zero++
	return FMRES_IGNORED
}

// Spawns the shooter and gives him weapon count times, then calls step(id) with it out.
Armed(const name[], weapon, count, const step[])
{
	copy(g_After, charsmax(g_After), step)
	g_Weapon = weapon
	g_Shots[1] = count
	g_P = bench_puppet(name)
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "armed_spawned", 20.0, "respawn")
}

public armed_spawned(id)
{
	new count = g_Shots[1]
	g_Shots[1] = 0
	for (new i = 0; i < count; i++)
		ts_giveweapon(id, g_Weapon, 30, 0)
	// past the spawn protection, with the gun out
	bench_next(g_After, 1.5, id)
}

// Holds buttons for 0.6 s, then calls step(id).
Hold(id, buttons, const step[])
{
	copy(g_After, charsmax(g_After), step)
	g_Shots[0] = g_Shots[1] = 0
	bench_puppet_input(id, buttons)
	bench_next("released", 0.6, id)
}

public released(id)
{
	bench_puppet_input(id, 0)
	bench_next(g_After, 0.1, id)
}

Report(const what[])
{
	server_print("ts_fire_event: %s: fire.sc %d (spread %f), firelinked.sc %d (spread %f), %d with fparam2 other than fparam1",
		what, g_Shots[0], g_Spread[0], g_Shots[1], g_Spread[1], g_Mismatch)
}

// A Glock 18's shot (StandardFire).
public test_standard_shot_sends_the_spread_twice()
{
	Armed("glockshot", GLOCK18, 1, "glock_ready")
}

public glock_ready(id)
{
	Hold(id, IN_ATTACK, "glock_fired")
}

public glock_fired(id)
{
	Report("glock 18")
	ASSERT(g_Shots[0] > 0)
	ASSERT_EQ(g_Mismatch, 0)
	ASSERT_EQ(g_Zero, 0)
	bench_pass()
}

// A Benelli M3's shot (ShotgunFire, the pump shotgun).
public test_shotgun_shot_sends_the_spread_twice()
{
	Armed("pumpshot", BENELLIM3, 1, "pump_ready")
}

public pump_ready(id)
{
	Hold(id, IN_ATTACK, "pump_fired")
}

public pump_fired(id)
{
	Report("benelli m3")
	ASSERT(g_Shots[0] > 0)
	ASSERT_EQ(g_Mismatch, 0)
	ASSERT_EQ(g_Zero, 0)
	bench_pass()
}

// Akimbo Berettas (two Berettas) on the right trigger (AkimboFire).
public test_akimbo_shot_sends_the_spread_twice()
{
	Armed("akimboshot", BERETTA, 2, "akimbo_ready")
}

public akimbo_ready(id)
{
	Hold(id, IN_ATTACK, "akimbo_fired")
}

public akimbo_fired(id)
{
	Report("akimbo berettas")
	ASSERT(g_Shots[0] + g_Shots[1] > 0)
	ASSERT_EQ(g_Mismatch, 0)
	ASSERT_EQ(g_Zero, 0)
	bench_pass()
}

// Akimbo Uzis (two Uzis) with both triggers held: the both-barrels shot, events/firelinked.sc.
public test_linked_shot_sends_the_spread_twice()
{
	Armed("linkedshot", UZI, 2, "linked_ready")
}

public linked_ready(id)
{
	Hold(id, IN_ATTACK | IN_ATTACK2, "linked_fired")
}

public linked_fired(id)
{
	Report("akimbo uzis")
	ASSERT(g_Shots[1] > 0)
	ASSERT_EQ(g_Mismatch, 0)
	ASSERT_EQ(g_Zero, 0)
	bench_pass()
}
