// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the original The Specialists 3.0's rounds: in last man standing the first round starts
// on an empty server, a joiner's round clock comes before the spectator catch-up and is truncated,
// the last player alive ends the round, and a spectator still in the round watches nobody
// (teammates only, and last man standing has none). In plain teamplay a wiped team does not end a
// round. ../ts_rounds.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <amxxbench>

#define OBS_ROAMING	3

new g_Map[32]
new g_A
new g_B
new g_Saved
new g_RoundTime
new g_Teamplay
new BenchMsg:g_Mark
new Float:g_Frags
// The last round start: the game time of a RoundTime to everyone with flag 0.
new Float:g_RoundStart
// Joiners and the RoundTime InitHUD sent each of them, with the game time it was sent.
#define JOINERS 5
new g_Joiner[JOINERS]
new g_JoinClock[JOINERS]
new Float:g_JoinTime[JOINERS]
// Order of the RoundTime and the first Spectator each joiner was sent on his own (MSG_ONE).
new g_JoinClockSeq[JOINERS]
new g_JoinSpecSeq[JOINERS]
new g_Seq
new g_Joined
new g_Result
// Waits inside a last man standing map give up at this game time and carry on, so the map is
// always put back.
new Float:g_Deadline

public plugin_init()
{
	register_plugin("TS Round Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	get_mapname(g_Map, charsmax(g_Map))
	register_message(get_user_msgid("RoundTime"), "on_round_time")
	register_message(get_user_msgid("Spectator"), "on_spectator")
}

public on_round_time(msgid, dest, ent)
{
	g_Seq++
	server_print("ts_rounds: %.3f RoundTime dest %d to %d: %d, %d", get_gametime(), dest, ent,
		get_msg_arg_int(1), get_msg_arg_int(2))
	if (get_msg_arg_int(2) != 0)
		return PLUGIN_CONTINUE
	if (dest == MSG_ALL || dest == MSG_BROADCAST)
	{
		g_RoundStart = get_gametime()
		return PLUGIN_CONTINUE
	}
	for (new i = 0; i < g_Joined; i++)
		if (g_Joiner[i] == ent && g_JoinTime[i] == 0.0)
		{
			g_JoinClock[i] = get_msg_arg_int(1)
			g_JoinTime[i] = get_gametime()
			g_JoinClockSeq[i] = g_Seq
		}
	return PLUGIN_CONTINUE
}

public on_spectator(msgid, dest, ent)
{
	g_Seq++
	if (dest != MSG_ONE && dest != MSG_ONE_UNRELIABLE)
		return PLUGIN_CONTINUE
	for (new i = 0; i < g_Joined; i++)
		if (g_Joiner[i] == ent && g_JoinSpecSeq[i] == 0)
			g_JoinSpecSeq[i] = g_Seq
	return PLUGIN_CONTINUE
}

public bool:is_dead(id)
{
	return !is_user_alive(id)
}

public bool:round_started()
{
	return g_RoundStart > 0.0 || get_gametime() > g_Deadline
}

public bool:last_man_told()
{
	return bench_msg_last(g_A, "TSMessage", "is the Last Man Standing") != BenchMsg:0
		|| get_gametime() > g_Deadline
}

// Joins id (the "respawn" command a client sends) until he is alive or the deadline passes.
public bool:joined(id)
{
	if (is_user_alive(id))
		return true
	engclient_cmd(id, "respawn")
	return get_gametime() > g_Deadline
}

WaitFor(const condition[], const step[], Float:seconds)
{
	g_Deadline = get_gametime() + seconds
	bench_wait_until(condition, step, seconds + 5.0)
}

// Last man standing for one map (lastmanstanding 1, roundtime 180), then the server's own settings.
StartLms(const step[])
{
	bench_set_timeout(150.0)
	g_Saved = 1
	g_RoundTime = get_cvar_num("roundtime")
	set_cvar_num("lastmanstanding", 1)
	set_cvar_num("roundtime", 180)
	bench_change_map(g_Map, step)
}

// Puts the map back first, so a failure leaves the next tests on the usual rules. Plugins reload on
// the map change, so the result travels as the step's data.
EndLms(const step[], result)
{
	set_cvar_num("lastmanstanding", 0)
	set_cvar_num("roundtime", g_RoundTime)
	g_Saved = 0
	bench_change_map(g_Map, step, result)
}

public bench_teardown()
{
	if (g_Saved)
	{
		set_cvar_num("lastmanstanding", 0)
		set_cvar_num("roundtime", g_RoundTime)
		if (g_Teamplay)
			set_cvar_num("mp_teamplay", 0)
	}
}

// The first round starts five seconds into the map whether or not anyone is playing, so a joiner
// later on is told the time left (InitHUD), not a fresh round.
public test_lms_round_starts_on_an_empty_server()
{
	StartLms("empty_map")
}

public empty_map()
{
	bench_next("empty_join", 7.0)
}

public empty_join()
{
	server_print("ts_rounds: round start at %.2f (map time %.2f)", g_RoundStart, get_gametime())
	new id = bench_puppet("emptyjoiner")
	ASSERT(id > 0)
	g_Joiner[g_Joined++] = id
	bench_next("empty_joined", 1.0, g_RoundStart > 0.0)
}

public empty_joined(started)
{
	// The RoundTime InitHUD sent the joiner (seconds left * 256 + flag), -1 for none, -2 if no round
	// had started before he joined.
	new clock = g_JoinTime[0] != 0.0 ? g_JoinClock[0] * 256 : -1
	EndLms("empty_restored", started ? clock : -2)
}

public empty_restored(clock)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_rounds: empty-server joiner's first RoundTime %d, %d", clock >> 8, clock & 255)
	ASSERT(clock != -2)
	ASSERT(clock != -1)
	ASSERT((clock >> 8) >= 170 && (clock >> 8) < 179)
	ASSERT_EQ(clock & 255, 0)
	bench_pass()
}

