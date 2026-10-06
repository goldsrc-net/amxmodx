// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for adminvote.sma (Admin Votes): amx_votemap, amx_votekick, amx_voteban, amx_vote and
// amx_cancelvote. Puppets answer the vote menus with menuselect. A map vote that passes is always
// refused at the result menu: accepting it runs "changelevel", which would end the run. Every
// test puts the vote cvars back and drops a vote still pending.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#define TASK_CHECKVOTES		99889988
#define TASK_AUTOREFUSE		4545454

new const g_Cvars[][] =
{
	"amx_vote_time", "amx_vote_answers", "amx_vote_delay", "amx_vote_ratio",
	"amx_votekick_ratio", "amx_voteban_ratio", "amx_votemap_ratio"
}
new g_Saved[sizeof(g_Cvars)][16]

new g_P[4]
new g_PuppetCount
new g_TargetUserId

public plugin_init()
{
	register_plugin("Admin Votes Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_setup()
{
	for (new i = 0; i < sizeof(g_Cvars); i++)
		get_cvar_string(g_Cvars[i], g_Saved[i], charsmax(g_Saved[]))
	// A vote lasts amx_vote_time + 2 seconds.
	set_cvar_num("amx_vote_time", 1)
	set_cvar_num("amx_vote_answers", 1)
	set_cvar_float("amx_last_voting", 0.0)
	g_PuppetCount = 0
}

public bench_teardown()
{
	remove_task(TASK_CHECKVOTES, 1)
	remove_task(TASK_AUTOREFUSE, 1)
	for (new i = 0; i < sizeof(g_Cvars); i++)
		set_cvar_string(g_Cvars[i], g_Saved[i])
	set_cvar_float("amx_last_voting", 0.0)
}

// ---------------------------------------------------------------------------------------------
// Helpers

AddPuppet(const name[], const authid[] = "", bool:bot = false)
{
	new id = bench_puppet(name, bot, authid)
	if (id > 0)
		g_P[g_PuppetCount++] = id
	return id
}

// Calls step once every puppet is in the game (alive, for those that are not bots).
WaitForPuppets(const step[])
{
	bench_wait_until("PuppetsReady", step, 30.0)
}

public PuppetsReady()
{
	new ready = true
	for (new i = 0; i < g_PuppetCount; i++)
	{
		new id = g_P[i]
		if (!is_user_connected(id))
			ready = false
		else if (!is_user_bot(id) && !is_user_alive(id))
		{
			engclient_cmd(id, "respawn")
			ready = false
		}
	}
	return ready
}

SetAccess(id, flags)
{
	remove_user_flags(id, -1)
	set_user_flags(id, flags)
}

// The text of the newest menu sent to id, its ShowMenu parts joined.
MenuText(id, out[], len)
{
	new BenchMsg:msg = BenchMsg:0, part[256], bool:more = false
	out[0] = 0
	while ((msg = bench_msg_next(id, msg, "ShowMenu")) != BenchMsg:0)
	{
		if (!more)
			out[0] = 0
		bench_msg_string(msg, 3, part, charsmax(part))
		add(out, len, part)
		more = bench_msg_int(msg, 2) != 0
	}
}

bool:MenuHas(id, const text[])
{
	new menu[1024]
	MenuText(id, menu, charsmax(menu))
	if (contain(menu, text) != -1)
		return true
	bench_fail("menu sent to %d lacks ^"%s^"; it is ^"%s^"", id, text, menu)
	return false
}

#define ASSERT_MENU(%0,%1)	if (!MenuHas(%0, %1)) return

public TargetGone()
{
	return !is_user_connected(g_P[1]) || get_user_userid(g_P[1]) != g_TargetUserId
}

// ---------------------------------------------------------------------------------------------
// Access and refusals

public test_commands_need_vote_access()
{
	ASSERT(AddPuppet("novoteaccess") > 0)
	WaitForPuppets("NoAccess_Ready")
}

public NoAccess_Ready()
{
	new id = g_P[0]
	bench_puppet_cmd(id, "amx_votemap ts_lobby")
	bench_puppet_cmd(id, "amx_votekick novoteaccess")
	bench_puppet_cmd(id, "amx_voteban novoteaccess")
	bench_puppet_cmd(id, "amx_vote question yes no")
	bench_puppet_cmd(id, "amx_cancelvote")
	ASSERT_EQ(bench_msg_count(id, "", "You have no access to that command"), 5)
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES, 1))
	bench_pass()
}

public test_cancel_without_a_vote()
{
	ASSERT(AddPuppet("canceller") > 0)
	WaitForPuppets("CancelNone_Ready")
}

