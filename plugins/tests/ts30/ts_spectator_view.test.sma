// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for where The Specialists 3.0's player movement puts a spectator: PM_SpectatorMove
// (@0xeef3c) moves a chasing spectator (modes 1 and 2) behind his target, 90 units back from 35
// above the target's origin unless a wall is nearer (GetChaseOrigin @0xeee5c), and one watching
// through the target's eyes (mode 5) onto the target's origin.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <amxxbench>

#define TS_OBS_LOCKED	1
#define TS_OBS_CHASE	2
#define TS_OBS_EYES	5

new g_Target
new g_Spec

public plugin_init()
{
	register_plugin("TS 3.0 Spectator View Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bool:is_dead(id)
{
	return !is_user_alive(id)
}

// How far the spectator is from his target's origin, and from 35 above it.
Float:Away(id, &Float:fromEye)
{
	new Float:a[3], Float:b[3]
	pev(id, pev_origin, a)
	pev(pev(id, pev_iuser2), pev_origin, b)
	new Float:d = get_distance_f(a, b)
	b[2] += 35.0
	fromEye = get_distance_f(a, b)
	return d
}

// A joiner chases a live player (mode 2), then jump takes him to the locked chase (1), then to the
// eyes (5).
public test_spectator_sits_behind_or_in_his_target()
{
	g_Target = bench_puppet("viewed")
	ASSERT(g_Target > 0)
	bench_puppet_spawn(g_Target, "viewed_alive", 20.0, "respawn")
}

public viewed_alive(target)
{
	g_Spec = bench_puppet("viewer")
	ASSERT(g_Spec > 0)
	bench_wait_until("is_dead", "viewer_spectating", 2.0, g_Spec)
}

public viewer_spectating(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), TS_OBS_CHASE)
	ASSERT_EQ(pev(id, pev_iuser2), g_Target)
	// a few moves to settle
	bench_next("viewer_chasing", 0.5, id)
}

public viewer_chasing(id)
{
	new Float:eye, Float:d = Away(id, eye)
	server_print("ts_spectator_view: mode %d, %.1f from the target, %.1f from 35 above it",
		pev(id, pev_iuser1), d, eye)
	ASSERT(d > 8.0)
	ASSERT(eye <= 94.5)
	bench_puppet_press(id, IN_JUMP, "viewer_locked")
}

public viewer_locked(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), TS_OBS_LOCKED)
	g_Presses = 0
	bench_next("viewer_locked_settled", 0.5, id)
}

public viewer_locked_settled(id)
{
	new Float:eye, Float:d = Away(id, eye)
	server_print("ts_spectator_view: mode %d, %.1f from the target, %.1f from 35 above it",
		pev(id, pev_iuser1), d, eye)
	ASSERT(d > 8.0)
	ASSERT(eye <= 94.5)
	bench_puppet_press(id, IN_JUMP, "viewer_eyes")
}

// Jump goes on round the modes (3, 2, 1, 5); with other players about it can land elsewhere, so it
// is pressed again, a few times at most, until the eyes come up.
new g_Presses

public viewer_eyes(id)
{
	if (pev(id, pev_iuser1) != TS_OBS_EYES && ++g_Presses < 6)
	{
		bench_next("viewer_press_again", 0.3, id)
		return
	}
	ASSERT_EQ(pev(id, pev_iuser1), TS_OBS_EYES)
	bench_next("viewer_eyes_settled", 0.5, id)
}

public viewer_press_again(id)
{
	bench_puppet_press(id, IN_JUMP, "viewer_eyes")
}

public viewer_eyes_settled(id)
{
	new Float:eye, Float:d = Away(id, eye)
	server_print("ts_spectator_view: mode %d, %.1f from the target", pev(id, pev_iuser1), d)
	ASSERT(d < 1.0)
	bench_pass()
}
