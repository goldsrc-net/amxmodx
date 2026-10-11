// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the lines The Specialists 3.0 shows when a briefcase's flag goes home, which reTS has to
// match: a neutral flag left lying goes home without a word, a team's flag left lying names the team
// ("%s briefcase returned", no full stop, held 30), and a player returning his team's dropped flag
// announces the 5 points it gives, not his frags.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//
// The first two pass in deathmatch and in teamplay; a flag can only be returned by hand in teamplay,
// so the third says so and passes in deathmatch.
//

#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <amxxbench>

new g_P[2]
new g_Ents[4]
new g_EntCount
new BenchMsg:g_Mark

public plugin_init()
{
	register_plugin("TS 3.0 Flag Return Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_setup()
{
	g_EntCount = 0
}

public bench_teardown()
{
	for (new i = 0; i < g_EntCount; i++)
		if (pev_valid(g_Ents[i]))
			engfunc(EngFunc_RemoveEntity, g_Ents[i])
	g_EntCount = 0
	new flag
	while ((flag = engfunc(EngFunc_FindEntityByString, -1, "classname", "ts_flag")) > 0)
		engfunc(EngFunc_RemoveEntity, flag)
}

// Kills puppet id as the world does, at once (a suicide right after spawning is refused).
Die(id)
{
	set_pev(id, pev_health, 1.0)
	ExecuteHamB(Ham_TakeDamage, id, 0, 0, 10.0, DMG_GENERIC)
}

// A briefcase on brush model *1 owned by team ownerteam (1-based as in the FGD; 0 is neutral). It
// puts its flag out a second after it spawns.
Briefcase(ownerteam)
{
	new ent = create_entity("ts_briefcase")
	if (ent <= 0)
		return 0
	g_Ents[g_EntCount++] = ent
	DispatchKeyValue(ent, "model", "*1")
	new value[8]
	num_to_str(ownerteam, value, charsmax(value))
	DispatchKeyValue(ent, "ownerteam", value)
	DispatchSpawn(ent)
	return ent
}

// The loose flag in play (one the game removed this frame is skipped), or 0.
Flag()
{
	new flag = -1
	while ((flag = engfunc(EngFunc_FindEntityByString, flag, "classname", "ts_flag")) > 0)
		if (!(pev(flag, pev_flags) & FL_KILLME))
			return flag
	return 0
}

// Removes the briefcases and flags made so far.
ClearBriefcases()
{
	bench_teardown()
}

// Whether puppet id was told after the mark that a flag was put out at its base (TSFlag type 0),
// which the briefcase does a second after its flag went home.
bool:BaseFlagAfter(id, BenchMsg:mark)
{
	new BenchMsg:msg = mark
	while ((msg = bench_msg_next(id, msg, "TSFlag")) != BenchMsg:0)
		if (bench_msg_int(msg, 0) == 0)
			return true
	return false
}

// --- a flag left lying ------------------------------------------------------------------------

// A dropped flag goes home 20 seconds later (CTSFlag::RespawnFlag). The line is shown only for team
// 0 to 3: the test is unsigned (@0x8deb2, cmp 3; ja), so a neutral flag (team -1) says nothing.
public test_neutral_flag_goes_home_quietly()
{
	g_P[0] = bench_puppet("neutralcarrier")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "neutral_spawned", 20.0, "respawn")
}

public neutral_spawned(id)
{
	ASSERT(Briefcase(0) > 0)
	bench_next("neutral_flag_out", 1.5, id)
}

public neutral_flag_out(id)
{
	new flag = Flag()
	ASSERT(flag > 0)
	ExecuteHamB(Ham_Use, flag, id, id, 1, 1.0)
	ASSERT(Flag() == 0)
	g_Mark = bench_msg_last(id)
	Die(id)
	ASSERT(Flag() > 0)
	bench_next("neutral_later", 22.0, id)
}

public neutral_later(id)
{
	// the dropped flag went home: the briefcase put a new one out
	ASSERT(BaseFlagAfter(id, g_Mark))
	ASSERT(bench_msg_next(id, g_Mark, "TSMessage", "briefcase returned") == BenchMsg:0)
	bench_pass()
}

// A team's flag left lying names the team: "%s briefcase returned" with the team's name and no
// full stop, held 30 (@0x8dee1, @0x8deea). A player cannot take his own team's flag at its base, so
// the carrier tries the first team's and, if that is his, the second's.
public test_team_flag_goes_home_named()
{
	g_P[0] = bench_puppet("teamcarrier")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "team_spawned", 20.0, "respawn")
}

