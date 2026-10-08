// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the original The Specialists 3.0's spectators: a joiner chases a player (observer mode
// 2) and keeps that mode after dying, a joiner in last man standing is told the round clock, and a
// spectator's pose (TSState) is not refreshed. The observer controls: jump cycles the mode, forward
// watches the next player, a dead target is replaced, and with nobody to watch the spectator roams
// without a message. ../ts_observer.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <amxxbench>

#define OBS_CHASE_LOCKED	1
#define OBS_CHASE_FREE	2
#define OBS_ROAMING	3

new g_Map[32]
new g_Helper
new g_Helper2
new g_Target
new g_Step[32]
new g_Lms
new g_RoundTime
new BenchMsg:g_Mark

public plugin_init()
{
	register_plugin("TS Observer Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	get_mapname(g_Map, charsmax(g_Map))
}

public bool:is_dead(id)
{
	return !is_user_alive(id)
}

public bool:spectating(id)
{
	return pev(id, pev_iuser1) != 0
}

// A chased player is someone else who is alive.
bool:ChasesAPlayer(id)
{
	new target = pev(id, pev_iuser2)
	return target > 0 && target <= get_maxplayers() && target != id && is_user_alive(target)
}

// StartObserver uses the mode StopObserver last saved, or 2 (chase) when there is none; a joiner
// has none, so with someone alive to watch he chases him.
public test_joiner_chases_a_player()
{
	g_Helper = bench_puppet("chased")
	ASSERT(g_Helper > 0)
	bench_puppet_spawn(g_Helper, "chased_alive", 20.0, "respawn")
}

public chased_alive(helper)
{
	new id = bench_puppet("chaser")
	ASSERT(id > 0)
	bench_wait_until("is_dead", "chaser_spectating", 2.0, id)
}

public chaser_spectating(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	ASSERT(ChasesAPlayer(id))
	bench_pass()
}

// StopObserver keeps the mode he spectated in, so after a life he chases again.
public test_mode_holds_after_a_life()
{
	g_Helper = bench_puppet("watched")
	ASSERT(g_Helper > 0)
	bench_puppet_spawn(g_Helper, "watched_alive", 20.0, "respawn")
}

public watched_alive(helper)
{
	new id = bench_puppet("watcher")
	ASSERT(id > 0)
	bench_wait_until("is_dead", "watcher_joined", 2.0, id)
}

public watcher_joined(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	bench_puppet_spawn(id, "watcher_spawned", 20.0, "respawn")
}

public watcher_spawned(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), 0)
	user_kill(id)
	bench_wait_until("spectating", "watcher_spectating", 10.0, id)
}

public watcher_spectating(id)
{
	ASSERT(is_user_alive(g_Helper))
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	ASSERT(ChasesAPlayer(id))
	bench_pass()
}

// InitHUD sends a joiner the round clock (RoundTime: seconds left, 0) whenever a round is running,
// in any game mode. Last man standing is the round mode whose rules are not teamplay.
public bench_teardown()
{
	if (g_Lms)
	{
		set_cvar_num("lastmanstanding", 0)
		set_cvar_num("roundtime", g_RoundTime)
	}
}

public test_lms_joiner_gets_the_round_clock()
{
	bench_set_timeout(120.0)
	g_Lms = 1
	g_RoundTime = get_cvar_num("roundtime")
	set_cvar_num("lastmanstanding", 1)
	set_cvar_num("roundtime", 180)
	bench_change_map(g_Map, "lms_map")
}

public lms_map()
{
	g_Helper = bench_puppet("lmsfirst")
	ASSERT(g_Helper > 0)
	// The first round starts five seconds into the map, with a RoundTime to everyone.
	bench_wait_message(g_Helper, "RoundTime", "", "lms_round", 15.0)
}

public lms_round(helper)
{
	new BenchMsg:msg = bench_msg_last(helper, "RoundTime")
	server_print("ts_observer: round started, %d s", bench_msg_int(msg, 0))
	bench_next("lms_join", 1.0)
}

public lms_join()
{
	new id = bench_puppet("lmsjoiner")
	ASSERT(id > 0)
	g_Mark = bench_msg_last(id, "RoundTime")
	bench_next("lms_joined", 1.0, id)
}

public lms_joined(id)
{
	// Put the map back first, so a failure leaves the next tests on the usual rules. Plugins
	// reload on the map change, so the clock travels as the step's data: seconds left * 256 +
	// the flag byte, or -1 for none.
	new BenchMsg:msg = bench_msg_next(id, g_Mark, "RoundTime")
	new clock = msg != BenchMsg:0 ? bench_msg_int(msg, 0) * 256 + bench_msg_int(msg, 1) : -1
	set_cvar_num("lastmanstanding", 0)
	set_cvar_num("roundtime", g_RoundTime)
	g_Lms = 0
	bench_change_map(g_Map, "lms_restored", clock)
}

public lms_restored(clock)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_observer: joiner's RoundTime %d, %d", clock >> 8, clock & 255)
	ASSERT(clock != -1)
	ASSERT((clock >> 8) > 150 && (clock >> 8) <= 180)
	ASSERT_EQ(clock & 255, 0)
	bench_pass()
}