// InitHUD sends a joiner the round clock before the spectator catch-up, and the seconds left are
// truncated. Five joiners 0.37 s apart: at least one joins in the second half of a second, where
// truncating and rounding differ.
public test_lms_joiner_clock_truncated_and_first()
{
	StartLms("clock_map")
}

public clock_map()
{
	g_A = bench_puppet("clockfirst")
	ASSERT(g_A > 0)
	WaitFor("round_started", "clock_join", 15.0)
}

public clock_join()
{
	new id = bench_puppet("clockjoiner")
	ASSERT(id > 0)
	g_Joiner[g_Joined++] = id
	if (g_Joined < JOINERS)
		bench_next("clock_join", 0.37)
	else
		bench_next("clock_joined", 1.0)
}

public clock_joined()
{
	// bit 0: every clock as truncated; bit 1: at least one where rounding differs; bit 2: every
	// joiner's RoundTime before his first Spectator.
	new result = 1 | 4
	new Float:end = g_RoundStart + 180.0
	for (new i = 0; i < JOINERS; i++)
	{
		new id = g_Joiner[i]
		new Float:left = end - g_JoinTime[i]
		new trunc = floatround(left, floatround_floor)
		new near = floatround(left, floatround_round)
		server_print("ts_rounds: joiner %d (%d) left %.3f sent %d (trunc %d, round %d), RoundTime #%d Spectator #%d",
			i, id, left, g_JoinClock[i], trunc, near, g_JoinClockSeq[i], g_JoinSpecSeq[i])
		if (g_JoinTime[i] == 0.0 || g_JoinClock[i] != trunc)
			result &= ~1
		if (trunc != near)
			result |= 2
		if (g_JoinClockSeq[i] == 0 || g_JoinSpecSeq[i] == 0 || g_JoinSpecSeq[i] < g_JoinClockSeq[i])
			result &= ~4
	}
	EndLms("clock_restored", result)
}

public clock_restored(result)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_rounds: clock result %d", result)
	ASSERT(result & 4)
	ASSERT(result & 2)
	ASSERT(result & 1)
	bench_pass()
}

// The last player alive is the Last Man Standing: +10 frags, a RoundTime with flag 2 to everyone,
// and a new round three seconds later. A spectator who joins meanwhile watches nobody: in last man
// standing a spectator still in the round may only watch teammates.
public test_last_man_standing_ends_the_round()
{
	StartLms("last_map")
}

public last_map()
{
	g_A = bench_puppet("lastone")
	ASSERT(g_A > 0)
	g_B = bench_puppet("lasttwo")
	ASSERT(g_B > 0)
	WaitFor("round_started", "last_round", 15.0)
}

public last_round()
{
	g_Deadline = get_gametime() + 20.0
	bench_wait_until("joined", "last_a_alive", 25.0, g_A)
}

public last_a_alive()
{
	g_Deadline = get_gametime() + 20.0
	bench_wait_until("joined", "last_b_alive", 25.0, g_B)
}

