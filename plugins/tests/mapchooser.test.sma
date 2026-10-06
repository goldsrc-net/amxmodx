// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for mapchooser.sma (Nextmap Chooser): the nextmap vote near the end of the map, by time
// left, mp_winlimit or mp_maxrounds, answered by a puppet. The plugin checks every 15 seconds; the
// tests make that every 0.1 second and put it back. The vote only sets amx_nextmap or extends
// mp_timelimit, it never changes the map. The Specialists has no mp_winlimit or mp_maxrounds, so
// this file registers both (at 0, the value the plugin reads when they are missing). mp_timelimit,
// mp_winlimit, mp_maxrounds, amx_nextmap and amx_vote_answers are put back after each test.
//

#include <amxmodx>
#include <amxxbench>

#define TASK_VOTE 987456

new g_Puppet
new Float:g_TimeLimit
new g_WinLimit
new g_MaxRounds
new g_NextMap[32]
new g_VoteAnswers
new g_Qualify[16]
new g_Map[32]
new g_Step[32]
new Float:g_TimeLimitBefore

public plugin_init()
{
	register_plugin("Nextmap Chooser Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_cvar("mp_winlimit", "0")
	register_cvar("mp_maxrounds", "0")

	bench_coverage_ignore("mapchooser.sma", 47, 47, "the TeamScore event is only registered under Counter-Strike")
	bench_coverage_ignore("mapchooser.sma", 275, 281, "team_score handles TeamScore, only registered under Counter-Strike")
}

public bench_setup()
{
	g_TimeLimit = get_cvar_float("mp_timelimit")
	g_WinLimit = get_cvar_num("mp_winlimit")
	g_MaxRounds = get_cvar_num("mp_maxrounds")
	get_cvar_string("amx_nextmap", g_NextMap, charsmax(g_NextMap))
	g_VoteAnswers = get_cvar_num("amx_vote_answers")
	g_Puppet = 0
}

public bench_teardown()
{
	set_cvar_float("mp_timelimit", g_TimeLimit)
	set_cvar_num("mp_winlimit", g_WinLimit)
	set_cvar_num("mp_maxrounds", g_MaxRounds)
	set_cvar_string("amx_nextmap", g_NextMap)
	set_cvar_num("amx_vote_answers", g_VoteAnswers)
	change_task(TASK_VOTE, 15.0, 1)
}

// Starts checking every 0.1 second with nothing near its end, so the plugin forgets any earlier
// vote, then makes the end near (how: "time", "winlimit" or "maxrounds") and calls step once the
// vote menu reaches the puppet.
StartVote(const how[], const step[])
{
	g_Puppet = bench_puppet("voter")
	if (!bench_check(g_Puppet > 0, "puppet created"))
		return
	set_cvar_float("mp_timelimit", 30.0)
	set_cvar_num("mp_winlimit", 0)
	set_cvar_num("mp_maxrounds", 0)
	if (!bench_check(change_task(TASK_VOTE, 0.1, 1) == 1, "vote task found"))
		return
	copy(g_Qualify, charsmax(g_Qualify), how)
	copy(g_Step, charsmax(g_Step), step)
	bench_next("near_the_end", 0.35)
}

public near_the_end()
{
	if (equal(g_Qualify, "time"))
		set_cvar_float("mp_timelimit", (get_gametime() + 100.0) / 60.0)
	else if (equal(g_Qualify, "winlimit"))
		set_cvar_num("mp_winlimit", 2)
	else
		set_cvar_num("mp_maxrounds", 2)
	bench_wait_message(g_Puppet, "ShowMenu", "AMX Choose nextmap:", g_Step, 2.0)
}

// The text of the newest menu sent to the puppet, its parts joined.
MenuText(text[], len)
{
	new BenchMsg:msg = BenchMsg:0, part[256], bool:more = false
	text[0] = EOS
	while ((msg = bench_msg_next(g_Puppet, msg, "ShowMenu")) != BenchMsg:0)
	{
		if (!more)
			text[0] = EOS
		bench_msg_string(msg, 3, part, charsmax(part))
		add(text, len, part)
		more = bench_msg_int(msg, 2) != 0
	}
}

MenuKeys()
{
	new BenchMsg:msg = bench_msg_last(g_Puppet, "ShowMenu")
	return msg == BenchMsg:0 ? -1 : bench_msg_int(msg, 0)
}

// The map item number offers in the vote menu.
MenuMap(number, map[], len)
{
	new text[512], item[8], pos
	MenuText(text, charsmax(text))
	formatex(item, charsmax(item), "%d. ", number)
	map[0] = EOS
	if ((pos = contain(text, item)) == -1)
		return
	copyc(map, len, text[pos + strlen(item)], '^n')
}

// After answering, back to a check every 15 seconds and wait for the result, 15 seconds after the
// vote started.
AwaitResult(const step[])
{
	bench_wait_message(g_Puppet, "TextMsg", "Choosing finished.", step, 17.0)
}

public test_vote_picks_a_map()
{
	set_cvar_num("amx_vote_answers", 1)
	StartVote("winlimit", "pick_shown")
}

public pick_shown()
{
	// Five maps and None; no extending when the end comes from mp_winlimit.
	ASSERT_EQ(MenuKeys(), MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_7)
	new text[512]
	MenuText(text, charsmax(text))
	ASSERT(contain(text, "7. None") != -1)
	ASSERT_EQ(contain(text, "Extend map"), -1)

	MenuMap(1, g_Map, charsmax(g_Map))
	ASSERT(is_map_valid(g_Map))
	bench_puppet_cmd(g_Puppet, "menuselect 1")
	new expected[64]
	formatex(expected, charsmax(expected), "voter chose %s", g_Map)
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	// While the vote runs, the next checks start no other one.
	bench_next("still_one_vote", 0.3)
}

public still_one_vote()
{
	ASSERT_EQ(bench_msg_count(g_Puppet, "TextMsg", "It's time to choose the nextmap..."), 1)
	change_task(TASK_VOTE, 15.0, 1)
	AwaitResult("map_picked")
}

public map_picked()
{
	new expected[64], nextmap[32]
	formatex(expected, charsmax(expected), "Choosing finished. The nextmap will be %s", g_Map)
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	get_cvar_string("amx_nextmap", nextmap, charsmax(nextmap))
	ASSERT_STR_EQ(nextmap, g_Map)
	bench_pass()
}

public test_vote_for_none_keeps_the_nextmap()
{
	set_cvar_num("amx_vote_answers", 1)
	StartVote("maxrounds", "none_shown")
}

public none_shown()
{
	bench_puppet_cmd(g_Puppet, "menuselect 7")
	ASSERT_EQ(bench_msg_count(g_Puppet, "TextMsg", " chose "), 0)
	change_task(TASK_VOTE, 15.0, 1)
	AwaitResult("none_picked")
}

public none_picked()
{
	new expected[64], nextmap[32]
	formatex(expected, charsmax(expected), "Choosing finished. The nextmap will be %s", g_NextMap)
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	get_cvar_string("amx_nextmap", nextmap, charsmax(nextmap))
	ASSERT_STR_EQ(nextmap, g_NextMap)
	bench_pass()
}

public test_vote_extends_the_map()
{
	set_cvar_num("amx_vote_answers", 1)
	set_cvar_num("amx_extendmap_max", 90)
	set_cvar_num("amx_extendmap_step", 15)
	StartVote("time", "extend_shown")
}

public extend_shown()
{
	// By time left, and mp_timelimit under amx_extendmap_max: 6 extends the map.
	new text[512], map[32], expected[64]
	MenuText(text, charsmax(text))
	get_mapname(map, charsmax(map))
	formatex(expected, charsmax(expected), "6. Extend map %s", map)
	ASSERT(contain(text, expected) != -1)
	ASSERT_EQ(MenuKeys(), MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_6|MENU_KEY_7)

	bench_puppet_cmd(g_Puppet, "menuselect 6")
	ASSERT_MSG(g_Puppet, "TextMsg", "voter chose map extending")
	g_TimeLimitBefore = get_cvar_float("mp_timelimit")
	change_task(TASK_VOTE, 15.0, 1)
	AwaitResult("extended")
}

public extended()
{
	ASSERT_MSG(g_Puppet, "TextMsg", "Choosing finished. Current map will be extended to next 15 minutes")
	ASSERT(floatabs(get_cvar_float("mp_timelimit") - (g_TimeLimitBefore + 15.0)) < 0.01)
	bench_pass()
}

public test_vote_without_answers_shown()
{
	set_cvar_num("amx_vote_answers", 0)
	StartVote("winlimit", "quiet_shown")
}

public quiet_shown()
{
	MenuMap(2, g_Map, charsmax(g_Map))
	bench_puppet_cmd(g_Puppet, "menuselect 2")
	ASSERT_EQ(bench_msg_count(g_Puppet, "TextMsg", " chose "), 0)
	change_task(TASK_VOTE, 15.0, 1)
	AwaitResult("quiet_picked")
}

public quiet_picked()
{
	new nextmap[32]
	get_cvar_string("amx_nextmap", nextmap, charsmax(nextmap))
	ASSERT_STR_EQ(nextmap, g_Map)
	bench_pass()
}

public test_no_vote_far_from_the_end()
{
	g_Puppet = bench_puppet("bystander")
	ASSERT(g_Puppet > 0)
	ASSERT_EQ(change_task(TASK_VOTE, 0.1, 1), 1)
	// Two wins short of mp_winlimit is near; ten is not.
	set_cvar_num("mp_winlimit", 10)
	bench_next("not_by_winlimit", 0.35)
}

public not_by_winlimit()
{
	ASSERT_EQ(bench_msg_count(g_Puppet, "ShowMenu"), 0)
	set_cvar_num("mp_winlimit", 0)
	set_cvar_num("mp_maxrounds", 10)
	bench_next("not_by_maxrounds", 0.35)
}

public not_by_maxrounds()
{
	ASSERT_EQ(bench_msg_count(g_Puppet, "ShowMenu"), 0)
	set_cvar_num("mp_maxrounds", 0)
	set_cvar_float("mp_timelimit", 30.0)
	bench_next("not_by_time", 0.35)
}

public not_by_time()
{
	ASSERT_EQ(bench_msg_count(g_Puppet, "ShowMenu"), 0)
	bench_pass()
}

// Each vote draws five maps at random and moves on from any already drawn, so no map is offered
// twice. Several votes in a row, each checked.
#define VOTES 8

new g_Votes

public test_each_vote_offers_different_maps()
{
	set_cvar_num("amx_vote_answers", 0)
	g_Votes = 0
	StartVote("winlimit", "drawn")
}

public drawn()
{
	new maps[5][32]
	for (new i = 0; i < 5; i++)
	{
		MenuMap(i + 1, maps[i], charsmax(maps[]))
		ASSERT(is_map_valid(maps[i]))
		for (new j = 0; j < i; j++)
			ASSERT_FALSE(equal(maps[i], maps[j]))
	}
	if (++g_Votes == VOTES)
	{
		set_cvar_num("mp_winlimit", 0)
		change_task(TASK_VOTE, 15.0, 1)
		bench_wait_until("all_finished", "votes_done", 17.0)
		return
	}
	// Far from the end for a moment, so the plugin forgets this vote, then near again.
	set_cvar_num("mp_winlimit", 10)
	bench_next("draw_again", 0.25)
}

public draw_again()
{
	set_cvar_num("mp_winlimit", 2)
	bench_wait_until("next_menu", "drawn", 2.0)
}

public next_menu()
{
	return bench_msg_count(g_Puppet, "ShowMenu", "AMX Choose nextmap:") > g_Votes
}

public all_finished()
{
	return bench_msg_count(g_Puppet, "TextMsg", "Choosing finished.") >= VOTES
}

public votes_done()
{
	bench_pass()
}