// A ducking player in play is sent his pose (TSState 1).
public test_ducking_player_sends_his_pose()
{
	new id = bench_puppet("croucher")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "croucher_alive", 20.0, "respawn")
}

public croucher_alive(id)
{
	g_Mark = bench_msg_last(id, "TSState")
	bench_puppet_input(id, IN_DUCK)
	bench_next("croucher_ducked", 1.0, id)
}

public croucher_ducked(id)
{
	bench_puppet_input(id, 0)
	ASSERT(pev(id, pev_flags) & FL_DUCKING)
	ASSERT(PoseSent(id, 1))
	bench_pass()
}

bool:PoseSent(id, pose)
{
	new BenchMsg:msg = g_Mark
	while ((msg = bench_msg_next(id, msg, "TSState")) != BenchMsg:0)
		if (bench_msg_int(msg, 0) == pose)
			return true
	return false
}

// The pose is refreshed only for a live player in play, so a spectator's stays as it was.
public test_spectator_pose_is_not_refreshed()
{
	new id = bench_puppet("posed")
	ASSERT(id > 0)
	bench_wait_until("is_dead", "posed_spectating", 2.0, id)
}

public posed_spectating(id)
{
	ASSERT(spectating(id))
	g_Mark = bench_msg_last(id, "TSState")
	set_pev(id, pev_flags, pev(id, pev_flags) | FL_DUCKING)
	bench_next("posed_later", 0.5, id)
}

public posed_later(id)
{
	ASSERT(pev(id, pev_flags) & FL_DUCKING)
	ASSERT_FALSE(PoseSent(id, 1))
	set_pev(id, pev_flags, pev(id, pev_flags) & ~FL_DUCKING)
	bench_pass()
}

// The other live helper, or 0.
OtherHelper(target)
{
	return target == g_Helper ? g_Helper2 : (target == g_Helper2 ? g_Helper : 0)
}

// Two live players and a spectator chasing one of them.
StartTwoAndASpectator(const step[])
{
	copy(g_Step, charsmax(g_Step), step)
	g_Helper = bench_puppet("watchone")
	ASSERT(g_Helper > 0)
	bench_puppet_spawn(g_Helper, "first_alive", 20.0, "respawn")
}

public first_alive(helper)
{
	g_Helper2 = bench_puppet("watchtwo")
	ASSERT(g_Helper2 > 0)
	bench_puppet_spawn(g_Helper2, "second_alive", 20.0, "respawn")
}

public second_alive(helper)
{
	new id = bench_puppet("spec")
	ASSERT(id > 0)
	bench_wait_until("is_dead", g_Step, 2.0, id)
}

// Jump steps the mode: chase (2) to locked chase (1).
public test_jump_cycles_the_mode()
{
	StartTwoAndASpectator("jumper_spectating")
}

public jumper_spectating(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	bench_puppet_press(id, IN_JUMP, "jumper_pressed")
}

public jumper_pressed(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_LOCKED)
	ASSERT(OtherHelper(pev(id, pev_iuser2)) != 0)
	bench_pass()
}

// Forward moves to the next player.
public test_forward_watches_the_next_player()
{
	StartTwoAndASpectator("forward_spectating")
}

public forward_spectating(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	g_Target = pev(id, pev_iuser2)
	ASSERT(OtherHelper(g_Target) != 0)
	bench_puppet_press(id, IN_FORWARD, "forward_pressed")
}

public forward_pressed(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	ASSERT_EQ(pev(id, pev_iuser2), OtherHelper(g_Target))
	bench_pass()
}

// When the watched player dies, the spectator moves on to someone alive.
public test_dead_target_is_replaced()
{
	StartTwoAndASpectator("idle_spectating")
}

public idle_spectating(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	g_Target = pev(id, pev_iuser2)
	ASSERT(OtherHelper(g_Target) != 0)
	user_kill(g_Target)
	bench_wait_until("target_moved", "idle_moved", 4.0, id)
}

public bool:target_moved(id)
{
	return pev(id, pev_iuser2) != g_Target
}

public idle_moved(id)
{
	ASSERT(!is_user_alive(g_Target))
	ASSERT_EQ(pev(id, pev_iuser2), OtherHelper(g_Target))
	ASSERT(is_user_alive(OtherHelper(g_Target)))
	bench_pass()
}

// With nobody alive to watch, a joiner roams (mode 3, max speed 420) and is told nothing.
public test_nobody_to_watch_roams_silently()
{
	new id = bench_puppet("loner")
	ASSERT(id > 0)
	bench_wait_until("is_dead", "loner_spectating", 2.0, id)
}

public loner_spectating(id)
{
	bench_next("loner_later", 0.5, id)
}

public loner_later(id)
{
	new Float:speed
	pev(id, pev_maxspeed, speed)
	server_print("ts_observer: loner mode %d, max speed %.1f, #Spec messages %d", pev(id, pev_iuser1),
		speed, bench_msg_count(id, "", "#Spec_"))
	ASSERT_EQ(pev(id, pev_iuser1), OBS_ROAMING)
	ASSERT_EQ(pev(id, pev_iuser2), 0)
	ASSERT(speed == 420.0)
	ASSERT_EQ(bench_msg_count(id, "", "#Spec_"), 0)
	bench_pass()
}
