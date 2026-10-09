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
// on an empty server, a joiner's round clock comes before the spectator catch-up and is truncated
// (and comes three times), the last player alive ends the round, a spectator still in the round
// watches nobody (teammates only, and last man standing has none), a new round sends everyone to
// spectate with the value of his loadout as cash, a player who leaves counts as one gone, a later
// death moves the count back, and the restartround command restarts the round under a black
// banner. In plain teamplay a wiped team does not end a round. A ts_mapglobals with spawnflag 32
// turns the round clock off.
// ../ts_rounds.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386) patched with amxxbench's tests/patch-ts30.py: on
// an unpatched TS 3.0 each free-for-all last man standing round start corrupts the server's heap.
// run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1

#define OBS_ROAMING	3

new g_Map[32]
new g_A
new g_B
new g_C
new g_Cash
new Float:g_Death
// Every RoundTime sent to one watched joiner on his own (MSG_ONE) with flag 0, and when.
new g_Watched
new g_ClockCount
new Float:g_ClockTimes[8]
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
	RestoreGameCfg()
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
	if (ent == g_Watched && g_ClockCount < sizeof(g_ClockTimes))
		g_ClockTimes[g_ClockCount++] = get_gametime()
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
StartLms(const step[], data = 0)
{
	bench_set_timeout(150.0)
	g_Saved = 1
	g_RoundTime = get_cvar_num("roundtime")
	set_cvar_num("lastmanstanding", 1)
	set_cvar_num("roundtime", 180)
	bench_change_map(g_Map, step, data)
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
// anything. (The server is put in teamplay for the test if it is not. The map change execs game.cfg
// before it installs the rules, so a game.cfg naming mp_teamplay is set aside without that line, as
// tsr_game.cfg, until the new map is up, or until this file loads next if the server went down in
// between.)
#define GAMECFG "game.cfg"
#define GAMECFG_SAVED "tsr_game.cfg"

RestoreGameCfg()
{
	if (file_exists(GAMECFG_SAVED))
	{
		delete_file(GAMECFG)
		rename_file(GAMECFG_SAVED, GAMECFG, 1)
	}
}

// Copies game.cfg aside and writes it back without its mp_teamplay line.
new g_CfgLines[32][128]

SetGameCfgAside()
{
	new count = 0
	new f = fopen(GAMECFG, "rt")
	if (!f)
		return
	while (count < sizeof(g_CfgLines) && fgets(f, g_CfgLines[count], charsmax(g_CfgLines[])))
		count++
	fclose(f)
	rename_file(GAMECFG, GAMECFG_SAVED, 1)
	f = fopen(GAMECFG, "wt")
	for (new i = 0; i < count; i++)
		if (containi(g_CfgLines[i], "mp_teamplay") == -1)
			fputs(f, g_CfgLines[i])
	fclose(f)
}

public test_teamplay_wipe_is_not_a_round()
{
	bench_set_timeout(150.0)
	if (get_cvar_num("mp_teamplay"))
	{
		team_map(0)
		return
	}
	g_Saved = 1
	g_Teamplay = 1
	set_cvar_num("mp_teamplay", 1)
	SetGameCfgAside()
	bench_change_map(g_Map, "team_map", 1)
}

// changed: the test put the server in teamplay (plugin variables start over on the map change, so
// it travels as the step's data)
public team_map(changed)
{
	g_Teamplay = changed
	g_Saved = changed
	ASSERT_EQ(get_cvar_num("mp_teamplay"), 1)
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

// Three players in play in last man standing, then leaver_ready (kind 0) or later_ready (1).
// (Plugin variables start over on the map change; the kind travels as the step's data.)
new g_Kind3
Lms3(kind)
{
	StartLms("three_map", kind)
}

public three_map(kind)
{
	g_Kind3 = kind
	g_A = bench_puppet("lmsa")
	g_B = bench_puppet("lmsb")
	g_C = bench_puppet("lmsc")
	ASSERT(g_A > 0 && g_B > 0 && g_C > 0)
	WaitFor("round_started", "three_round", 15.0)
}

public three_round()
{
	g_Deadline = get_gametime() + 20.0
	bench_wait_until("joined", "three_a", 25.0, g_A)
}

public three_a()
{
	g_Deadline = get_gametime() + 20.0
	bench_wait_until("joined", "three_b", 25.0, g_B)
}

public three_b()
{
	g_Deadline = get_gametime() + 20.0
	bench_wait_until("joined", "three_c", 25.0, g_C)
}

public three_c()
{
	if (!is_user_alive(g_A) || !is_user_alive(g_B) || !is_user_alive(g_C))
	{
		// bit 4: the three could not get into play
		EndLms("three_restored", 16)
		return
	}
	// past the spawn protection
	bench_next(g_Kind3 ? "later_ready" : "leaver_ready", 1.5)
}

public three_restored(result)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_rounds: three-player result %d", result)
	ASSERT_FALSE(result & 16)
	ASSERT(result & 1)
	bench_pass()
}

// A player who leaves while the round runs counts like one who died: a second later the others
// are told how many are still standing.
public test_leaver_is_counted_out()
{
	Lms3(0)
}

public leaver_ready()
{
	g_Mark = bench_msg_last(g_A)
	server_cmd("kick #%d", get_user_userid(g_C))
	WaitFor("standing_told", "leaver_counted", 3.0)
}

public bool:standing_told()
{
	return bench_msg_next(g_A, g_Mark, "TSMessage", "men standing") != BenchMsg:0
		|| get_gametime() > g_Deadline
}

public leaver_counted()
{
	// bit 0: "2 men standing!"
	EndLms("three_restored", bench_msg_next(g_A, g_Mark, "TSMessage", "2 men standing") != BenchMsg:0)
}

// Each death puts the count a second after it, so two deaths 0.6 s apart are counted once, a
// second after the later one, which leaves the last man standing.
public test_later_death_moves_the_count()
{
	Lms3(1)
}

public later_ready()
{
	g_Mark = bench_msg_last(g_A)
	user_kill(g_C)
	bench_next("later_second", 0.6)
}

public later_second()
{
	user_kill(g_B)
	g_Deadline = get_gametime() + 4.0
	bench_wait_until("b_dead", "later_b_dead", 5.0)
}

public bool:b_dead()
{
	return !is_user_alive(g_B) || get_gametime() > g_Deadline
}

public later_b_dead()
{
	g_Death = get_gametime()
	WaitFor("last_man_after_mark", "later_counted", 3.0)
}

public bool:last_man_after_mark()
{
	return bench_msg_next(g_A, g_Mark, "TSMessage", "is the Last Man Standing") != BenchMsg:0
		|| get_gametime() > g_Deadline
}

public later_counted()
{
	new told = bench_msg_next(g_A, g_Mark, "TSMessage", "is the Last Man Standing") != BenchMsg:0
	new Float:after = get_gametime() - g_Death
	server_print("ts_rounds: last man told %d, %.2f s after the second death", told, after)
	// bit 0: told, a second after the second death
	EndLms("three_restored", told && after >= 0.9 && after < 1.3)
}

// A new round sends every player in play to spectate, where he waits for the respawn gate as
// after a death, and pays him what his loadout is worth (the Glock's price, here).
public test_new_round_sends_everyone_to_spectate()
{
	StartLms("round_map")
}

public round_map()
{
	g_A = bench_puppet("roundone")
	g_B = bench_puppet("roundtwo")
	ASSERT(g_A > 0 && g_B > 0)
	WaitFor("round_started", "round_round", 15.0)
}

public round_round()
{
	g_Deadline = get_gametime() + 20.0
	bench_wait_until("joined", "round_a", 25.0, g_A)
}

public round_a()
{
	g_Deadline = get_gametime() + 20.0
	bench_wait_until("joined", "round_b", 25.0, g_B)
}

public round_b()
{
	if (!is_user_alive(g_A) || !is_user_alive(g_B))
	{
		EndLms("round_restored", 16)
		return
	}
	ts_giveweapon(g_A, GLOCK18, 0, 0)
	bench_next("round_armed", 1.0)
}

public round_armed()
{
	g_Cash = ts_getusercash(g_A)
	g_RoundStart = 0.0
	user_kill(g_B)
	WaitFor("round_started", "round_new", 10.0)
}

public round_new()
{
	bench_next("round_after", 0.2)
}

public round_after()
{
	new cash = ts_getusercash(g_A)
	server_print("ts_rounds: new round %d, survivor alive %d mode %d, cash %d -> %d", g_RoundStart > 0.0,
		is_user_alive(g_A), pev(g_A, pev_iuser1), g_Cash, cash)
	// bit 0: a new round came; bit 1: the survivor spectates; bit 2: he was paid
	new result = g_RoundStart > 0.0 ? 1 : 0
	if (!is_user_alive(g_A) && pev(g_A, pev_iuser1) != 0)
		result |= 2
	if (cash > g_Cash)
		result |= 4
	EndLms("round_restored", result)
}

public round_restored(result)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_rounds: new round result %d", result)
	ASSERT_FALSE(result & 16)
	ASSERT(result & 1)
	ASSERT(result & 2)
	ASSERT(result & 4)
	bench_pass()
}