public CancelNone_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_VOTE)
	bench_puppet_cmd(id, "amx_cancelvote")
	ASSERT_MSG(id, "", "There is no voting to cancel")
	bench_pass()
}

public test_vote_refused_while_one_runs_or_too_soon()
{
	ASSERT(AddPuppet("busyvoter") > 0)
	WaitForPuppets("Busy_Ready")
}

public Busy_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_VOTE)
	set_cvar_float("amx_last_voting", get_gametime() + 100.0)
	bench_puppet_cmd(id, "amx_votemap ts_lobby")
	bench_puppet_cmd(id, "amx_vote question yes no")
	bench_puppet_cmd(id, "amx_votekick busyvoter")
	ASSERT_EQ(bench_msg_count(id, "", "There is already one voting..."), 3)

	// The last vote ended a second ago, and amx_vote_delay asks for a minute between votes.
	set_cvar_float("amx_last_voting", get_gametime() - 1.0)
	set_cvar_num("amx_vote_delay", 60)
	bench_puppet_cmd(id, "amx_votemap ts_lobby")
	bench_puppet_cmd(id, "amx_vote question yes no")
	bench_puppet_cmd(id, "amx_votekick busyvoter")
	ASSERT_EQ(bench_msg_count(id, "", "Voting not allowed at this time"), 3)
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES, 1))
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_vote

public test_custom_vote_passes()
{
	ASSERT(AddPuppet("customcaller") > 0)
	ASSERT(AddPuppet("customvoter") > 0)
	WaitForPuppets("Custom_Ready")
}

public Custom_Ready()
{
	new caller = g_P[0], voter = g_P[1]
	SetAccess(caller, ADMIN_VOTE)
	// Five answers: only the first four are offered. The '%' is dropped from the result.
	bench_puppet_cmd(caller, "amx_vote ^"50%% sure?^" Knife Gun Fist Kick Extra")
	ASSERT_MSG(caller, "", "Voting has started...")
	ASSERT_MSG(voter, "", "vote custom")
	ASSERT_MENU(voter, "Vote: 50% sure?")
	ASSERT_MENU(voter, "2.  Gun")
	ASSERT_MENU(voter, "4.  Kick")
	new menu[1024]
	MenuText(voter, menu, charsmax(menu))
	ASSERT_EQ(contain(menu, "Extra"), -1)
	ASSERT(task_exists(TASK_CHECKVOTES, 1))

	bench_puppet_cmd(voter, "menuselect 2")
	ASSERT_MSG(voter, "", "customvoter voted for option #2")
	bench_wait_message(caller, "", "Voting successful", "Custom_Checked", 10.0)
}

public Custom_Checked(caller)
{
	ASSERT_MSG(caller, "", "Voting successful (got ^"1^") (needed ^"1^"). The result: 50 sure? - ^"Gun^"")
	// A custom vote only reports its result: there is no result menu to confirm.
	ASSERT_EQ(bench_msg_count(caller, "ShowMenu", "The result"), 0)
	bench_pass()
}

public test_custom_vote_fails_without_votes()
{
	ASSERT(AddPuppet("lonelycaller") > 0)
	WaitForPuppets("CustomFail_Ready")
}

public CustomFail_Ready()
{
	new caller = g_P[0]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_vote ^"Anyone?^" yes no")
	bench_wait_message(caller, "", "Voting failed", "CustomFail_Checked", 10.0)
}

public CustomFail_Checked(caller)
{
	ASSERT_MSG(caller, "", "Voting failed (got ^"0^") (needed ^"1^")")
	bench_pass()
}

public test_custom_vote_on_passwords_forbidden()
{
	ASSERT(AddPuppet("pwvoter") > 0)
	WaitForPuppets("Forbidden_Ready")
}

public Forbidden_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_VOTE)
	bench_puppet_cmd(id, "amx_vote ^"set SV_Password abc^" yes no")
	ASSERT_MSG(id, "", "Voting for that has been forbidden")
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES, 1))
	bench_pass()
}

public test_cancel_running_vote()
{
	ASSERT(AddPuppet("cancelcaller") > 0)
	ASSERT(AddPuppet("cancelwatcher") > 0)
	WaitForPuppets("Cancel_Ready")
}

