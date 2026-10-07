// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for adminhelp.sma (Admin Help): amx_help pages, amx_searchcmd matches and pages, the
// per-page amount, admins seeing ADMIN_ADMIN commands, and the help message a player gets after
// joining, with and without a time limit. The expected counts and first entries are read with the
// same natives the plugin uses (get_concmdsnum, get_concmd).
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

new g_SavedDisplay
new g_SavedDisplayTime
new g_SavedPerPage
new Float:g_SavedTimeLimit
new bool:g_ConfigsExecuted
new g_Puppet

public plugin_init()
{
	register_plugin("Admin Help Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public OnConfigsExecuted()
{
	// adminhelp binds mp_timelimit and amx_nextmap here.
	g_ConfigsExecuted = true
}

public bench_setup()
{
	g_SavedDisplay = get_cvar_num("amx_help_display_msg")
	g_SavedDisplayTime = get_cvar_num("amx_help_display_msg_time")
	g_SavedPerPage = get_cvar_num("amx_help_amount_per_page")
	g_SavedTimeLimit = get_cvar_float("mp_timelimit")
	g_Puppet = 0
}

public bench_teardown()
{
	set_cvar_num("amx_help_display_msg", g_SavedDisplay)
	set_cvar_num("amx_help_display_msg_time", g_SavedDisplayTime)
	set_cvar_num("amx_help_amount_per_page", g_SavedPerPage)
	set_cvar_float("mp_timelimit", g_SavedTimeLimit)
}

SetFlags(id, const flags[])
{
	remove_user_flags(id, -1)
	set_user_flags(id, read_flags(flags))
}

// The number of commands amx_help lists for id, with its flags as ProcessHelp sees them.
HelpCount(id)
{
	new flags = get_user_flags(id)
	if (flags > 0 && !(flags & ADMIN_USER))
		flags |= ADMIN_ADMIN
	return get_concmdsnum(flags, id)
}

// The name of entry index (0-based) of that list.
HelpCommand(id, index, command[], len)
{
	new flags = get_user_flags(id), cmdflags, info[2], bool:info_ml
	if (flags > 0 && !(flags & ADMIN_USER))
		flags |= ADMIN_ADMIN
	get_concmd(index, command, len, cmdflags, info, charsmax(info), flags, id, info_ml)
}

StartPlayer(const flags[], const step[])
{
	set_cvar_num("amx_help_display_msg", 0)
	g_Puppet = bench_puppet("helpreader")
	ASSERT(g_Puppet > 0)
	SetFlags(g_Puppet, flags)
	bench_next(step, 0.1)
}

public test_help_first_page()
{
	StartPlayer("z", "help_first_page")
}

public help_first_page()
{
	set_cvar_num("amx_help_amount_per_page", 10)
	new count = HelpCount(g_Puppet), first[32], eleventh[32]
	ASSERT(count > 10)
	HelpCommand(g_Puppet, 0, first, charsmax(first))
	HelpCommand(g_Puppet, 10, eleventh, charsmax(eleventh))
	bench_puppet_cmd(g_Puppet, "amx_help")
	ASSERT_MSG(g_Puppet, "", "----- AMX Mod X Help: Commands -----")
	ASSERT_MSG(g_Puppet, "", fmt("  1: %s ", first))
	ASSERT_EQ(bench_msg_count(g_Puppet, "", fmt(" 11: %s ", eleventh)), 0)
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries 1 - 10 of %d -----", count))
	ASSERT_MSG(g_Puppet, "", "----- Use 'amx_help 11' for more -----")
	bench_pass()
}

public test_help_later_and_last_pages()
{
	StartPlayer("z", "help_later_pages")
}

public help_later_pages()
{
	set_cvar_num("amx_help_amount_per_page", 10)
	new count = HelpCount(g_Puppet), eleventh[32]
	ASSERT(count > 10)
	HelpCommand(g_Puppet, 10, eleventh, charsmax(eleventh))
	bench_puppet_cmd(g_Puppet, "amx_help 11")
	ASSERT_MSG(g_Puppet, "", fmt(" 11: %s ", eleventh))
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries 11 - %d of %d -----", min(20, count), count))

	// The last page points back to the beginning; a start past the end is clamped to the last
	// entry.
	bench_puppet_cmd(g_Puppet, "amx_help 9999")
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries %d - %d of %d -----", count, count, count))
	ASSERT_MSG(g_Puppet, "", "----- Use 'amx_help 1' for begin -----")
	bench_pass()
}

public test_help_amount_per_page()
{
	StartPlayer("z", "help_amount")
}

public help_amount()
{
	new count = HelpCount(g_Puppet)
	set_cvar_num("amx_help_amount_per_page", 5)
	bench_puppet_cmd(g_Puppet, "amx_help")
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries 1 - 5 of %d -----", count))
	ASSERT_MSG(g_Puppet, "", "----- Use 'amx_help 6' for more -----")

	// 0 falls back to ten.
	set_cvar_num("amx_help_amount_per_page", 0)
	bench_puppet_cmd(g_Puppet, "amx_help")
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries 1 - 10 of %d -----", count))

	// Everything on one page: no pointer to more, nor back to the beginning.
	set_cvar_num("amx_help_amount_per_page", 1000)
	bench_puppet_cmd(g_Puppet, "amx_help")
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries 1 - %d of %d -----", count, count))
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "for begin"), 0)
	// Its own entry, whose info is a language key, is shown translated.
	ASSERT_MSG(g_Puppet, "", ": amx_help <entry no.> [no. of entries to display (server only)] - displays information about available commands")
	bench_pass()
}