// restartround (a server command) restarts a round of last man standing a second later: everyone
// is told "Restarting Round", in black, and a new round starts.
public test_restartround_restarts_the_round()
{
	StartLms("restart_map")
}

// kind 0: the restart; 1: the banner's colour
new g_Kind
public restart_map(kind)
{
	g_Kind = kind
	g_A = bench_puppet("restarter")
	ASSERT(g_A > 0)
	WaitFor("round_started", "restart_round", 15.0)
}

public restart_round()
{
	g_Mark = bench_msg_last(g_A)
	g_RoundStart = 0.0
	server_cmd("restartround")
	WaitFor("round_started", "restart_new", 4.0)
}

public restart_new()
{
	// bit 0: the banner; bit 1: a new round; bit 2: the banner is black
	new result = 0
	new BenchMsg:msg = bench_msg_next(g_A, g_Mark, "TSMessage", "Restarting Round")
	if (msg != BenchMsg:0)
	{
		result |= 1
		server_print("ts_rounds: Restarting Round in %d %d %d", bench_msg_int(msg, 0),
			bench_msg_int(msg, 1), bench_msg_int(msg, 2))
		if (bench_msg_int(msg, 0) == 0 && bench_msg_int(msg, 1) == 0 && bench_msg_int(msg, 2) == 0)
			result |= 4
	}
	if (g_RoundStart > 0.0)
		result |= 2
	EndLms(g_Kind ? "banner_restored" : "restart_restored", result)
}

