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
// 2) and keeps that mode after dying, and a spectator's pose (TSState) is not refreshed. The observer controls: jump cycles the mode, forward
// watches the next player, a dead target is replaced, and with nobody to watch the spectator roams
// without a message. The spectate block clears the impulse, a spectator back from play watches his
// old target again, and a team change does not reset the controls' clock. A player leaving spectate
// is announced (Spectator idx 0) only if he was watching (iuser1 or iuser2 set), and the "respawn"
// command takes only a player in a spectator mode (iuser1 set). Spectating does not hide the HUD,
// nor any part of it. Leaving spectate keeps iuser3. A joiner in last man standing is told the
// round clock.
// ../ts_observer.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386) patched with amxxbench's tests/patch-ts30.py: on
// an unpatched TS 3.0 each free-for-all last man standing round start corrupts the server's heap.
// run.sh --tests plugins/tests/ts30 stock
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
	register_forward(FM_PlayerPostThink, "on_post_think")
	register_message(get_user_msgid("Spectator"), "on_spectator")
	register_message(get_user_msgid("HideWeapon"), "on_hide_weapon")
}

new g_Leaver
new g_Announced
new Float:g_Until

// Spectator (idx, 0) to everyone for g_Leaver: he is announced out of spectate.
public on_spectator(msgid, dest, ent)
{
	if (g_Leaver && (dest == MSG_ALL || dest == MSG_BROADCAST) && get_msg_arg_int(1) == g_Leaver
		&& get_msg_arg_int(2) == 0)
		g_Announced++
	return PLUGIN_CONTINUE
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

// The spectate block clears the impulse a spectator sends, as it ends (after the observer controls).
new g_Impulser
new g_Impulses

public on_post_think(id)
{
	if (id == g_Impulser && g_Impulser && pev(id, pev_impulse) != 0)
		g_Impulses++
	return FMRES_IGNORED
}

public test_spectator_impulse_is_cleared()
{
	new id = bench_puppet("impulser")
	ASSERT(id > 0)
	bench_wait_until("is_dead", "impulser_spectating", 2.0, id)
}

public impulser_spectating(id)
{
	ASSERT(spectating(id))
	g_Impulses = 0
	g_Impulser = id
	bench_puppet_input(id, 0, 0.0, 0.0, 0.0, 55)
	bench_next("impulser_later", 0.3, id)
}

public impulser_later(id)
{
	bench_puppet_input(id, 0)
	g_Impulser = 0
	// whoever gets the slot next starts without it
	set_pev(id, pev_impulse, 0)
	server_print("ts_observer: impulse left after the think %d times", g_Impulses)
	ASSERT_EQ(g_Impulses, 0)
	bench_pass()
}

// A spectator who goes into play keeps the player he watched: back in spectate he watches him again
// (here the second of two, where looking afresh would find the first).
public test_returning_spectator_watches_his_old_target()
{
	StartTwoAndASpectator("return_spectating")
}

public return_spectating(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	ASSERT(g_Helper < g_Helper2)
	if (pev(id, pev_iuser2) == g_Helper2)
	{
		return_target(id)
		return
	}
	bench_puppet_press(id, IN_FORWARD, "return_target")
}

public return_target(id)
{
	ASSERT_EQ(pev(id, pev_iuser2), g_Helper2)
	bench_puppet_spawn(id, "return_playing", 20.0, "respawn")
}

public return_playing(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), 0)
	user_kill(id)
	bench_wait_until("spectating", "return_back", 10.0, id)
}

public return_back(id)
{
	server_print("ts_observer: back in mode %d watching %d (helpers %d, %d)", pev(id, pev_iuser1),
		pev(id, pev_iuser2), g_Helper, g_Helper2)
	ASSERT(is_user_alive(g_Helper2))
	ASSERT_EQ(pev(id, pev_iuser2), g_Helper2)
	bench_pass()
}