public last_b_alive()
{
	if (!is_user_alive(g_A) || !is_user_alive(g_B))
	{
		// bit 4: the two players could not get into play
		EndLms("last_restored", 16)
		return
	}
	new spec = bench_puppet("lastspec")
	ASSERT(spec > 0)
	bench_wait_until("is_dead", "last_spec_joined", 2.0, spec)
}

public last_spec_joined(spec)
{
	// bit 0: the spectator roams
	g_Result = pev(spec, pev_iuser1) == OBS_ROAMING ? 1 : 0
	server_print("ts_rounds: spectator mode %d target %d", pev(spec, pev_iuser1), pev(spec, pev_iuser2))
	pev(g_A, pev_frags, g_Frags)
	g_Mark = bench_msg_last(g_A)
	g_RoundStart = 0.0
	user_kill(g_B)
	WaitFor("last_man_told", "last_standing", 5.0)
}

public last_standing()
{
	new result = g_Result
	new Float:frags
	pev(g_A, pev_frags, frags)
	server_print("ts_rounds: frags %.0f -> %.0f", g_Frags, frags)
	// bit 1: +10 frags; bit 2: RoundTime flag 2
	if (frags == g_Frags + 10.0)
		result |= 2
	new BenchMsg:msg = g_Mark
	while ((msg = bench_msg_next(g_A, msg, "RoundTime")) != BenchMsg:0)
		if (bench_msg_int(msg, 1) == 2)
			result |= 4
	g_Result = result
	WaitFor("round_started", "last_restarted", 5.0)
}

public last_restarted()
{
	// bit 3: the new round came
	EndLms("last_restored", g_Result | (g_RoundStart > 0.0 ? 8 : 0))
}

public last_restored(result)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_rounds: last man result %d", result)
	ASSERT_FALSE(result & 16)
	ASSERT(result & 2)
	ASSERT(result & 4)
	ASSERT(result & 8)
	ASSERT(result & 1)
	bench_pass()
}

// In plain teamplay there are no rounds: a team with nobody left alive does not win or restart
// anything. (The server is put in teamplay for the test if it is not.)
public test_teamplay_wipe_is_not_a_round()
{
	bench_set_timeout(150.0)
	if (get_cvar_num("mp_teamplay"))
	{
		team_map()
		return
	}
	g_Saved = 1
	g_Teamplay = 1
	set_cvar_num("mp_teamplay", 1)
	bench_change_map(g_Map, "team_map")
}

public team_map()
{
	g_A = bench_puppet("teamone")
	ASSERT(g_A > 0)
	bench_puppet_spawn(g_A, "team_a_alive", 20.0, "respawn")
}

public team_a_alive(id)
{
	g_B = bench_puppet("teamtwo")
	ASSERT(g_B > 0)
	bench_puppet_spawn(g_B, "team_b_alive", 20.0, "respawn")
}

public team_b_alive(id)
{
	new ta[32], tb[32]
	get_user_team(g_A, ta, charsmax(ta))
	get_user_team(g_B, tb, charsmax(tb))
	server_print("ts_rounds: teams %s and %s", ta, tb)
	ASSERT(!equal(ta, tb))
	g_Mark = bench_msg_last(g_A)
	user_kill(g_B)
	bench_wait_until("is_dead", "team_b_dead", 5.0, g_B)
}

public team_b_dead(id)
{
	bench_next("team_later", 3.0)
}

public team_later()
{
	// bit 0: no round message; bit 1: no RoundTime
	new result = 0
	if (bench_msg_next(g_A, g_Mark, "TSMessage", "the round") == BenchMsg:0
		&& bench_msg_next(g_A, g_Mark, "TSMessage", "Round draw") == BenchMsg:0
		&& bench_msg_next(g_A, g_Mark, "TSMessage", "Restarting Round") == BenchMsg:0)
		result |= 1
	if (bench_msg_next(g_A, g_Mark, "RoundTime") == BenchMsg:0)
		result |= 2
	if (!g_Teamplay)
	{
		team_restored(result)
		return
	}
	set_cvar_num("mp_teamplay", 0)
	g_Saved = 0
	bench_change_map(g_Map, "team_restored", result)
}

public team_restored(result)
{
	server_print("ts_rounds: teamplay wipe result %d", result)
	ASSERT(result & 1)
	ASSERT(result & 2)
	bench_pass()
}