public Cancel_Ready()
{
	new caller = g_P[0], watcher = g_P[1]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_vote ^"Cancel me?^" yes no")
	ASSERT(task_exists(TASK_CHECKVOTES, 1))
	bench_puppet_cmd(caller, "amx_cancelvote")
	ASSERT_MSG(caller, "", "Voting canceled")
	ASSERT_MSG(watcher, "", "Voting canceled")
	ASSERT_MSG(watcher, "", "cancel vote")
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES, 1))
	// The cancel counts as the end of a vote for amx_vote_delay.
	ASSERT(get_cvar_float("amx_last_voting") > 0.0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_votemap

public test_votemap_rejects_invalid_maps()
{
	ASSERT(AddPuppet("badmapper") > 0)
	WaitForPuppets("BadMap_Ready")
}

public BadMap_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_VOTE)
	bench_puppet_cmd(id, "amx_votemap bench_no_such_map")
	ASSERT_MSG(id, "", "Given map is not valid")
	// A name with ".." is skipped even when it would resolve to a map.
	bench_puppet_cmd(id, "amx_votemap ^"../ts/maps/ts_lobby^" bench_no_such_map")
	ASSERT_MSG(id, "", "Given maps are not valid")
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES, 1))
	bench_pass()
}

public test_votemap_passes_and_is_refused()
{
	ASSERT(AddPuppet("mapcaller") > 0)
	ASSERT(AddPuppet("mapyes") > 0)
	ASSERT(AddPuppet("mapno") > 0)
	WaitForPuppets("MapVote_Ready")
}

public MapVote_Ready()
{
	new caller = g_P[0], yes = g_P[1], no = g_P[2]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_votemap ts_lobby")
	ASSERT_MSG(caller, "", "Voting has started...")
	ASSERT_MSG(yes, "", "vote map(s)")
	ASSERT_MENU(yes, "Change map to ts_lobby?")
	ASSERT_MENU(yes, "1.  Yes")
	ASSERT_MENU(yes, "2.  No")

	bench_puppet_cmd(yes, "menuselect 1")
	ASSERT_MSG(yes, "", "mapyes voted for")
	bench_puppet_cmd(no, "menuselect 2")
	ASSERT_MSG(no, "", "mapno voted against")
	bench_wait_message(caller, "ShowMenu", "The result: changelevel ts_lobby", "MapVote_Result", 10.0)
}

public MapVote_Result(caller)
{
	// One yes of two votes meets amx_votemap_ratio 0.40.
	ASSERT_MSG(g_P[1], "", "Voting successful (got ^"1^") (needed ^"1^"). The result: changelevel ts_lobby")
	ASSERT_MENU(caller, "Do you want to continue?")
	ASSERT(task_exists(TASK_AUTOREFUSE, 1))
	bench_puppet_cmd(caller, "menuselect 2")
	ASSERT_MSG(caller, "", "Result refused")
	ASSERT_FALSE(task_exists(TASK_AUTOREFUSE, 1))
	bench_pass()
}

public test_votemap_fails_without_votes()
{
	ASSERT(AddPuppet("quietmapper") > 0)
	WaitForPuppets("MapFail_Ready")
}

public MapFail_Ready()
{
	new caller = g_P[0]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_votemap ts_lobby")
	bench_wait_message(caller, "", "Voting failed", "MapFail_Checked", 10.0)
}

public MapFail_Checked(caller)
{
	ASSERT_MSG(caller, "", "Voting failed (yes ^"0^") (no ^"0^") (needed ^"1^")")
	bench_pass()
}

public test_votemap_choice_of_maps()
{
	ASSERT(AddPuppet("choicecaller") > 0)
	ASSERT(AddPuppet("choiceone") > 0)
	ASSERT(AddPuppet("choicetwo") > 0)
	WaitForPuppets("Choice_Ready")
}

public Choice_Ready()
{
	new caller = g_P[0], one = g_P[1], two = g_P[2]
	SetAccess(caller, ADMIN_VOTE)
	// Five maps: only the first four are offered.
	bench_puppet_cmd(caller, "amx_votemap ts_lobby ts_central ts_casa ts_metro ts_awaken")
	ASSERT_MENU(one, "Choose map:")
	ASSERT_MENU(one, "3.  ts_casa")
	ASSERT_MENU(one, "4.  ts_metro")
	ASSERT_MENU(one, "0.  None")
	new menu[1024]
	MenuText(one, menu, charsmax(menu))
	ASSERT_EQ(contain(menu, "ts_awaken"), -1)

	bench_puppet_cmd(one, "menuselect 3")
	ASSERT_MSG(one, "", "choiceone voted for option #3")
	bench_puppet_cmd(two, "menuselect 3")
	bench_wait_message(caller, "ShowMenu", "The result: changelevel ts_casa", "Choice_Result", 10.0)
}

public Choice_Result(caller)
{
	ASSERT_MSG(caller, "", "Voting successful (got ^"2^") (needed ^"1^"). The result: changelevel ts_casa")
	bench_puppet_cmd(caller, "menuselect 2")
	ASSERT_MSG(caller, "", "Result refused")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_votekick and amx_voteban

public test_votekick_unknown_target()
{
	ASSERT(AddPuppet("kicklooker") > 0)
	WaitForPuppets("KickUnknown_Ready")
}

public KickUnknown_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_VOTE)
	bench_puppet_cmd(id, "amx_votekick bench_nobody_here")
	ASSERT_MSG(id, "", "Client with that name or userid not found")
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES, 1))
	bench_pass()
}