// Going to spectate again (a team change, in teamplay) does not reset the controls' 0.2 s clock:
// jump pressed again at once does nothing. (The server is put in teamplay for the test if it is
// not; the flag travels as the step's data, plugin variables start over on the map change.)
new g_TeamChanged
new g_OldTeam[32]

public test_team_change_keeps_the_jump_clock()
{
	bench_set_timeout(120.0)
	if (get_cvar_num("mp_teamplay"))
	{
		clock_team_map(0)
		return
	}
	set_cvar_num("mp_teamplay", 1)
	bench_change_map(g_Map, "clock_team_map", 1)
}

public clock_team_map(changed)
{
	g_TeamChanged = changed
	g_Helper = bench_puppet("clockhelper")
	ASSERT(g_Helper > 0)
	bench_puppet_spawn(g_Helper, "clock_helper_alive", 20.0, "respawn")
}

public clock_helper_alive(helper)
{
	new id = bench_puppet("clockspec")
	ASSERT(id > 0)
	bench_wait_until("is_dead", "clock_spectating", 2.0, id)
}

public clock_spectating(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	bench_puppet_press(id, IN_JUMP, "clock_jumped")
}

public clock_jumped(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_LOCKED)
	// another team: the first, or the second if he is on the first (jointeam counts from 1)
	get_user_team(id, g_OldTeam, charsmax(g_OldTeam))
	bench_puppet_cmd(id, "jointeam 1")
	bench_next("clock_joined", 0.0, id)
}

public clock_joined(id)
{
	new team[32]
	get_user_team(id, team, charsmax(team))
	if (equal(team, g_OldTeam))
		bench_puppet_cmd(id, "jointeam 2")
	bench_next("clock_moved", 0.0, id)
}

public clock_moved(id)
{
	new team[32]
	get_user_team(id, team, charsmax(team))
	server_print("ts_observer: now team %s, mode %d", team, pev(id, pev_iuser1))
	// StartObserver put him back in chase
	ASSERT_EQ(pev(id, pev_iuser1), OBS_CHASE_FREE)
	bench_puppet_press(id, IN_JUMP, "clock_jumped_again")
}

public clock_jumped_again(id)
{
	new mode = pev(id, pev_iuser1)
	if (!g_TeamChanged)
	{
		clock_restored(mode)
		return
	}
	set_cvar_num("mp_teamplay", 0)
	bench_change_map(g_Map, "clock_restored", mode)
}