public team_spawned(id)
{
	ASSERT(Briefcase(1) > 0)
	bench_next("team_flag_out", 1.5, id)
}

public team_flag_out(id)
{
	new flag = Flag()
	ASSERT(flag > 0)
	ExecuteHamB(Ham_Use, flag, id, id, 1, 1.0)
	if (Flag() == flag)
	{
		// his own team's flag: try the other team's
		ClearBriefcases()
		ASSERT(Briefcase(2) > 0)
		bench_next("team_other_out", 1.5, id)
		return
	}
	team_taken(id)
}

public team_other_out(id)
{
	new flag = Flag()
	ASSERT(flag > 0)
	ExecuteHamB(Ham_Use, flag, id, id, 1, 1.0)
	ASSERT(Flag() == 0)
	team_taken(id)
}

team_taken(id)
{
	ASSERT(Flag() == 0)
	g_Mark = bench_msg_last(id)
	Die(id)
	ASSERT(Flag() > 0)
	bench_next("team_later", 22.0, id)
}

public team_later(id)
{
	ASSERT(BaseFlagAfter(id, g_Mark))
	new BenchMsg:msg = bench_msg_next(id, g_Mark, "TSMessage", "briefcase returned")
	ASSERT(msg != BenchMsg:0)
	new text[128]
	bench_msg_string(msg, 5, text, charsmax(text))
	server_print("ts_flag_return: ^"%s^"", text)
	ASSERT(contain(text, "briefcase returned.") == -1)
	ASSERT(contain(text, "The briefcase") != 0)
	ASSERT_EQ(bench_msg_int(msg, 4), 30)
	bench_pass()
}

// --- a flag returned by hand ------------------------------------------------------------------

// A player who takes back his team's dropped flag gets 5 frags, and the line announces the 5, not
// his frags (@0x8e49e pushes 5 for "%s returned the briefcase! %i #TS_Frg"), held 30.
public test_return_announces_five_points()
{
	if (!get_cvar_num("mp_teamplay"))
	{
		bench_describe("return announces five points (teamplay only: in deathmatch nobody owns a flag)")
		bench_pass()
		return
	}
	g_P[0] = bench_puppet("returner")
	g_P[1] = bench_puppet("thief")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[0], "ret_one", 20.0, "respawn")
}

public ret_one(id)
{
	bench_puppet_spawn(g_P[1], "ret_two", 20.0, "respawn")
}

public ret_two(id)
{
	// team 1's flag; whichever puppet cannot take it at its base is on team 1 and returns it
	ASSERT(Briefcase(1) > 0)
	bench_next("ret_flag_out", 1.5, id)
}

public ret_flag_out(id)
{
	new returner = g_P[0], thief = g_P[1]
	new flag = Flag()
	ASSERT(flag > 0)
	ExecuteHamB(Ham_Use, flag, thief, thief, 1, 1.0)
	if (Flag() == flag)
	{
		returner = g_P[1]
		thief = g_P[0]
		ExecuteHamB(Ham_Use, flag, thief, thief, 1, 1.0)
	}
	// the other puppet took it, so the two are on different teams and the returner is on team 1
	ASSERT(Flag() == 0)
	Die(thief)
	flag = Flag()
	ASSERT(flag > 0)
	set_pev(returner, pev_frags, 7.0)
	g_Mark = bench_msg_last(returner)
	ExecuteHamB(Ham_Use, flag, returner, returner, 1, 1.0)
	new BenchMsg:msg = bench_msg_next(returner, g_Mark, "TSMessage", "returned the briefcase!")
	ASSERT(msg != BenchMsg:0)
	new text[128]
	bench_msg_string(msg, 5, text, charsmax(text))
	ASSERT(contain(text, "returned the briefcase! 5 #TS_Frg") != -1)
	ASSERT_EQ(bench_msg_int(msg, 4), 30)
	ASSERT_EQ(get_user_frags(returner), 12)
	bench_pass()
}
