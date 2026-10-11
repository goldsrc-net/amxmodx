// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the shooter's pev->weaponanim when The Specialists 3.0 fires a gun, which reTS has to
// match: StandardFire (@0x724a4), ShotgunFire (@0x72108) and AkimboFire (@0x729c0) call no
// SendWeaponAnim, so the shot leaves weaponanim at the draw or idle animation. The shoot animation is
// the client's, from events/fire.sc. The client data carries weaponanim, and a client that predicts
// its shot replays the server's value when the two differ.
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
#define BENELLIM3	4
#define AUG			15

new g_P
new g_EvFire
new g_EvLinked
new g_Shots
new g_Changed
new g_Before
new g_After[32]
new g_Weapon
new g_Count

public plugin_precache()
{
	g_EvFire = precache_event(1, "events/fire.sc")
	g_EvLinked = precache_event(1, "events/firelinked.sc")
}

public plugin_init()
{
	register_plugin("TS Fire Weaponanim Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_forward(FM_PlaybackEvent, "on_event")
}

public bench_setup()
{
	g_P = 0
	g_Shots = 0
	g_Changed = 0
	g_Before = -1
}

// Each fire event the shooter sends, with his weaponanim at that moment.
public on_event(flags, invoker, eventindex, Float:delay, Float:origin[3], Float:angles[3],
	Float:fparam1, Float:fparam2, iparam1, iparam2, bparam1, bparam2)
{
	if (!g_P || invoker != g_P || g_Before < 0)
		return FMRES_IGNORED
	if (eventindex != g_EvFire && eventindex != g_EvLinked)
		return FMRES_IGNORED
	g_Shots++
	new anim = pev(invoker, pev_weaponanim)
	if (anim != g_Before)
	{
		g_Changed++
		server_print("ts_fire_weaponanim: weapon %d shot %d: weaponanim %d, %d before the press",
			iparam1, g_Shots, anim, g_Before)
	}
	return FMRES_IGNORED
}

// Spawns the shooter and gives him weapon count times, then calls step(id) with it out.
Armed(const name[], weapon, count, const step[])
{
	copy(g_After, charsmax(g_After), step)
	g_Weapon = weapon
	g_Count = count
	g_P = bench_puppet(name)
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "armed_spawned", 20.0, "respawn")
}

public armed_spawned(id)
{
	for (new i = 0; i < g_Count; i++)
		ts_giveweapon(id, g_Weapon, 30, 0)
	// past the spawn protection and the draw, with the gun out
	bench_next("armed_fire", 1.5, id)
}

// Notes weaponanim, holds fire for 0.6 s, then calls the step.
public armed_fire(id)
{
	g_Shots = 0
	g_Changed = 0
	g_Before = pev(id, pev_weaponanim)
	bench_puppet_input(id, IN_ATTACK)
	bench_next("released", 0.6, id)
}

public released(id)
{
	bench_puppet_input(id, 0)
	bench_next(g_After, 0.1, id)
}

Report(const what[])
{
	server_print("ts_fire_weaponanim: %s: %d shots, weaponanim %d before, %d shots changed it",
		what, g_Shots, g_Before, g_Changed)
}

// A Glock 18's shot (StandardFire).
public test_standard_shot_keeps_weaponanim()
{
	Armed("glockanim", GLOCK18, 1, "glock_fired")
}

public glock_fired(id)
{
	Report("glock 18")
	ASSERT(g_Shots > 0)
	ASSERT_EQ(g_Changed, 0)
	bench_pass()
}

// A Steyr AUG's shots (StandardFire, full auto).
public test_aug_shots_keep_weaponanim()
{
	Armed("auganim", AUG, 1, "aug_fired")
}

public aug_fired(id)
{
	Report("steyr aug")
	ASSERT(g_Shots > 0)
	ASSERT_EQ(g_Changed, 0)
	bench_pass()
}

// A Benelli M3's shot (ShotgunFire).
public test_shotgun_shot_keeps_weaponanim()
{
	Armed("pumpanim", BENELLIM3, 1, "pump_fired")
}

public pump_fired(id)
{
	Report("benelli m3")
	ASSERT(g_Shots > 0)
	ASSERT_EQ(g_Changed, 0)
	bench_pass()
}

// Akimbo Berettas (two Berettas) on the right trigger (AkimboFire).
public test_akimbo_shot_keeps_weaponanim()
{
	Armed("akimboanim", BERETTA, 2, "akimbo_fired")
}

public akimbo_fired(id)
{
	Report("akimbo berettas")
	ASSERT(g_Shots > 0)
	ASSERT_EQ(g_Changed, 0)
	bench_pass()
}