public clock_restored(mode)
{
	server_print("ts_observer: mode after the second jump %d", mode)
	ASSERT_EQ(mode, OBS_CHASE_FREE)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Leaving spectate ("respawn" once the respawn wait is over), a spectator is announced to everyone
// (Spectator idx, 0). One whose iuser1 and iuser2 have been cleared is not, as the command takes
// only a player with iuser1 set: he stays out of play.

public test_unwatching_spectator_is_not_announced()
{
	bench_set_timeout(60.0)
	g_Leaver = bench_puppet("announced")
	ASSERT(g_Leaver > 0)
	g_Announced = 0
	bench_wait_until("spectating", "announced_spectating", 5.0, g_Leaver)
}

public announced_spectating(id)
{
	g_Until = get_gametime() + 15.0
	bench_wait_until("announced_back", "announced_in", 20.0, id)
}

// "respawn" every frame until he is in play, or 15 s pass
public bool:announced_back(id)
{
	if (is_user_alive(id) || get_gametime() > g_Until)
		return true
	engclient_cmd(id, "respawn")
	return false
}

public announced_in(id)
{
	ASSERT(is_user_alive(id))
	ASSERT(g_Announced > 0)
	g_Leaver = bench_puppet("unannounced")
	ASSERT(g_Leaver > 0)
	g_Announced = 0
	bench_wait_until("spectating", "unannounced_spectating", 5.0, g_Leaver)
}

public unannounced_spectating(id)
{
	g_Until = get_gametime() + 15.0
	bench_wait_until("unannounced_back", "unannounced_done", 20.0, id)
}

// the same with iuser1 and iuser2 cleared just before each "respawn"
public bool:unannounced_back(id)
{
	if (is_user_alive(id) || get_gametime() > g_Until)
		return true
	set_pev(id, pev_iuser1, 0)
	set_pev(id, pev_iuser2, 0)
	engclient_cmd(id, "respawn")
	return false
}

public unannounced_done(id)
{
	server_print("ts_observer: unwatching spectator alive %d, announced %d times", is_user_alive(id),
		g_Announced)
	g_Leaver = 0
	ASSERT_EQ(g_Announced, 0)
	ASSERT_FALSE(is_user_alive(id))
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Spectating does not hide the HUD: a joiner, who spectates until he plays, is never sent a
// HideWeapon hiding anything, the health (8), the weapons (1) or the flashlight (2) among them.
// Every HideWeapon he gets is printed.

new g_Hider
new g_Hides
new g_HideBits

public on_hide_weapon(msgid, dest, ent)
{
	if (g_Hider && ent == g_Hider)
	{
		new bits = get_msg_arg_int(1)
		server_print("ts_observer: %.3f HideWeapon %d to the joiner", get_gametime(), bits)
		g_Hides++
		g_HideBits |= bits
	}
	return PLUGIN_CONTINUE
}

public test_spectating_does_not_hide_the_hud()
{
	g_Hides = 0
	g_HideBits = 0
	g_Hider = 0
	new id = bench_puppet("hudwatcher")
	ASSERT(id > 0)
	g_Hider = id
	bench_wait_until("spectating", "hud_spectating", 5.0, id)
}

public hud_spectating(id)
{
	bench_next("hud_counted", 2.0, id)
}

public hud_counted(id)
{
	server_print("ts_observer: %d HideWeapon to the spectating joiner, bits %d", g_Hides, g_HideBits)
	g_Hider = 0
	ASSERT(pev(id, pev_iuser1) != 0)
	ASSERT_EQ(g_HideBits, 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Leaving spectate clears iuser1 and iuser2 only: an iuser3 set on a spectator (7 here, set before
// each "respawn") is still there once he is in play.

public test_leaving_spectate_keeps_iuser3()
{
	bench_set_timeout(60.0)
	new id = bench_puppet("iuserthree")
	ASSERT(id > 0)
	bench_wait_until("spectating", "iuser3_spectating", 5.0, id)
}

public iuser3_spectating(id)
{
	g_Until = get_gametime() + 15.0
	bench_wait_until("iuser3_back", "iuser3_in", 20.0, id)
}

public bool:iuser3_back(id)
{
	if (is_user_alive(id) || get_gametime() > g_Until)
		return true
	set_pev(id, pev_iuser3, 7)
	engclient_cmd(id, "respawn")
	return false
}

public iuser3_in(id)
{
	server_print("ts_observer: back in play: alive %d, iuser1 %d, iuser2 %d, iuser3 %d", is_user_alive(id),
		pev(id, pev_iuser1), pev(id, pev_iuser2), pev(id, pev_iuser3))
	ASSERT(is_user_alive(id))
	ASSERT_EQ(pev(id, pev_iuser1), 0)
	ASSERT_EQ(pev(id, pev_iuser3), 7)
	bench_pass()
}

// PreThink eases the slow-motion rate (InterpolateSlowMotion, 0x8098e) and runs the stunt, animation
// and melee timers before its spectate block (0x80e73), so a spectator's rate eases too: set to 0.5,
// it is back near his target (1.0) a moment later.
public test_spectator_eases_his_slow_motion()
{
	new id = bench_puppet("slowspec")
	ASSERT(id > 0)
	bench_wait_until("spectating", "slowspec_spectating", 10.0, id)
}

public slowspec_spectating(id)
{
	set_pev(id, pev_fuser1, 0.5)
	bench_next("slowspec_eased", 0.5, id)
}

public slowspec_eased(id)
{
	new Float:rate
	pev(id, pev_fuser1, rate)
	server_print("ts_observer: spectator's slow-motion rate 0.5 s after 0.5: %.3f", rate)
	ASSERT(pev(id, pev_iuser1) != 0)
	ASSERT(rate > 0.9)
	bench_pass()
}

// A round's re-entry window (RestartRound arms it 10 s out, the gate 3 s out) is a spectate-block
// line once a second, its seconds truncated (0x81063): 6 down to 0 after the 3 s countdown. It runs
// out inside the spectate block (0x80fb3) with "You have to wait until the next round."; a player
// who went in to play in the window is not told that.
new g_HoldWaiter
new g_HoldPlayer
new BenchMsg:g_HoldMark
new BenchMsg:g_HoldMark2

public test_lms_hold_window_counts_down_in_spectate()
{
	bench_set_timeout(150.0)
	g_Lms = 1
	g_RoundTime = get_cvar_num("roundtime")
	set_cvar_num("lastmanstanding", 1)
	set_cvar_num("roundtime", 180)
	bench_change_map(g_Map, "hold_map")
}

public hold_map()
{
	g_HoldWaiter = bench_puppet("holdwaiter")
	ASSERT(g_HoldWaiter > 0)
	g_HoldPlayer = bench_puppet("holdplayer")
	ASSERT(g_HoldPlayer > 0)
	// The first round starts five seconds into the map, with a RoundTime to everyone.
	bench_wait_message(g_HoldWaiter, "RoundTime", "", "hold_round", 15.0)
}

public hold_round(waiter)
{
	g_HoldMark = bench_msg_last(g_HoldWaiter, "RoundTime")
	g_HoldMark2 = bench_msg_last(g_HoldPlayer, "RoundTime")
	// past the 3 s gate, inside the window
	bench_next("hold_play", 4.0)
}

public hold_play()
{
	bench_puppet_spawn(g_HoldPlayer, "hold_playing", 4.0, "respawn")
}

public hold_playing(player)
{
	// to 1 s past the window's end (10 s after the round started)
	bench_next("hold_done", 6.0)
}

public hold_done()
{
	new lines = 0, first = -1, last = -1, bool:steps = true, waits = 0, bool:waitLast = false
	new text[128]
	for (new BenchMsg:msg = bench_msg_next(g_HoldWaiter, g_HoldMark, "TSMessage"); msg != BenchMsg:0;
		msg = bench_msg_next(g_HoldWaiter, msg, "TSMessage"))
	{
		bench_msg_text(msg, text, charsmax(text))
		if (contain(text, "seconds left for respawn") != -1)
		{
			new n = str_to_num(text)
			if (lines > 0 && n != last - 1)
				steps = false
			if (first == -1)
				first = n
			last = n
			lines++
			waitLast = false
		}
		else if (contain(text, "You have to wait until the next round.") != -1)
		{
			waits++
			waitLast = true
		}
	}
	new playerWaits = 0
	for (new BenchMsg:msg = bench_msg_next(g_HoldPlayer, g_HoldMark2, "TSMessage"); msg != BenchMsg:0;
		msg = bench_msg_next(g_HoldPlayer, msg, "TSMessage"))
	{
		bench_msg_text(msg, text, charsmax(text))
		if (contain(text, "You have to wait until the next round.") != -1)
			playerWaits++
	}
	new alive = is_user_alive(g_HoldPlayer) ? 1 : 0
	server_print("ts_observer: window lines %d, %d down to %d, steps %d, waits %d (last %d); player alive %d, told to wait %d",
		lines, first, last, steps, waits, waitLast, alive, playerWaits)
	// Put the map back first, so a failure leaves the next tests on the usual rules. Plugins reload on
	// the map change, so the outcome travels as the step's data.
	new ok = lines == 7 && first == 6 && last == 0 && steps && waits == 1 && waitLast && alive == 1 && playerWaits == 0
	set_cvar_num("lastmanstanding", 0)
	set_cvar_num("roundtime", g_RoundTime)
	g_Lms = 0
	bench_change_map(g_Map, "hold_restored", ok ? 1 : 0)
}

public hold_restored(ok)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	ASSERT_EQ(ok, 1)
	bench_pass()
}
