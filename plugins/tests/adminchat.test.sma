// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for adminchat.sma (Admin Chat): "say @" HUD messages and their colours, "say_team @"
// messages to admins and its flood check, amx_chat, amx_say, amx_psay, amx_tsay and amx_csay,
// under each amx_show_activity setting. An admin puppet gets its access with set_user_flags.
// amx_flood_time is 0 in every test but the flood one, so chat is never held back.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

new g_SavedActivity
new Float:g_SavedFloodTime
new g_Admin
new g_Player
new g_Other
new g_Drained

public plugin_init()
{
	register_plugin("Admin Chat Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("adminchat.sma", 52, 52, "admin.amxx, which plugins.ini requires ('Always one has to be activated'), registers amx_show_activity first")
}

public bench_setup()
{
	g_SavedActivity = get_cvar_num("amx_show_activity")
	g_SavedFloodTime = get_cvar_float("amx_flood_time")
	set_cvar_float("amx_flood_time", 0.0)
	g_Admin = g_Player = g_Other = 0
	g_Drained = 0
}

public bench_teardown()
{
	set_cvar_num("amx_show_activity", g_SavedActivity)
	set_cvar_float("amx_flood_time", g_SavedFloodTime)
}

// Gives a puppet exactly these access flags.
SetFlags(id, const flags[])
{
	remove_user_flags(id, -1)
	set_user_flags(id, read_flags(flags))
}

// Counts the text messages (client_print, console_print) of one kind sent to id containing text:
// print_notify, print_console or print_chat.
CountPrint(id, dest, const text[])
{
	new count, BenchMsg:msg
	while ((msg = bench_msg_next(id, msg, "TextMsg", text)) != BenchMsg:0)
	{
		if (bench_msg_int(msg, 0) == dest)
			count++
	}
	return count
}

// An admin with ADMIN_CHAT ("i"), a plain player ("z") and, if wanted, a second plain player.
Start(const step[], bool:other = false)
{
	g_Admin = bench_puppet("chatadmin")
	g_Player = bench_puppet("plainguy")
	ASSERT(g_Admin > 0 && g_Player > 0)
	if (other)
	{
		g_Other = bench_puppet("bystander")
		ASSERT(g_Other > 0)
	}
	bench_next(step, 0.1)
}

Flags()
{
	SetFlags(g_Admin, "i")
	SetFlags(g_Player, "z")
	if (g_Other)
		SetFlags(g_Other, "z")
}

// ---------------------------------------------------------------------------------------------
// say @

public test_say_at_needs_chat_access()
{
	Start("say_at_without_access")
}

public say_at_without_access()
{
	Flags()
	bench_puppet_say(g_Player, "@notforyou")
	ASSERT_EQ(bench_msg_count(g_Player, "", "plainguy :   notforyou"), 0)
	ASSERT_EQ(bench_msg_count(g_Admin, "", "plainguy :   notforyou"), 0)
	bench_pass()
}

public test_say_without_at_or_too_many_is_ordinary_chat()
{
	Start("say_ordinary")
}

public say_ordinary()
{
	Flags()
	bench_puppet_say(g_Admin, "nohud")
	bench_puppet_say(g_Admin, "@@@@fourats")
	ASSERT_EQ(bench_msg_count(g_Player, "", ":   nohud"), 0)
	ASSERT_EQ(bench_msg_count(g_Player, "", ":   fourats"), 0)
	ASSERT_EQ(bench_msg_count(g_Player, "", ":   @fourats"), 0)
	bench_pass()
}

public test_say_at_colours_and_positions()
{
	Start("say_colours")
}

public say_colours()
{
	Flags()
	set_cvar_num("amx_show_activity", 2)
	bench_puppet_say(g_Admin, "@r redtext")
	bench_puppet_say(g_Admin, "@g greentext")
	bench_puppet_say(g_Admin, "@b bluetext")
	bench_puppet_say(g_Admin, "@y yellowtext")
	bench_puppet_say(g_Admin, "@m magentatext")
	bench_puppet_say(g_Admin, "@c cyantext")
	bench_puppet_say(g_Admin, "@o orangetext")
	bench_puppet_say(g_Admin, "@  plaintext")
	bench_puppet_say(g_Admin, "@@r secondrow")
	bench_puppet_say(g_Admin, "@@@thirdrow")
	// amx_show_activity 2: everyone sees the admin's name.
	ASSERT_MSG(g_Player, "", "chatadmin :   redtext")
	ASSERT_MSG(g_Player, "", "chatadmin :   greentext")
	ASSERT_MSG(g_Player, "", "chatadmin :   bluetext")
	ASSERT_MSG(g_Player, "", "chatadmin :   yellowtext")
	ASSERT_MSG(g_Player, "", "chatadmin :   magentatext")
	ASSERT_MSG(g_Player, "", "chatadmin :   cyantext")
	ASSERT_MSG(g_Player, "", "chatadmin :   orangetext")
	ASSERT_MSG(g_Player, "", "chatadmin :   plaintext")
	ASSERT_MSG(g_Player, "", "chatadmin :   secondrow")
	ASSERT_MSG(g_Player, "", "chatadmin :   thirdrow")
	bench_pass()
}

// The usage text offers "w" for white, but the switch has no case for it: the letter stays in
// the message.
public test_say_at_w_is_white()
{
	bench_describe("say @w is white")
	Start("say_white")
}

public say_white()
{
	Flags()
	set_cvar_num("amx_show_activity", 2)
	bench_puppet_say(g_Admin, "@w whitetext")
	ASSERT_MSG(g_Player, "", "whitetext")
	ASSERT_MSG(g_Player, "", "chatadmin :   whitetext")
	bench_pass()
}

public test_say_at_activity_3_names_only_to_admins()
{
	Start("say_activity_3")
}

public say_activity_3()
{
	Flags()
	set_cvar_num("amx_show_activity", 3)
	bench_puppet_say(g_Admin, "@r forstaff")
	ASSERT_MSG(g_Admin, "", "chatadmin :   forstaff")
	ASSERT_MSG(g_Player, "", "forstaff")
	ASSERT_EQ(bench_msg_count(g_Player, "", "chatadmin :   forstaff"), 0)
	bench_pass()
}

public test_say_at_activity_1_hides_name()
{
	Start("say_activity_1")
}

public say_activity_1()
{
	Flags()
	set_cvar_num("amx_show_activity", 1)
	bench_puppet_say(g_Admin, "@g anonymous")
	ASSERT_MSG(g_Admin, "", "anonymous")
	ASSERT_MSG(g_Player, "", "anonymous")
	ASSERT_EQ(bench_msg_count(g_Player, "", "chatadmin :   anonymous"), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// say_team @

public test_say_team_at_reaches_admins_only()
{
	Start("say_team_at", true)
}

public say_team_at()
{
	Flags()
	bench_puppet_say(g_Player, "@helpme", true)
	ASSERT_MSG(g_Player, "", "(PLAYER) plainguy :  helpme")
	ASSERT_MSG(g_Admin, "", "(PLAYER) plainguy :  helpme")
	ASSERT_EQ(bench_msg_count(g_Other, "", "helpme"), 0)

	bench_puppet_say(g_Admin, "@onit", true)
	ASSERT_MSG(g_Admin, "", "(ADMIN) chatadmin :  onit")
	ASSERT_EQ(bench_msg_count(g_Player, "", "onit"), 0)

	// Without the @ it is ordinary team chat.
	bench_puppet_say(g_Player, "teamonly", true)
	ASSERT_EQ(bench_msg_count(g_Admin, "", "(PLAYER) plainguy :  teamonly"), 0)
	bench_pass()
}

public test_say_team_at_flood()
{
	Start("say_team_flood")
}

public say_team_flood()
{
	Flags()
	set_cvar_float("amx_flood_time", 0.75)
	for (new i = 1; i <= 4; i++)
		bench_puppet_say(g_Player, fmt("@teamflood%d", i), true)
	ASSERT_EQ(bench_msg_count(g_Player, "", "Stop flooding the server!"), 0)
	bench_puppet_say(g_Player, "@teamflood5", true)
	ASSERT_EQ(bench_msg_count(g_Player, "", "Stop flooding the server!"), 1)
	ASSERT_MSG(g_Admin, "", "teamflood4")
	ASSERT_EQ(bench_msg_count(g_Admin, "", "teamflood5"), 0)
	bench_next("team_drain", 4.0)
}

public team_drain()
{
	// Lines after the window take the count back down to zero.
	bench_puppet_say(g_Player, "@calm", true)
	ASSERT_EQ(bench_msg_count(g_Player, "", "Stop flooding the server!"), 1)
	if (++g_Drained < 3)
	{
		bench_next("team_drain", 1.0)
		return
	}
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_chat, amx_say

public test_amx_chat()
{
	Start("amx_chat", true)
}

public amx_chat()
{
	Flags()
	bench_puppet_cmd(g_Player, "amx_chat ^"sneaky^"")
	ASSERT_MSG(g_Player, "TextMsg", "You have no access to that command")
	ASSERT_EQ(bench_msg_count(g_Admin, "", "sneaky"), 0)

	// An empty message is dropped.
	bench_puppet_cmd(g_Admin, "amx_chat ^"^"")
	ASSERT_EQ(bench_msg_count(g_Admin, "", "(ADMINS)"), 0)

	bench_puppet_cmd(g_Admin, "amx_chat staff only")
	ASSERT_EQ(CountPrint(g_Admin, print_console, "(ADMINS) chatadmin :   staff only"), 1)
	ASSERT_EQ(CountPrint(g_Admin, print_chat, "(ADMINS) chatadmin :   staff only"), 1)
	ASSERT_EQ(bench_msg_count(g_Player, "", "staff only"), 0)
	bench_pass()
}

public test_amx_say()
{
	Start("amx_say")
}

public amx_say()
{
	Flags()
	bench_puppet_cmd(g_Admin, "amx_say")
	ASSERT_MSG(g_Admin, "TextMsg", "Usage:  amx_say <message>")
	bench_puppet_cmd(g_Admin, "amx_say hello everyone")
	ASSERT_EQ(CountPrint(g_Player, print_chat, "(ALL) chatadmin :   hello everyone"), 1)
	ASSERT_EQ(CountPrint(g_Admin, print_console, "(ALL) chatadmin :   hello everyone"), 1)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_psay

public test_amx_psay()
{
	Start("amx_psay", true)
}

public amx_psay()
{
	Flags()
	bench_puppet_cmd(g_Admin, "amx_psay plainguy")
	ASSERT_MSG(g_Admin, "TextMsg", "Usage:  amx_psay <name or #userid> <message>")
	bench_puppet_cmd(g_Admin, "amx_psay nobodyhere hi")
	ASSERT_MSG(g_Admin, "TextMsg", "Client with that name or userid not found")

	bench_puppet_cmd(g_Admin, "amx_psay plainguy just between us")
	ASSERT_EQ(CountPrint(g_Player, print_chat, "(plainguy) chatadmin :   just between us"), 1)
	ASSERT_EQ(CountPrint(g_Admin, print_chat, "(plainguy) chatadmin :   just between us"), 1)
	ASSERT_EQ(CountPrint(g_Admin, print_console, "(plainguy) chatadmin :   just between us"), 1)
	ASSERT_EQ(bench_msg_count(g_Other, "", "just between us"), 0)

	// HLSW quotes the name.
	bench_puppet_cmd(g_Admin, "amx_psay ^"plainguy^" quoted name")
	ASSERT_MSG(g_Player, "", "(plainguy) chatadmin :   quoted name")

	// To oneself: one copy, not two.
	bench_puppet_cmd(g_Admin, "amx_psay chatadmin note to self")
	ASSERT_EQ(CountPrint(g_Admin, print_chat, "(chatadmin) chatadmin :   note to self"), 1)

	// From the server console.
	server_cmd("amx_psay bystander from the server")
	server_exec()
	ASSERT_MSG(g_Other, "", ":   from the server")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_tsay, amx_csay

public test_amx_tsay_colour_and_activity_2()
{
	Start("tsay_2")
}

public tsay_2()
{
	Flags()
	set_cvar_num("amx_show_activity", 2)
	bench_puppet_cmd(g_Admin, "amx_tsay red left side")
	ASSERT_EQ(CountPrint(g_Player, print_notify, "chatadmin :   left side"), 1)
	ASSERT_EQ(CountPrint(g_Admin, print_console, "chatadmin :  left side"), 1)
	// An unknown colour is part of the message.
	bench_puppet_cmd(g_Admin, "amx_csay purple centre")
	ASSERT_MSG(g_Player, "", "chatadmin :   purple centre")
	bench_pass()
}

public test_amx_tsay_activity_3()
{
	Start("tsay_3")
}

public tsay_3()
{
	Flags()
	set_cvar_num("amx_show_activity", 3)
	bench_puppet_cmd(g_Admin, "amx_csay green staffnamed")
	ASSERT_MSG(g_Admin, "", "chatadmin :   staffnamed")
	ASSERT_MSG(g_Player, "", "staffnamed")
	ASSERT_EQ(bench_msg_count(g_Player, "", "chatadmin :   staffnamed"), 0)
	ASSERT_EQ(CountPrint(g_Admin, print_console, "chatadmin :  staffnamed"), 1)
	bench_pass()
}

public test_amx_tsay_activity_0()
{
	Start("tsay_0")
}

public tsay_0()
{
	Flags()
	set_cvar_num("amx_show_activity", 0)
	bench_puppet_cmd(g_Admin, "amx_tsay blue nameless")
	ASSERT_MSG(g_Player, "", "nameless")
	ASSERT_EQ(bench_msg_count(g_Player, "", "chatadmin :   nameless"), 0)
	ASSERT_EQ(CountPrint(g_Admin, print_console, "nameless"), 1)
	// Too few arguments.
	bench_puppet_cmd(g_Admin, "amx_tsay blue")
	ASSERT_MSG(g_Admin, "TextMsg", "Usage:  amx_tsay")
	bench_pass()
}