public test_admin_sees_admin_commands()
{
	StartPlayer("abcdefghijklmnopqrstu", "admin_help")
}

public admin_help()
{
	set_cvar_num("amx_help_amount_per_page", 10)
	// ProcessHelp adds ADMIN_ADMIN for an admin, so amx_who and amx_plugins are listed.
	new count = HelpCount(g_Puppet)
	new without = get_concmdsnum(get_user_flags(g_Puppet), g_Puppet)
	ASSERT(count > without)
	bench_puppet_cmd(g_Puppet, "amx_help")
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries 1 - 10 of %d -----", count))
	bench_puppet_cmd(g_Puppet, "amx_searchcmd amx_who")
	ASSERT_MSG(g_Puppet, "", "  1: amx_who - displays who is on server")
	bench_pass()
}

public test_search()
{
	StartPlayer("z", "search")
}

public search()
{
	set_cvar_num("amx_help_amount_per_page", 10)
	// A single match, with its language-key info translated.
	bench_puppet_cmd(g_Puppet, "amx_searchcmd searchcmd")
	ASSERT_MSG(g_Puppet, "", "  1: amx_searchcmd <match> <entry no.>")
	ASSERT_MSG(g_Puppet, "", "----- Entries 1 - 1 of 1 -----")
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Use 'amx_searchcmd"), 0)

	bench_puppet_cmd(g_Puppet, "amx_searchcmd zzqqnothing")
	ASSERT_MSG(g_Puppet, "", "No matching results found")

	// Starting past the only match finds nothing either.
	bench_puppet_cmd(g_Puppet, "amx_searchcmd searchcmd 5")
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "No matching results found"), 2)
	bench_pass()
}

public test_search_pages()
{
	StartPlayer("z", "search_pages")
}

public search_pages()
{
	set_cvar_num("amx_help_amount_per_page", 1)
	// Count the commands with amx_ in their name.
	new flags = get_user_flags(g_Puppet), count = get_concmdsnum(flags, g_Puppet), matches
	new command[32], cmdflags, info[2], bool:info_ml
	for (new i = 0; i < count; i++)
	{
		get_concmd(i, command, charsmax(command), cmdflags, info, charsmax(info), flags, g_Puppet, info_ml)
		if (containi(command, "amx_") != -1)
			matches++
	}
	ASSERT(matches >= 3)
	bench_puppet_cmd(g_Puppet, "amx_searchcmd amx_")
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries 1 - 1 of %d -----", matches))
	ASSERT_MSG(g_Puppet, "", "----- Use 'amx_searchcmd amx_ 2' for more -----")
	bench_puppet_cmd(g_Puppet, "amx_searchcmd amx_ 2")
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries 2 - 2 of %d -----", matches))
	bench_puppet_cmd(g_Puppet, fmt("amx_searchcmd amx_ %d", matches))
	ASSERT_MSG(g_Puppet, "", fmt("----- Entries %d - %d of %d -----", matches, matches, matches))
	ASSERT_MSG(g_Puppet, "", "----- Use 'amx_searchcmd amx_ 1' for begin -----")
	bench_pass()
}