public test_votekick_accepted_kicks_target()
{
	ASSERT(AddPuppet("kickcaller") > 0)
	ASSERT(AddPuppet("kicktarget") > 0)
	WaitForPuppets("Kick_Ready")
}

public Kick_Ready()
{
	new caller = g_P[0], target = g_P[1]
	SetAccess(caller, ADMIN_VOTE)
	g_TargetUserId = get_user_userid(target)
	bench_puppet_cmd(caller, "amx_votekick kicktarget")
	ASSERT_MSG(target, "", "vote kick for kicktarget")
	ASSERT_MENU(target, "Kick kicktarget?")
	bench_puppet_cmd(caller, "menuselect 1")
	bench_puppet_cmd(target, "menuselect 1")
	new result[64]
	formatex(result, charsmax(result), "The result: kick #%d", g_TargetUserId)
	bench_wait_message(caller, "ShowMenu", result, "Kick_Result", 10.0)
}

public Kick_Result(caller)
{
	bench_puppet_cmd(caller, "menuselect 1")
	ASSERT_MSG(caller, "", "Result accepted")
	// The kick runs two seconds later.
	ASSERT(is_user_connected(g_P[1]))
	bench_wait_until("TargetGone", "Kick_Done", 10.0)
}

public Kick_Done()
{
	ASSERT(is_user_connected(g_P[0]))
	bench_pass()
}

public test_votekick_from_server_console()
{
	ASSERT(AddPuppet("srvkicktarget") > 0)
	WaitForPuppets("SrvKick_Ready")
}

public SrvKick_Ready()
{
	new target = g_P[0]
	g_P[1] = target
	g_TargetUserId = get_user_userid(target)
	server_cmd("amx_votekick srvkicktarget")
	server_exec()
	ASSERT_MENU(target, "Kick srvkicktarget?")
	bench_puppet_cmd(target, "menuselect 1")
	// With no player to confirm the result, it runs straight away.
	bench_wait_until("TargetGone", "SrvKick_Done", 15.0)
}

public SrvKick_Done()
{
	bench_pass()
}

public test_voteban_refuses_bots()
{
	ASSERT(AddPuppet("botbanner") > 0)
	ASSERT(AddPuppet("benchbot", "", true) > 0)
	WaitForPuppets("BotBan_Ready")
}

public BotBan_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_VOTE)
	bench_puppet_cmd(id, "amx_voteban benchbot")
	ASSERT_MSG(id, "", "That action can't be performed on bot ^"benchbot^"")
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES, 1))
	bench_pass()
}

public test_voteban_by_steam_id()
{
	ASSERT(AddPuppet("bancaller") > 0)
	ASSERT(AddPuppet("bantarget", "STEAM_0:0:4711") > 0)
	WaitForPuppets("SteamBan_Ready")
}

public SteamBan_Ready()
{
	new caller = g_P[0], target = g_P[1]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_voteban bantarget")
	ASSERT_MSG(target, "", "vote ban for bantarget")
	ASSERT_MENU(target, "Ban bantarget?")
	bench_puppet_cmd(caller, "menuselect 1")
	bench_wait_message(caller, "ShowMenu", "The result: banid 30.0 STEAM_0:0:4711 kick", "SteamBan_Result", 10.0)
}

public SteamBan_Result(caller)
{
	bench_puppet_cmd(caller, "menuselect 2")
	ASSERT_MSG(caller, "", "Result refused")
	ASSERT(is_user_connected(g_P[1]))
	bench_pass()
}

public test_voteban_lan_player_by_address()
{
	ASSERT(AddPuppet("lancaller") > 0)
	ASSERT(AddPuppet("lantarget", "STEAM_ID_LAN") > 0)
	WaitForPuppets("LanBan_Ready")
}

public LanBan_Ready()
{
	new caller = g_P[0], target = g_P[1]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_voteban lantarget")
	bench_puppet_cmd(caller, "menuselect 1")
	new ip[32], result[64]
	get_user_ip(target, ip, charsmax(ip), 1)
	formatex(result, charsmax(result), "The result: addip 30.0 %s", ip)
	bench_wait_message(caller, "ShowMenu", result, "LanBan_Result", 10.0)
}

public LanBan_Result(caller)
{
	bench_puppet_cmd(caller, "menuselect 2")
	ASSERT_MSG(caller, "", "Result refused")
	bench_pass()
}
