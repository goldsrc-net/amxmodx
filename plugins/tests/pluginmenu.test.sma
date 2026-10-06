// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for pluginmenu.sma (Plugin Menu): amx_plugincvarmenu and amx_plugincmdmenu, answered by
// puppets with menuselect, and the amx_changecvar and amx_executecmd commands the menus prompt
// for. This plugin registers the cvars and commands the menus list, so the tests know what to
// expect; a stock plugin is paused for a moment to show how the list marks one.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

new g_P[3]
new g_PuppetCount

public plugin_init()
{
	register_plugin("Plugin Menu Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	register_cvar("pmtest_cvar", "1")
	register_cvar("pmtest_protected", "secret", FCVAR_PROTECTED)

	register_clcmd("pmtest_all", "CmdIgnored", ADMIN_ALL, "- a command anyone can run")
	register_clcmd("pmtest_user", "CmdIgnored", ADMIN_USER)
	register_clcmd("pmtest_admin", "CmdIgnored", ADMIN_ADMIN, "- any admin")
	register_clcmd("pmtest_kick", "CmdIgnored", ADMIN_KICK, "- kick access")
	register_clcmd("pmtest_rcon", "CmdIgnored", ADMIN_RCON, "- rcon access")
	register_clcmd("saypmtest", "CmdIgnored", ADMIN_ALL, "- starts with say")

	bench_coverage_ignore("pluginmenu.sma", 81, 81, "get_concmd always names the command register_clcmd returned the id of")
	bench_coverage_ignore("pluginmenu.sma", 88, 88, "get_concmd always names the command register_clcmd returned the id of")
	bench_coverage_ignore("pluginmenu.sma", 286, 286, "get_plugins_cvar lists only cvars AMX Mod X created, and sv_password is the engine's")
	bench_coverage_ignore("pluginmenu.sma", 479, 480, "AMX Mod X 1.10 sends Back and More to a menu's page callback, never to its handler")
	bench_coverage_ignore("pluginmenu.sma", 484, 485, "AMX Mod X 1.10 sends Back and More to a menu's page callback, never to its handler")
	bench_coverage_ignore("pluginmenu.sma", 499, 500, "pcvar handles start at 1, and only enabled items, which carry one, can be chosen")
	bench_coverage_ignore("pluginmenu.sma", 647, 648, "the item's info is a command name get_concmd returned, never empty")
	bench_coverage_ignore("pluginmenu.sma", 664, 665, "the item's info is a command name get_concmd returned, never empty")
	bench_coverage_ignore("pluginmenu.sma", 687, 689, "the menu has two items, so the item is 0, 1 or negative")
	bench_coverage_ignore("pluginmenu.sma", 804, 805, "AMX Mod X 1.10 sends Back and More to a menu's page callback, never to its handler")
	bench_coverage_ignore("pluginmenu.sma", 809, 810, "AMX Mod X 1.10 sends Back and More to a menu's page callback, never to its handler")
}

public CmdIgnored(id)
{
	return PLUGIN_HANDLED
}

public bench_setup()
{
	g_PuppetCount = 0
}

public bench_teardown()
{
	set_cvar_string("pmtest_cvar", "1")
	set_cvar_string("pmtest_protected", "secret")
	unpause("ac", "antiflood.amxx")
	unpause("ac", "admin.amxx")
}

// ---------------------------------------------------------------------------------------------
// Helpers

AddPuppet(const name[])
{
	new id = bench_puppet(name)
	if (id > 0)
		g_P[g_PuppetCount++] = id
	return id
}

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
		else if (!is_user_alive(id))
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

bool:MenuHas(id, const text[], bool:has = true)
{
	new menu[1024]
	MenuText(id, menu, charsmax(menu))
	if ((contain(menu, text) != -1) == has)
		return true
	bench_fail("menu sent to %d %s ^"%s^"; it is ^"%s^"", id, has ? "lacks" : "has", text, menu)
	return false
}

#define ASSERT_MENU(%0,%1)		if (!MenuHas(%0, %1)) return
#define ASSERT_NO_MENU(%0,%1)	if (!MenuHas(%0, %1, false)) return

// The index of the first item of id's open menu whose text starts with prefix, or -1.
FindItem(id, const prefix[], info[] = "", infolen = 0)
{
	new name[64], menu = bench_menu_open(id)
	if (menu < 0)
		return -1
	for (new i = 0; i < menu_items(menu); i++)
	{
		bench_menu_item(id, i, name, charsmax(name), info, infolen)
		if (equal(name, prefix, strlen(prefix)))
			return i
	}
	return -1
}

// The access an item of id's open menu asks for.
ItemAccess(id, item)
{
	new access, info[2], name[2], callback
	menu_item_getinfo(bench_menu_open(id), item, access, info, 0, name, 0, callback)
	return access
}

// Opens the plugin list with cmd, as an admin with flags, and returns the index of the item
// starting with prefix. The list asks for stray access (see test_plugin_list_access_bug), so the
// admin is given its lowest bit as well, and the list opened again, to be able to choose it.
OpenPluginList(id, const cmd[], flags, const prefix[])
{
	SetAccess(id, flags)
	bench_puppet_cmd(id, cmd)
	new item = FindItem(id, prefix)
	if (item < 0)
		return -1
	new access = ItemAccess(id, item)
	SetAccess(id, flags | (access & -access))
	bench_puppet_cmd(id, cmd)
	return item
}

// Chooses item (0-based) of id's open menu the way a player does: More until its page, then its
// key. Seven items to a page; a menu that fits on one page has no More.
SelectItem(id, item)
{
	new menu = bench_menu_open(id)
	if (menu >= 0 && menu_items(menu) > 7)
	{
		for (new page = 0; page < item / 7; page++)
			bench_puppet_cmd(id, "menuselect 9")
	}
	bench_puppet_cmd(id, "menuselect %d", item % 7 + 1)
}

// ---------------------------------------------------------------------------------------------
// Access and plugin lookup

public test_menus_need_access()
{
	ASSERT(AddPuppet("nopluginaccess") > 0)
	WaitForPuppets("NoAccess_Ready")
}

public NoAccess_Ready()
{
	new id = g_P[0]
	bench_puppet_cmd(id, "amx_plugincvarmenu")
	bench_puppet_cmd(id, "amx_plugincmdmenu")
	ASSERT_EQ(bench_msg_count(id, "", "You have no access to that command"), 2)
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

// GetPlidForValidPlugins finds a plugin by file or by title: Anti Flood's cvars for antiflood.amxx,
// Admin Base's commands for its title (once any argument picked plugin 0, Admin Base).
public test_named_plugin()
{
	ASSERT(AddPuppet("namedplugin") > 0)
	WaitForPuppets("Named_Ready")
}

public Named_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_CVAR|ADMIN_MENU)
	bench_puppet_cmd(id, "amx_plugincvarmenu antiflood.amxx")
	ASSERT(bench_menu_open(id) >= 0)
	ASSERT_MENU(id, "Anti Flood Cvars:")
	ASSERT(FindItem(id, "amx_flood_time") >= 0)
	ASSERT_NO_MENU(id, "Admin Base")
	// The cvar menu of a named plugin closes on Exit instead of going back to a plugin list.
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_menu_open(id), -1)

	// Admin Base's protected cvars are shown without their value to an admin without rcon.
	bench_puppet_cmd(id, "amx_plugincvarmenu admin.amxx")
	ASSERT_MENU(id, "Admin Base Cvars:")
	ASSERT_MENU(id, "amx_vote_time - ")
	ASSERT(FindItem(id, "amx_mode") >= 0)
	ASSERT(FindItem(id, "amx_mode - ") == -1)
	bench_puppet_cmd(id, "menuselect 10")

	bench_puppet_cmd(id, "amx_plugincmdmenu ^"Admin Base^"")
	ASSERT_MENU(id, "Admin Base Commands:")
	ASSERT(FindItem(id, "amx_reloadadmins") >= 0)
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

