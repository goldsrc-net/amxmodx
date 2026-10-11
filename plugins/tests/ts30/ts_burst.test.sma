// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for The Specialists 3.0's burst fire, which reTS has to match: in burst mode PrimaryAttack (@0x71a20) only arms a
// burst on a fresh press (three rounds, two for the UMP) and WeaponIdle (@0x754dc) fires them 0.03 s
// apart, so a press of one frame, a short press and a long hold each fire one whole burst, holding
// on fires no more, and the double fire rate powerup does not turn it into automatic fire (it
// lets the semi modes fire while held).
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsfun>
#include <tsconst>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define M16A4		27

new g_P
new g_EvFire
new g_Shots
new Float:g_First
new Float:g_Last
new g_After[32]

public plugin_precache()
{
	g_EvFire = precache_event(1, "events/fire.sc")
}

public plugin_init()
{
	register_plugin("TS 3.0 Burst Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_forward(FM_PlaybackEvent, "on_event")
}

public bench_setup()
{
	g_P = 0
	g_Shots = 0
}

public on_event(flags, invoker, eventindex)
{
	if (!g_P || invoker != g_P || eventindex != g_EvFire)
		return FMRES_IGNORED
	new Float:now = get_gametime()
	if (g_Shots == 0)
		g_First = now
	g_Last = now
	g_Shots++
	return FMRES_IGNORED
}

// Spawns the shooter with an M16A4 out (its first mode is burst), then calls step(id).
Armed(const name[], const step[])
{
	copy(g_After, charsmax(g_After), step)
	g_P = bench_puppet(name)
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "armed_spawned", 20.0, "respawn")
}

public armed_spawned(id)
{
	ts_giveweapon(id, M16A4, 60, 0)
	// past the spawn protection, with the gun out
	bench_next(g_After, 1.5, id)
}

// Holds attack for `secs`, then lets go and calls step(id) a second later.
Hold(id, Float:secs, const step[])
{
	copy(g_After, charsmax(g_After), step)
	g_Shots = 0
	bench_puppet_input(id, IN_ATTACK)
	bench_next("released", secs, id)
}

public released(id)
{
	bench_puppet_input(id, 0)
	bench_next(g_After, 1.0, id)
}

Report(const what[])
{
	new clip, ammo, mode, extra
	ts_getuserwpn(g_P, clip, ammo, mode, extra)
	server_print("ts_burst: %s: %d rounds over %.3f s (mode %d)", what, g_Shots, g_Last - g_First, mode)
}

// A short press fires the whole burst.
public test_short_press_fires_a_whole_burst()
{
	Armed("burstshort", "short_ready")
}

public short_ready(id)
{
	Hold(id, 0.2, "short_fired")
}

public short_fired(id)
{
	Report("0.2 s press")
	ASSERT_EQ(g_Shots, 3)
	bench_pass()
}

// Holding on fires one burst only.
public test_held_trigger_fires_one_burst()
{
	Armed("burstheld", "held_ready")
}

public held_ready(id)
{
	Hold(id, 1.5, "held_fired")
}

public held_fired(id)
{
	Report("1.5 s hold")
	ASSERT_EQ(g_Shots, 3)
	bench_pass()
}

// A press of a single frame (0.01 s at the bench's time scale) fires the whole burst.
public test_frame_press_fires_a_whole_burst()
{
	Armed("burstframe", "frame_ready")
}

public frame_ready(id)
{
	Hold(id, 0.01, "frame_fired")
}

public frame_fired(id)
{
	Report("0.01 s press")
	ASSERT_EQ(g_Shots, 3)
	bench_pass()
}

// With the double fire rate powerup a held trigger still fires one burst.
public test_double_fire_rate_keeps_the_burst()
{
	Armed("burstdouble", "double_ready")
}

public double_ready(id)
{
	ts_force_run_powerup(id, TSPWUP_DFIRERATE)
	Hold(id, 1.5, "double_fired")
}

public double_fired(id)
{
	Report("1.5 s hold, double fire rate")
	ASSERT_EQ(g_Shots, 3)
	bench_pass()
}