public test_server_console_help()
{
	set_cvar_num("amx_help_amount_per_page", 10)
	new count = HelpCount(0), first[32], fourth[32]
	ASSERT(count > 12)
	HelpCommand(0, 0, first, charsmax(first))
	HelpCommand(0, 3, fourth, charsmax(fourth))

	// The server console may ask for any number of entries.
	server_cmd("amx_help 1 3")
	server_exec()
	ASSERT_MSG(0, "server", "----- AMX Mod X Help: Commands -----")
	ASSERT_MSG(0, "server", fmt("  1: %s ", first))
	ASSERT_EQ(bench_msg_count(0, "server", fmt("  4: %s ", fourth)), 0)
	ASSERT_MSG(0, "server", fmt("----- Entries 1 - 3 of %d -----", count))
	ASSERT_MSG(0, "server", "----- Use 'amx_help 4' for more -----")

	// No amount: the per-page amount.
	server_cmd("amx_help 2 0")
	server_exec()
	ASSERT_MSG(0, "server", fmt("----- Entries 2 - 11 of %d -----", count))

	// Searches too.
	new flags = get_user_flags(0), matches
	new command[32], cmdflags, info[2], bool:info_ml
	if (flags > 0 && !(flags & ADMIN_USER))
		flags |= ADMIN_ADMIN
	for (new i = 0; i < count; i++)
	{
		get_concmd(i, command, charsmax(command), cmdflags, info, charsmax(info), flags, 0, info_ml)
		if (containi(command, "amx_") != -1)
			matches++
	}
	ASSERT(matches > 2)
	server_cmd("amx_searchcmd amx_ 1 2")
	server_exec()
	ASSERT_MSG(0, "server", fmt("----- Entries 1 - 2 of %d -----", matches))
	ASSERT_MSG(0, "server", "----- Use 'amx_searchcmd amx_ 3' for more -----")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The message after joining

public test_join_message_with_time_left()
{
	bench_wait_until("configs_executed", "join_with_time_left", 15.0)
}

public configs_executed()
{
	return g_ConfigsExecuted
}

public join_with_time_left()
{
	set_cvar_num("amx_help_display_msg", 1)
	set_cvar_num("amx_help_display_msg_time", 1)
	set_cvar_float("mp_timelimit", 30.0)
	g_Puppet = bench_puppet("newcomer")
	ASSERT(g_Puppet > 0)
	bench_wait_message(g_Puppet, "", "Type 'amx_help' 'amx_searchcmd' in the console to see available commands", "time_left_shown", 5.0)
}

public time_left_shown()
{
	new nextmap[32]
	get_cvar_string("amx_nextmap", nextmap, charsmax(nextmap))
	ASSERT_MSG(g_Puppet, "", "Time Left: ")
	ASSERT_MSG(g_Puppet, "", fmt(" min. Next Map: %s", nextmap))
	bench_pass()
}

public test_join_message_without_time_limit()
{
	bench_wait_until("configs_executed", "join_without_time_limit", 15.0)
}

public join_without_time_limit()
{
	set_cvar_num("amx_help_display_msg", 1)
	set_cvar_num("amx_help_display_msg_time", 1)
	set_cvar_float("mp_timelimit", 0.0)
	g_Puppet = bench_puppet("notimer")
	ASSERT(g_Puppet > 0)
	bench_wait_message(g_Puppet, "", "Type 'amx_help'", "no_time_info", 5.0)
}

public no_time_info()
{
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Time Left"), 0)
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Next Map"), 0)
	bench_pass()
}

public test_join_message_when_time_is_up()
{
	bench_wait_until("configs_executed", "time_is_up", 15.0)
}

public time_is_up()
{
	set_cvar_num("amx_help_display_msg", 0)
	g_Puppet = bench_puppet("lastminute")
	ASSERT(g_Puppet > 0)
	// A time limit that has already run out. The game would end the map on its next frame, so
	// the message is shown and the limit put back within this one.
	set_cvar_float("mp_timelimit", 0.001)
	new timeleft = get_timeleft()
	new ok = callfunc_begin("@Task_DisplayMessage", "adminhelp.amxx")
	if (ok == 1)
	{
		callfunc_push_int(g_Puppet)
		callfunc_end()
	}
	set_cvar_float("mp_timelimit", g_SavedTimeLimit)
	ASSERT_EQ(timeleft, 0)
	ASSERT_EQ(ok, 1)
	new nextmap[32]
	get_cvar_string("amx_nextmap", nextmap, charsmax(nextmap))
	ASSERT(nextmap[0] != EOS)
	ASSERT_MSG(g_Puppet, "", fmt("No Time Limit. Next Map: %s", nextmap))
	bench_pass()
}

public test_no_join_message_when_disabled()
{
	set_cvar_num("amx_help_display_msg", 0)
	set_cvar_num("amx_help_display_msg_time", 1)
	g_Puppet = bench_puppet("quietjoin")
	ASSERT(g_Puppet > 0)
	bench_next("no_message", 2.0)
}

public no_message()
{
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Type 'amx_help'"), 0)
	bench_pass()
}

public test_leaving_before_the_message()
{
	// A player who leaves before the message is due has it cancelled; the next player in the
	// slot gets their own.
	set_cvar_num("amx_help_display_msg", 1)
	set_cvar_num("amx_help_display_msg_time", 0)
	g_Puppet = bench_puppet("shortstay")
	ASSERT(g_Puppet > 0)
	ASSERT(task_exists(g_Puppet, 1))
	server_cmd("kick #%d", get_user_userid(g_Puppet))
	server_exec()
	bench_next("cancelled", 0.2)
}

public cancelled()
{
	ASSERT_FALSE(is_user_connected(g_Puppet))
	ASSERT_FALSE(task_exists(g_Puppet, 1))
	bench_pass()
}