public test_named_plugin_not_running()
{
	ASSERT(AddPuppet("pausedplugin") > 0)
	WaitForPuppets("NotRunning_Ready")
}

public NotRunning_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_CVAR|ADMIN_MENU)
	ASSERT(pause("ac", "antiflood.amxx"))
	bench_puppet_cmd(id, "amx_plugincvarmenu antiflood.amxx")
	bench_puppet_cmd(id, "amx_plugincmdmenu antiflood.amxx")
	unpause("ac", "antiflood.amxx")
	ASSERT_EQ(bench_msg_count(id, "", "Plugin ^"antiflood.amxx^" is not running."), 2)
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

public test_named_plugin_not_found()
{
	ASSERT(AddPuppet("noplugin") > 0)
	WaitForPuppets("NotFound_Ready")
}

public NotFound_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_CVAR|ADMIN_MENU)
	bench_puppet_cmd(id, "amx_plugincvarmenu nosuchplugin.amxx")
	bench_puppet_cmd(id, "amx_plugincmdmenu nosuchplugin.amxx")
	ASSERT_EQ(bench_msg_count(id, "", "Couldn't find a plugin matching ^"nosuchplugin.amxx^""), 2)
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

// Every running plugin in the list can be opened by an admin with ADMIN_CVAR: the items carry no
// access flags of their own (once the enabled callback was passed as the access argument).
public test_plugin_list_access()
{
	ASSERT(AddPuppet("listaccess") > 0)
	WaitForPuppets("ListAccess_Ready")
}

