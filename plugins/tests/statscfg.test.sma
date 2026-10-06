// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for statscfg.sma (Stats Configuration): amx_statscfg on/off/save/load/list and the
// amx_statscfgmenu menu, driven by an admin puppet. The options are the 21 TS Stats adds in its
// plugin_cfg. TS Stats' switches and configs/stats.ini are put back after every test (a saved
// copy, or a marker for "there was none", left by an interrupted run is restored first).
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#define OPTIONS 21

new const g_Vars[OPTIONS][] =
{
	"EndPlayer", "EndTop15", "SayStatsAll", "SayTop15", "SayRank", "SayStatsMe", "ShowAttackers",
	"ShowVictims", "ShowKiller", "KillerHp", "SayHP", "SayFF", "GrenadeKill", "GrenadeSuicide",
	"HeadShotKill", "HeadShotKillSound", "DoubleKill", "DoubleKillSound", "BulletDamage", "TAInfo",
	"FragInfo"
}

new g_Saved[OPTIONS]
new g_StatsFile[PLATFORM_MAX_PATH]
new g_SavedFile[PLATFORM_MAX_PATH]
new g_AbsentMarker[PLATFORM_MAX_PATH]
new g_Puppet

public plugin_init()
{
	register_plugin("Stats Configuration Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("statscfg.sma", 189, 189, "the first page always starts inside the list unless it is empty, and TS Stats always adds 21 options")
	bench_coverage_ignore("statscfg.sma", 210, 210, "TS Stats always adds 21 options in plugin_cfg on this server, so the list is never empty")
}

public bench_setup()
{
	get_configsdir(g_StatsFile, charsmax(g_StatsFile))
	formatex(g_SavedFile, charsmax(g_SavedFile), "%s/stats.ini.bench", g_StatsFile)
	formatex(g_AbsentMarker, charsmax(g_AbsentMarker), "%s/stats.ini.bench-absent", g_StatsFile)
	add(g_StatsFile, charsmax(g_StatsFile), "/stats.ini")

	// A saved copy or marker already there is from a run that stopped before teardown: the file
	// now in place is that run's, the saved one (or none) is the server's.
	if (file_exists(g_SavedFile) || file_exists(g_AbsentMarker))
		delete_file(g_StatsFile)
	else if (file_exists(g_StatsFile))
		rename_file(g_StatsFile, g_SavedFile, 1)
	else
		write_file(g_AbsentMarker, "stats.ini did not exist")

	for (new i = 0; i < OPTIONS; i++)
		g_Saved[i] = get_xvar_num(get_xvar_id(g_Vars[i]))
	g_Puppet = 0
}

public bench_teardown()
{
	for (new i = 0; i < OPTIONS; i++)
		set_xvar_num(get_xvar_id(g_Vars[i]), g_Saved[i])
	// A successful save clears the "modified" mark the menu shows; the file goes away next.
	server_cmd("amx_statscfg save")
	server_exec()

	delete_file(g_StatsFile)
	if (file_exists(g_SavedFile))
		rename_file(g_SavedFile, g_StatsFile, 1)
	delete_file(g_AbsentMarker)
}

Option(const name[])
{
	return get_xvar_num(get_xvar_id(name))
}

bool:StartAdmin(const name[], flags = ADMIN_CFG)
{
	g_Puppet = bench_puppet(name)
	if (!bench_check(g_Puppet > 0, "puppet created"))
		return false
	remove_user_flags(g_Puppet)
	set_user_flags(g_Puppet, flags)
	return true
}

Cfg(const args[])
{
	bench_puppet_cmd(g_Puppet, "amx_statscfg %s", args)
}

// A line of "amx_statscfg list": number, name, variable, On/Off.
bool:ListLine(number, const name[], const variable[], const status[])
{
	new expected[128]
	formatex(expected, charsmax(expected), "%3d: %-29.28s   %-24.23s   %-9.8s", number, name, variable, status)
	return __bench_msg(g_Puppet, "TextMsg", expected)
}

// A line of stats.ini: the variable in 24 columns, then the name as a comment.
bool:SavedLine(const line[], const variable[], const name[])
{
	new expected[128]
	formatex(expected, charsmax(expected), "%-24.23s ;%s", variable, name)
	return __bench_str_eq(line, expected)
}

AllOff()
{
	for (new i = 0; i < OPTIONS; i++)
		set_xvar_num(get_xvar_id(g_Vars[i]), 0)
}

public test_needs_cfg_access()
{
	if (!StartAdmin("nocfg", ADMIN_KICK))
		return
	AllOff()
	Cfg("on SayFF")
	ASSERT_MSG(g_Puppet, "TextMsg", "You have no access to that command")
	ASSERT_EQ(Option("SayFF"), 0)
	bench_puppet_cmd(g_Puppet, "amx_statscfgmenu")
	ASSERT_EQ(bench_msg_count(g_Puppet, "ShowMenu"), 0)
	bench_pass()
}

public test_usage()
{
	if (!StartAdmin("usage"))
		return
	bench_puppet_cmd(g_Puppet, "amx_statscfg")
	ASSERT_MSG(g_Puppet, "TextMsg", "Usage:  amx_statscfg <command> [parameters] ...")
	ASSERT_MSG(g_Puppet, "TextMsg", "on <variable> - enable specified option")
	ASSERT_MSG(g_Puppet, "TextMsg", "add <name> <variable> - add stats to the list")
	// "on" without a variable is not a command either.
	Cfg("on")
	ASSERT_EQ(bench_msg_count(g_Puppet, "TextMsg", "Usage:  amx_statscfg"), 2)
	bench_pass()
}

public test_on_and_off_by_variable()
{
	if (!StartAdmin("switcher"))
		return
	AllOff()
	Cfg("on SayFF")
	ASSERT_MSG(g_Puppet, "TextMsg", "Stats enabled: Say /ff")
	ASSERT_MSG(g_Puppet, "TextMsg", "Total 1")
	ASSERT_EQ(Option("SayFF"), 1)
	Cfg("off sayff")
	ASSERT_MSG(g_Puppet, "TextMsg", "Stats disabled: Say /ff")
	ASSERT_EQ(Option("SayFF"), 0)
	bench_pass()
}

public test_on_by_part_of_a_variable()
{
	if (!StartAdmin("partial"))
		return
	AllOff()
	// SayStatsAll, SayTop15, SayRank, SayStatsMe, SayHP and SayFF.
	Cfg("on say")
	ASSERT_MSG(g_Puppet, "TextMsg", "Total 6")
	ASSERT_EQ(Option("SayTop15"), 1)
	ASSERT_EQ(Option("SayHP"), 1)
	ASSERT_EQ(Option("EndPlayer"), 0)
	bench_pass()
}

public test_unknown_variable()
{
	if (!StartAdmin("unknown"))
		return
	Cfg("on NoSuchStats")
	ASSERT_MSG(g_Puppet, "TextMsg", "Couldn't find option(s) with such variable (name ^"NoSuchStats^")")
	bench_pass()
}

public test_save_writes_enabled_options()
{
	if (!StartAdmin("saver"))
		return
	AllOff()
	Cfg("on SayRank")
	Cfg("on FragInfo")
	Cfg("save")
	ASSERT_MSG(g_Puppet, "TextMsg", "Stats configuration saved successfully")

	new line[128], len
	ASSERT(read_file(g_StatsFile, 0, line, charsmax(line), len))
	ASSERT_STR_EQ(line, ";Generated by Stats Configuration Plugin. Do not modify!")
	ASSERT(read_file(g_StatsFile, 2, line, charsmax(line), len))
	if (!SavedLine(line, "SayRank", "Say /rank")) return
	ASSERT(read_file(g_StatsFile, 3, line, charsmax(line), len))
	if (!SavedLine(line, "FragInfo", "Frag Info")) return
	ASSERT_FALSE(read_file(g_StatsFile, 4, line, charsmax(line), len))
	bench_pass()
}

public test_load_enables_listed_options()
{
	if (!StartAdmin("loader"))
		return
	AllOff()
	new f = fopen(g_StatsFile, "wt")
	fputs(f, "; a comment naming SayFF^n")
	fputs(f, "SayRank    ;Say /rank^n")
	fputs(f, "NoSuchStats ;ignored^n")
	fputs(f, "TAInfo^n")
	fclose(f)
	Cfg("load")
	ASSERT_MSG(g_Puppet, "TextMsg", "Stats configuration loaded successfully")
	ASSERT_EQ(Option("SayRank"), 1)
	ASSERT_EQ(Option("TAInfo"), 1)
	ASSERT_EQ(Option("SayFF"), 0)
	bench_pass()
}

public test_load_without_a_file()
{
	if (!StartAdmin("noload"))
		return
	delete_file(g_StatsFile)
	Cfg("load")
	ASSERT_MSG(g_Puppet, "TextMsg", "Failed to load stats configuration!!!")
	bench_pass()
}

public test_list_first_page()
{
	if (!StartAdmin("lister"))
		return
	AllOff()
	Cfg("on EndTop15")
	Cfg("list")
	ASSERT_MSG(g_Puppet, "TextMsg", "----- Stats Configuration: -----")
	if (!ListLine(1, "Stats at the end of map", "EndPlayer", "Off")) return
	if (!ListLine(2, "Top15 at the end of map", "EndTop15", "On")) return
	if (!ListLine(10, "Show killer hp", "KillerHp", "Off")) return
	ASSERT_EQ(bench_msg_count(g_Puppet, "TextMsg", " 11: "), 0)
	ASSERT_MSG(g_Puppet, "TextMsg", "----- Entries 1 - 10 of 21 -----")
	ASSERT_MSG(g_Puppet, "TextMsg", "----- Use 'amx_statscfg list 11' for more -----")
	bench_pass()
}

// statscfg.sma:125 asks for the "VARIABLE" key, which no dictionary has (NAME and STATUS come from
// admincmd.txt, loaded by Admin Commands).
public test_list_header_names_the_columns()
{
	if (!StartAdmin("header"))
		return
	Cfg("list")
	new BenchMsg:msg = bench_msg_last(g_Puppet, "TextMsg", "----- Stats Configuration: -----")
	ASSERT(msg != BenchMsg:0)
	msg = bench_msg_next(g_Puppet, msg, "TextMsg")
	ASSERT(msg != BenchMsg:0)
	new text[128], expected[128]
	bench_msg_string(msg, 1, text, charsmax(text))
	replace_all(text, charsmax(text), "^n", "")
	formatex(expected, charsmax(expected), "     %-29.28s   %-24.23s   %-9.8s", "name", "variable", "status")
	ASSERT_STR_EQ(text, expected)
	bench_pass()
}

public test_list_last_page()
{
	if (!StartAdmin("lastpage"))
		return
	Cfg("list 15")
	ASSERT_MSG(g_Puppet, "TextMsg", " 15: HeadShot Kill")
	ASSERT_MSG(g_Puppet, "TextMsg", " 21: Frag Info")
	ASSERT_EQ(bench_msg_count(g_Puppet, "TextMsg", " 14: "), 0)
	ASSERT_MSG(g_Puppet, "TextMsg", "----- Entries 15 - 21 of 21 -----")
	ASSERT_MSG(g_Puppet, "TextMsg", "----- Use 'amx_statscfg list 1' for begin -----")
	bench_pass()
}

public test_list_out_of_range()
{
	if (!StartAdmin("range"))
		return
	// Past the end: the last entry alone.
	Cfg("list 100")
	ASSERT_MSG(g_Puppet, "TextMsg", "----- Entries 21 - 21 of 21 -----")
	// 0 and below: from the first.
	Cfg("list 0")
	ASSERT_MSG(g_Puppet, "TextMsg", "----- Entries 1 - 10 of 21 -----")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The menu: seven options a page, 8 saves, 9 is More, 0 Back or Exit.

// The newest menu sent to the puppet. A long one comes in several ShowMenu messages, each but the
// last with its "more" byte set.
LastMenu(text[], len)
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

bool:MenuHas(const part[])
{
	new text[512]
	LastMenu(text, charsmax(text))
	if (contain(text, part) != -1)
		return true
	bench_fail("menu ^"%s^" has no ^"%s^"", text, part)
	return false
}

public test_menu_pages()
{
	if (!StartAdmin("menupager"))
		return
	AllOff()
	bench_puppet_cmd(g_Puppet, "amx_statscfgmenu")
	if (!MenuHas("Stats Configuration 1/3")) return
	if (!MenuHas("1. Stats at the end of map Off")) return
	if (!MenuHas("7. Show Attackers Off")) return
	if (!MenuHas("8. Save configuration ^n")) return
	if (!MenuHas("9. More...")) return
	if (!MenuHas("0. Exit")) return
	ASSERT_EQ(MenuKeys(), MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_6|MENU_KEY_7|MENU_KEY_8|MENU_KEY_9|MENU_KEY_0)

	bench_puppet_cmd(g_Puppet, "menuselect 9")
	if (!MenuHas("Stats Configuration 2/3")) return
	if (!MenuHas("1. Show Victims Off")) return
	if (!MenuHas("0. Back")) return

	bench_puppet_cmd(g_Puppet, "menuselect 9")
	if (!MenuHas("Stats Configuration 3/3")) return
	if (!MenuHas("7. Frag Info Off")) return
	// The last page has no More.
	ASSERT_EQ(MenuKeys(), MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_6|MENU_KEY_7|MENU_KEY_8|MENU_KEY_0)

	bench_puppet_cmd(g_Puppet, "menuselect 10")
	if (!MenuHas("Stats Configuration 2/3")) return
	bench_puppet_cmd(g_Puppet, "menuselect 10")
	if (!MenuHas("Stats Configuration 1/3")) return

	// Exit closes it: no new menu.
	new count = bench_msg_count(g_Puppet, "ShowMenu")
	bench_puppet_cmd(g_Puppet, "menuselect 10")
	ASSERT_EQ(bench_msg_count(g_Puppet, "ShowMenu"), count)
	bench_pass()
}

public test_menu_toggles_and_saves()
{
	if (!StartAdmin("menusaver"))
		return
	AllOff()
	bench_puppet_cmd(g_Puppet, "amx_statscfgmenu")
	bench_puppet_cmd(g_Puppet, "menuselect 9")
	// Page 2, key 5: the 12th option, Say /ff.
	bench_puppet_cmd(g_Puppet, "menuselect 5")
	ASSERT_EQ(Option("SayFF"), 1)
	if (!MenuHas("Stats Configuration 2/3")) return
	if (!MenuHas("5. Say /ff On")) return
	// Not saved yet: the save line is marked.
	if (!MenuHas("8. Save configuration *")) return

	bench_puppet_cmd(g_Puppet, "menuselect 8")
	ASSERT_MSG(g_Puppet, "TextMsg", "* Stats configuration saved successfully")
	if (!MenuHas("8. Save configuration ^n")) return

	new line[128], len
	ASSERT(read_file(g_StatsFile, 2, line, charsmax(line), len))
	if (!SavedLine(line, "SayFF", "Say /ff")) return

	// And off again.
	bench_puppet_cmd(g_Puppet, "menuselect 5")
	ASSERT_EQ(Option("SayFF"), 0)
	bench_pass()
}