public restart_restored(result)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_rounds: restartround result %d", result)
	ASSERT(result & 1)
	ASSERT(result & 2)
	bench_pass()
}

// The same restart, for the banner's colour.
public test_restart_banner_is_black()
{
	StartLms("restart_map", 1)
}

public banner_restored(result)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	ASSERT(result & 1)
	ASSERT(result & 4)
	bench_pass()
}

// InitHUD tells a joiner the round clock, and so does each pass of UpdateClientData's HUD reset:
// that one in the same frame, and again on the pass his move to spectate asks for, which comes
// 0.1 s later as UpdateClientData runs at most every 0.1 s.
public test_joiner_is_told_the_clock_three_times()
{
	StartLms("thrice_map")
}

public thrice_map()
{
	g_A = bench_puppet("thricefirst")
	ASSERT(g_A > 0)
	WaitFor("round_started", "thrice_join", 15.0)
}

public thrice_join()
{
	g_ClockCount = 0
	g_Watched = bench_puppet("thricejoiner")
	ASSERT(g_Watched > 0)
	bench_next("thrice_joined", 1.0)
}

public thrice_joined()
{
	for (new i = 0; i < g_ClockCount; i++)
		server_print("ts_rounds: joiner clock %d at %.3f", i, g_ClockTimes[i])
	// count, bit 8 when the first two came in one frame, bit 9 when the third came at least
	// 0.05 s after them (on the next UpdateClientData, 0.1 s later)
	new result = g_ClockCount
	if (g_ClockCount >= 3 && g_ClockTimes[0] == g_ClockTimes[1] && g_ClockTimes[2] >= g_ClockTimes[1])
		result |= 256
	if (g_ClockCount >= 3 && g_ClockTimes[2] >= g_ClockTimes[1] + 0.05)
		result |= 512
	g_Watched = 0
	EndLms("thrice_restored", result)
}

public thrice_restored(result)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_rounds: joiner clock result %d", result)
	ASSERT_EQ(result & 255, 3)
	ASSERT(result & 256)
	ASSERT(result & 512)
	bench_pass()
}

// A ts_mapglobals with spawnflag 32 turns the round clock off: in last man standing nobody is told
// the round's start (RoundTime to everyone) and a joiner is not caught up on it.
public test_mapglobals_turns_the_round_clock_off()
{
	StartLms("clockoff_map")
}

public clockoff_map()
{
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_mapglobals"))
	ASSERT(ent > 0)
	set_pev(ent, pev_spawnflags, 32)
	dllfunc(DLLFunc_Spawn, ent)
	g_RoundStart = 0.0
	g_A = bench_puppet("clockofffirst")
	ASSERT(g_A > 0)
	// the first round starts five seconds into the map
	bench_next("clockoff_join", 7.0)
}

public clockoff_join()
{
	g_ClockCount = 0
	g_Watched = bench_puppet("clockoffjoiner")
	ASSERT(g_Watched > 0)
	bench_next("clockoff_joined", 1.0)
}

public clockoff_joined()
{
	// joiner's clocks, and bit 8 when the round start was told to everyone
	new result = g_ClockCount
	if (g_RoundStart > 0.0)
		result |= 256
	g_Watched = 0
	EndLms("clockoff_restored", result)
}

public clockoff_restored(result)
{
	ASSERT_EQ(get_cvar_num("lastmanstanding"), 0)
	server_print("ts_rounds: clock off result %d", result)
	ASSERT_EQ(result, 0)
	bench_pass()
}