public ListAccess_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_CVAR)
	bench_puppet_cmd(id, "amx_plugincvarmenu")
	ASSERT(bench_menu_open(id) >= 0)
	new item = FindItem(id, "Plugin Menu Tests - 2")
	ASSERT(item >= 0)
	ASSERT_EQ(ItemAccess(id, item), 0)
	SelectItem(id, item)
	ASSERT_MENU(id, "Plugin Menu Tests Cvars:")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The cvar menu

public test_cvar_menu_changes_a_cvar()
{
	ASSERT(AddPuppet("cvarchanger") > 0)
	ASSERT(AddPuppet("cvarwatcher") > 0)
	WaitForPuppets("Cvar_Ready")
}

public Cvar_Ready()
{
	new id = g_P[0], watcher = g_P[1], info[32]
	// A paused plugin is listed, but cannot be chosen.
	ASSERT(pause("ac", "antiflood.amxx"))
	new item = OpenPluginList(id, "amx_plugincvarmenu", ADMIN_CVAR, "Plugin Menu Tests - 2")
	ASSERT_MENU(id, "Plugin Cvar Menu:")
	ASSERT(FindItem(id, "Anti Flood - 1", info, charsmax(info)) >= 0)
	ASSERT_STR_EQ(info, "")
	ASSERT_EQ(FindItem(id, "Plugin Menu Tests - 2", info, charsmax(info)), item)
	ASSERT(item >= 0)
	ASSERT(contain(info, " DisplayCvarMenu") != -1)

	SelectItem(id, item)
	ASSERT_MENU(id, "Plugin Menu Tests Cvars:")
	ASSERT_EQ(FindItem(id, "pmtest_cvar - 1"), 0)
	// A protected cvar, to an admin without rcon access: no value, and it cannot be chosen.
	ASSERT_EQ(FindItem(id, "pmtest_protected", info, charsmax(info)), 1)
	ASSERT_NO_MENU(id, "secret")
	ASSERT_STR_EQ(info, "")

	bench_puppet_cmd(id, "menuselect 1")
	ASSERT_MSG(id, "", "[AMXX] Type in the new value for pmtest_cvar, or !cancel to cancel.")
	ASSERT_EQ(bench_menu_open(id), -1)

	bench_puppet_cmd(id, "amx_changecvar ^"7^"")
	ASSERT_EQ(get_cvar_num("pmtest_cvar"), 7)
	ASSERT_MSG(id, "", "[AMXX] Cvar ^"pmtest_cvar^" changed to ^"7^"")
	ASSERT_MSG(watcher, "", "set cvar pmtest_cvar to ^"7^"")
	// The cvar menu comes back with the new value.
	ASSERT_MENU(id, "Plugin Menu Tests Cvars:")
	ASSERT_EQ(FindItem(id, "pmtest_cvar - 7"), 0)

	bench_puppet_cmd(id, "amx_changecvar !cancel")
	ASSERT_MSG(id, "", "[AMXX] Cvar not changed.")
	ASSERT_EQ(get_cvar_num("pmtest_cvar"), 7)

	// Exit goes back to the plugin list, and Exit there closes it.
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MENU(id, "Plugin Cvar Menu:")
	ASSERT(bench_menu_open(id) >= 0)
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

public test_cvar_menu_rcon_changes_protected_cvar()
{
	ASSERT(AddPuppet("rconchanger") > 0)
	ASSERT(AddPuppet("rconwatcher") > 0)
	WaitForPuppets("Rcon_Ready")
}

public Rcon_Ready()
{
	new id = g_P[0], watcher = g_P[1]
	SelectItem(id, OpenPluginList(id, "amx_plugincvarmenu", ADMIN_CVAR|ADMIN_RCON, "Plugin Menu Tests - 2"))
	ASSERT_EQ(FindItem(id, "pmtest_protected - secret"), 1)
	bench_puppet_cmd(id, "menuselect 2")
	ASSERT_MSG(id, "", "Type in the new value for pmtest_protected")
	bench_puppet_cmd(id, "amx_changecvar hidden")
	new value[32]
	get_cvar_string("pmtest_protected", value, charsmax(value))
	ASSERT_STR_EQ(value, "hidden")
	// Other players are not shown the value of a protected cvar.
	ASSERT_MSG(watcher, "", "set cvar pmtest_protected to ^"*** PROTECTED ***^"")
	ASSERT_EQ(bench_msg_count(watcher, "", "hidden"), 0)
	bench_pass()
}

public test_change_cvar_without_a_choice()
{
	ASSERT(AddPuppet("nochoice") > 0)
	WaitForPuppets("NoChoice_Ready")
}

public NoChoice_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_CVAR|ADMIN_MENU)
	bench_puppet_cmd(id, "amx_changecvar 5")
	bench_puppet_cmd(id, "amx_executecmd ^"a b^"")
	ASSERT_EQ(get_cvar_num("pmtest_cvar"), 1)
	ASSERT_EQ(bench_msg_count(id, "", "[AMXX]"), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The command menu

public test_command_menu_runs_commands()
{
	ASSERT(AddPuppet("cmdrunner") > 0)
	WaitForPuppets("Cmd_Ready")
}

public Cmd_Ready()
{
	new id = g_P[0], info[32]
	new item = OpenPluginList(id, "amx_plugincmdmenu", ADMIN_MENU|ADMIN_KICK, "Plugin Menu Tests - 6")
	ASSERT_MENU(id, "Plugin Command Menu:")
	ASSERT(item >= 0)
	SelectItem(id, item)

	ASSERT_MENU(id, "Plugin Menu Tests Commands:")
	// Commands starting with "say" are left out; an admin may run ADMIN_ADMIN commands; a
	// command needing access the admin lacks is listed but cannot be chosen.
	ASSERT_EQ(menu_items(bench_menu_open(id)), 5)
	ASSERT_EQ(FindItem(id, "saypmtest"), -1)
	new all = FindItem(id, "pmtest_all", info, charsmax(info))
	ASSERT(all >= 0 && info[0] != 0)
	new user = FindItem(id, "pmtest_user", info, charsmax(info))
	ASSERT(user >= 0 && info[0] != 0)
	new admin = FindItem(id, "pmtest_admin", info, charsmax(info))
	ASSERT(admin >= 0 && info[0] != 0)
	ASSERT(FindItem(id, "pmtest_kick", info, charsmax(info)) >= 0)
	ASSERT(info[0] != 0)
	ASSERT(FindItem(id, "pmtest_rcon", info, charsmax(info)) >= 0)
	ASSERT_STR_EQ(info, "")

	// With parameters.
	bench_puppet_cmd(id, "menuselect %d", all + 1)
	ASSERT_MENU(id, "pmtest_all^n- a command anyone can run")
	ASSERT_MENU(id, "Execute with parameters.")
	bench_puppet_cmd(id, "menuselect 1")
	ASSERT_MSG(id, "", "[AMXX] Type in the parameters for pmtest_all, or !cancel to cancel.")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_puppet_cmd(id, "amx_executecmd ^"a b^"")
	ASSERT_MSG(id, "", "[AMXX] Command ^"pmtest_all^" executed with ^"a b^"")
	ASSERT_MENU(id, "Plugin Menu Tests Commands:")

	// Without parameters; a command without a description has only its name as the title.
	bench_puppet_cmd(id, "menuselect %d", user + 1)
	ASSERT_MENU(id, "pmtest_user^n^n")
	bench_puppet_cmd(id, "menuselect 2")
	ASSERT_MSG(id, "", "[AMXX] Command ^"pmtest_user^" executed with no parameters")
	ASSERT_MENU(id, "Plugin Menu Tests Commands:")

	bench_puppet_cmd(id, "amx_executecmd !cancel")
	ASSERT_MSG(id, "", "[AMXX] Command not executed.")
	ASSERT_MENU(id, "Plugin Menu Tests Commands:")

	// Exit from a command goes back to the command list, from there to the plugin list.
	bench_puppet_cmd(id, "menuselect %d", admin + 1)
	ASSERT_MENU(id, "pmtest_admin^n- any admin")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MENU(id, "Plugin Menu Tests Commands:")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MENU(id, "Plugin Command Menu:")
	ASSERT(bench_menu_open(id) >= 0)
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

public test_command_menu_for_a_non_admin()
{
	ASSERT(AddPuppet("cmdnonadmin") > 0)
	WaitForPuppets("NonAdmin_Ready")
}

public NonAdmin_Ready()
{
	new id = g_P[0], info[32]
	// ADMIN_USER makes a player no admin, so ADMIN_ADMIN commands are closed to them.
	SelectItem(id, OpenPluginList(id, "amx_plugincmdmenu", ADMIN_MENU|ADMIN_USER, "Plugin Menu Tests - 6"))
	ASSERT_MENU(id, "Plugin Menu Tests Commands:")
	ASSERT(FindItem(id, "pmtest_user", info, charsmax(info)) >= 0)
	ASSERT(info[0] != 0)
	ASSERT(FindItem(id, "pmtest_admin", info, charsmax(info)) >= 0)
	ASSERT_STR_EQ(info, "")
	bench_pass()
}
