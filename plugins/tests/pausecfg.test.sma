// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for pausecfg.sma (Pause Plugins): amx_pausecfg and its subcommands, amx_off, amx_on and
// the pause menu (amx_pausecfgmenu), answered by a puppet with menuselect. The plugins paused
// and stopped are the helpers next to this file: Pause Target (pausecfg_pause.test.sma), Stop
// Target (pausecfg_stop.test.sma, stopped for good by the first test that stops it) and Failed
// Target (pausecfg_fail.test.sma, failed on load). configs/pausecfg.ini is put back after every
// test.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#define PAUSE_TARGET	"tests/pausecfg_pause.test.amxx"
#define STOP_TARGET		"tests/pausecfg_stop.test.amxx"
#define FAIL_TARGET		"tests/pausecfg_fail.test.amxx"
#define NO_FILE_MARKER	"; amxxbench: there was no pausecfg.ini"

// The titles pausecfg.sma's plugin_cfg marks as unpauseable.
new const g_SystemTitles[][] =
{
	"Admin Base", "Admin Base (SQL)", "Pause Plugins", "TimeLeft", "NextMap", "Slots Reservation"
}

new g_File[PLATFORM_MAX_PATH]
new g_SavedFile[PLATFORM_MAX_PATH]
new g_Puppet

public plugin_init()
{
	register_plugin("Pause Plugins Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("pausecfg.sma", 214, 214, "Next is only offered while a further page exists, and plugins are never unloaded")
	bench_coverage_ignore("pausecfg.sma", 229, 231, "colored_menus() is false on The Specialists")
	bench_coverage_ignore("pausecfg.sma", 109, 109, "write_file raises a native error when it cannot write (as file.inc documents) instead of returning 0, so saveSettings never fails")
	bench_coverage_ignore("pausecfg.sma", 356, 356, "the unpauseable list cannot be emptied, so filling it (32 marks) would change every later test")
	bench_coverage_ignore("pausecfg.sma", 376, 376, "write_file raises a native error when it cannot write (as file.inc documents) instead of returning 0, so saveSettings never fails")
	bench_coverage_ignore("pausecfg.sma", 497, 497, "write_file raises a native error when it cannot write (as file.inc documents) instead of returning 0, so saveSettings never fails")
}

public bench_setup()
{
	get_configsdir(g_File, charsmax(g_File))
	formatex(g_SavedFile, charsmax(g_SavedFile), "%s/pausecfg.ini.bench", g_File)
	add(g_File, charsmax(g_File), "/pausecfg.ini")
	// A saved copy already there is the server's own (or the marker for none), left by a run
	// that stopped before teardown: keep it, and drop the pausecfg.ini that run wrote.
	if (file_exists(g_SavedFile))
		delete_file(g_File)
	else if (file_exists(g_File))
		rename_file(g_File, g_SavedFile, 1)
	else
		write_file(g_SavedFile, NO_FILE_MARKER)
	g_Puppet = 0
}

public bench_teardown()
{
	unpause("ac", PAUSE_TARGET)
	// Saving clears the plugin's "modified" mark; the file it writes is replaced below.
	server_cmd("amx_pausecfg save")
	server_exec()

	delete_file(g_File)
	new line[64], len
	read_file(g_SavedFile, 0, line, charsmax(line), len)
	if (equal(line, NO_FILE_MARKER))
		delete_file(g_SavedFile)
	else
		rename_file(g_SavedFile, g_File, 1)
}

// ---------------------------------------------------------------------------------------------
// Helpers

StartWithAdmin(const name[], const step[])
{
	g_Puppet = bench_puppet(name)
	if (!bench_check(g_Puppet > 0, "puppet created"))
		return
	bench_puppet_spawn(g_Puppet, step, 30.0, "respawn")
}

SetAccess(id, flags)
{
	remove_user_flags(id, -1)
	set_user_flags(id, flags)
}

// The status get_plugin reports for a plugin file ("debug", "paused", ...).
Status(const file[])
{
	new status[16]
	get_plugin(find_plugin_byfile(file), "", 0, "", 0, "", 0, "", 0, status, charsmax(status))
	return status
}

bool:IsSystemTitle(const title[])
{
	for (new i = 0; i < sizeof(g_SystemTitles); i++)
		if (equali(title, g_SystemTitles[i]))
			return true
	return false
}

// How many plugins amx_off would pause (first = 'r') or amx_on unpause (first = 'p').
CountUnmarked(first)
{
	new title[32], status[16], count = 0
	for (new i = 0; i < get_pluginsnum(); i++)
	{
		get_plugin(i, "", 0, title, charsmax(title), "", 0, "", 0, status, charsmax(status))
		if (status[0] == first && !IsSystemTitle(title))
			count++
	}
	return count
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

MenuKeys(id)
{
	new BenchMsg:msg = bench_msg_last(id, "ShowMenu")
	return msg == BenchMsg:0 ? -1 : bench_msg_int(msg, 0)
}

Pages()
{
	new n = get_pluginsnum()
	return n / 6 + ((n % 6) ? 1 : 0)
}

// Opens the pause menu on the page of plugin file; returns the row (1-6) it is on.
OpenMenuAt(id, const file[])
{
	new plugin = find_plugin_byfile(file)
	bench_puppet_cmd(id, "amx_pausecfgmenu")
	for (new page = 0; page < plugin / 6; page++)
		bench_puppet_cmd(id, "menuselect 9")
	return plugin % 6 + 1
}

// ---------------------------------------------------------------------------------------------
// Access, usage, list

public test_commands_need_access()
{
	StartWithAdmin("nopauseaccess", "NoAccess_Spawned")
}

public NoAccess_Spawned(id)
{
	bench_puppet_cmd(id, "amx_pausecfg list")
	bench_puppet_cmd(id, "amx_pausecfgmenu")
	bench_puppet_cmd(id, "amx_off")
	bench_puppet_cmd(id, "amx_on")
	ASSERT_EQ(bench_msg_count(id, "", "You have no access to that command"), 4)
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), 0)
	ASSERT_EQ(bench_msg_count(id, "", "Paused"), 0)
	ASSERT_EQ(bench_msg_count(id, "", "Unpaused"), 0)
	bench_pass()
}

public test_usage()
{
	StartWithAdmin("pauseusage", "Usage_Spawned")
}

public Usage_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	bench_puppet_cmd(id, "amx_pausecfg")
	ASSERT_MSG(id, "", "Usage:  amx_pausecfg <command> [name]")
	ASSERT_MSG(id, "", "Commands:")
	ASSERT_MSG(id, "", "off - pauses all plugins not in the list")
	ASSERT_MSG(id, "", "add <title> - marks a plugin as unpauseable")
	// "add" without a title falls through to the usage too.
	bench_puppet_cmd(id, "amx_pausecfg add")
	ASSERT_EQ(bench_msg_count(id, "", "Usage:  amx_pausecfg"), 2)
	bench_pass()
}

public test_list_pages()
{
	StartWithAdmin("pauselister", "List_Spawned")
}

public List_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	new n = get_pluginsnum(), text[96], status[16], running = 0
	ASSERT(n > 10)
	for (new i = 0; i < 10; i++)
	{
		get_plugin(i, "", 0, "", 0, "", 0, "", 0, status, charsmax(status))
		if (status[0] == 'r')
			running++
	}
	bench_puppet_cmd(id, "amx_pausecfg list")
	ASSERT_MSG(id, "", "----- Pause Plugins: Loaded plugins -----")
	ASSERT_MSG(id, "", "name")
	ASSERT_MSG(id, "", " [  1] Admin Base")
	formatex(text, charsmax(text), "----- Entries 1 - 10 of %d (%d running) -----", n, running)
	ASSERT_MSG(id, "", text)
	ASSERT_MSG(id, "", "----- Use 'amx_pausecfg list 11' for more -----")

	// Past the end: the last entry; 0: the first.
	bench_puppet_cmd(id, "amx_pausecfg list 1000")
	formatex(text, charsmax(text), "----- Entries %d - %d of %d", n, n, n)
	ASSERT_MSG(id, "", text)
	ASSERT_MSG(id, "", "----- Use 'amx_pausecfg list 1' for begin -----")
	bench_puppet_cmd(id, "amx_pausecfg list 0")
	formatex(text, charsmax(text), "----- Entries 1 - 10 of %d", n)
	ASSERT_EQ(bench_msg_count(id, "", text), 2)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_off, amx_on

// amx_off pauses every plugin not marked unpauseable that is running, in debug mode or not (every
// plugin is in debug mode in a coverage run), this test plugin among them; amx_on unpauses them. The
// counts are taken first and amx_on runs in the same step, so no assertion can return while this
// plugin is paused.
public test_off_and_on()
{
	StartWithAdmin("offandon", "OffOn_Spawned")
}

public OffOn_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	new text[64], off = CountUnmarked('r') + CountUnmarked('d')
	bench_puppet_cmd(id, "amx_off")
	new paused = CountUnmarked('p'), stillOn = CountUnmarked('r') + CountUnmarked('d')
	bench_puppet_cmd(id, "amx_on")

	formatex(text, charsmax(text), off == 1 ? "Paused %d plugin" : "Paused %d plugins", off)
	ASSERT_MSG(id, "", text)
	ASSERT_EQ(paused, off)
	ASSERT_EQ(stillOn, 0)
	formatex(text, charsmax(text), off == 1 ? "Unpaused %d plugin" : "Unpaused %d plugins", off)
	ASSERT_MSG(id, "", text)
	ASSERT_EQ(CountUnmarked('p'), 0)

	// The same through amx_pausecfg.
	bench_puppet_cmd(id, "amx_pausecfg off")
	bench_puppet_cmd(id, "amx_pausecfg on")
	ASSERT_EQ(CountUnmarked('p'), 0)
	ASSERT_EQ(bench_msg_count(id, "", "Unpaused"), 2)
	bench_pass()
}

public test_on_unpauses_a_paused_plugin()
{
	StartWithAdmin("onepause", "OnOne_Spawned")
}

public OnOne_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	ASSERT_EQ(CountUnmarked('p'), 0)
	ASSERT(pause("ac", PAUSE_TARGET))
	ASSERT_STR_EQ(Status(PAUSE_TARGET), "paused")
	bench_puppet_cmd(id, "amx_on")
	ASSERT_MSG(id, "", "Unpaused 1 plugin")
	ASSERT_STR_EQ(Status(PAUSE_TARGET), "debug")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// pause, enable, stop

public test_pause_and_enable_by_file()
{
	StartWithAdmin("filepauser", "File_Spawned")
}

public File_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	// A file name prefix is enough; the full name is reported.
	bench_puppet_cmd(id, "amx_pausecfg pause tests/pausecfg_pause")
	ASSERT_MSG(id, "", "Plugin matching ^"tests/pausecfg_pause.test.amxx^" paused")
	ASSERT_STR_EQ(Status(PAUSE_TARGET), "paused")
	bench_puppet_cmd(id, "amx_pausecfg enable tests/pausecfg_pause")
	ASSERT_MSG(id, "", "Plugin matching ^"tests/pausecfg_pause.test.amxx^" unpaused")
	ASSERT_STR_EQ(Status(PAUSE_TARGET), "debug")
	// Enabling a plugin that is not paused fails with the message for a stopped one.
	bench_puppet_cmd(id, "amx_pausecfg enable tests/pausecfg_pause")
	ASSERT_MSG(id, "", "Plugin ^"tests/pausecfg_pause.test.amxx^" is stopped and cannot be paused or unpaused.")

	// Unpauseable plugins, unknown files and no file at all are not found.
	bench_puppet_cmd(id, "amx_pausecfg pause pausecfg.amxx")
	ASSERT_MSG(id, "", "Couldn't find a plugin matching ^"pausecfg.amxx^"")
	ASSERT_FALSE(equal(Status("pausecfg.amxx"), "paused"))
	bench_puppet_cmd(id, "amx_pausecfg pause bench_nosuch")
	bench_puppet_cmd(id, "amx_pausecfg enable bench_nosuch")
	bench_puppet_cmd(id, "amx_pausecfg stop bench_nosuch")
	ASSERT_EQ(bench_msg_count(id, "", "Couldn't find a plugin matching ^"bench_nosuch^""), 3)
	bench_puppet_cmd(id, "amx_pausecfg pause")
	ASSERT_MSG(id, "", "Couldn't find a plugin matching ^"^"")
	bench_pass()
}

public test_stop_is_final()
{
	StartWithAdmin("stopper", "Stop_Spawned")
}

public Stop_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	bench_puppet_cmd(id, "amx_pausecfg stop tests/pausecfg_stop")
	ASSERT_MSG(id, "", "Plugin matching ^"tests/pausecfg_stop.test.amxx^" stopped")
	ASSERT_STR_EQ(Status(STOP_TARGET), "stopped")
	bench_puppet_cmd(id, "amx_pausecfg enable tests/pausecfg_stop")
	ASSERT_MSG(id, "", "Plugin ^"tests/pausecfg_stop.test.amxx^" is stopped and cannot be paused or unpaused.")
	ASSERT_STR_EQ(Status(STOP_TARGET), "stopped")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The configuration file

public test_save_and_clear()
{
	StartWithAdmin("pausesaver", "Save_Spawned")
}

public Save_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	ASSERT(pause("ac", PAUSE_TARGET))
	bench_puppet_cmd(id, "amx_pausecfg save")
	ASSERT_MSG(id, "", "Configuration saved successfully")
	ASSERT(file_exists(g_File))
	new line[128], len
	read_file(g_File, 0, line, charsmax(line), len)
	ASSERT_STR_EQ(line, ";Generated by Pause Plugins Plugin. Do not modify!")
	read_file(g_File, 2, line, charsmax(line), len)
	ASSERT_STR_EQ(line, "^"Pause Target^" ;tests/pausecfg_pause.test.amxx")
	// Only the paused plugin is listed.
	ASSERT_EQ(read_file(g_File, 3, line, charsmax(line), len), 0)

	bench_puppet_cmd(id, "amx_pausecfg clear")
	ASSERT_MSG(id, "", "Configuration file cleared. Reload the map if needed")
	ASSERT_FALSE(file_exists(g_File))
	bench_puppet_cmd(id, "amx_pausecfg clear")
	ASSERT_MSG(id, "", "Configuration was already cleared!")
	bench_pass()
}

// plugin_cfg pauses the plugins pausecfg.ini lists by title. It also marks the unpauseable
// plugins again, which only repeats entries already in its list.
public test_config_pauses_listed_plugins()
{
	write_file(g_File, ";Generated by Pause Plugins Plugin. Do not modify!")
	write_file(g_File, "^"Pause Target^" ;tests/pausecfg_pause.test.amxx")
	write_file(g_File, "^"No Such Plugin^" ;nosuch.amxx")
	write_file(g_File, "")
	ASSERT_STR_EQ(Status(PAUSE_TARGET), "debug")
	ASSERT(callfunc_begin("plugin_cfg", "pausecfg.amxx") == 1)
	callfunc_end()
	server_exec()
	ASSERT_STR_EQ(Status(PAUSE_TARGET), "paused")
	ASSERT_FALSE(equal(Status("pausecfg.amxx"), "paused"))
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The pause menu

public test_menu_pages()
{
	StartWithAdmin("menupager", "Pages_Spawned")
}

public Pages_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	new text[64]
	bench_puppet_cmd(id, "amx_pausecfgmenu")
	formatex(text, charsmax(text), "Pause/Unpause Plugins 1/%d", Pages())
	ASSERT_MENU(id, text)
	// Unpauseable plugins have no key.
	ASSERT_MENU(id, "#. Admin Base On")
	ASSERT_MENU(id, "2. Admin Commands On")
	ASSERT_MENU(id, "7. Clear file with paused")
	ASSERT_MENU(id, "8. Save paused ")
	ASSERT_MENU(id, "9. More...")
	ASSERT_MENU(id, "0. Exit")
	// Rows 2-6 (Slots Reservation, row 4, is unpauseable), Clear, Save, More, Exit.
	ASSERT_EQ(MenuKeys(id), MENU_KEY_2|MENU_KEY_3|MENU_KEY_5|MENU_KEY_6|MENU_KEY_7|MENU_KEY_8|MENU_KEY_9|MENU_KEY_0)

	for (new page = 1; page < Pages(); page++)
		bench_puppet_cmd(id, "menuselect 9")
	formatex(text, charsmax(text), "Pause/Unpause Plugins %d/%d", Pages(), Pages())
	ASSERT_MENU(id, text)
	ASSERT_NO_MENU(id, "More")
	ASSERT_MENU(id, "0. Back")

	for (new page = Pages(); page > 1; page--)
		bench_puppet_cmd(id, "menuselect 10")
	formatex(text, charsmax(text), "Pause/Unpause Plugins 1/%d", Pages())
	ASSERT_MENU(id, text)
	new menus = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), menus)
	bench_pass()
}

public test_menu_pauses_and_unpauses()
{
	StartWithAdmin("menupauser", "MenuPause_Spawned")
}

public MenuPause_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	new text[64]
	new row = OpenMenuAt(id, PAUSE_TARGET)
	formatex(text, charsmax(text), "%d. Pause Target On", row)
	ASSERT_MENU(id, text)
	ASSERT_MENU(id, "8. Save paused ^n")

	bench_puppet_cmd(id, "menuselect %d", row)
	ASSERT_STR_EQ(Status(PAUSE_TARGET), "paused")
	formatex(text, charsmax(text), "%d. Pause Target Off", row)
	ASSERT_MENU(id, text)

	// Unpausing marks the configuration as modified.
	bench_puppet_cmd(id, "menuselect %d", row)
	ASSERT_STR_EQ(Status(PAUSE_TARGET), "debug")
	formatex(text, charsmax(text), "%d. Pause Target On", row)
	ASSERT_MENU(id, text)
	ASSERT_MENU(id, "8. Save paused *")
	bench_pass()
}

public test_menu_stopped_and_failed_plugins()
{
	StartWithAdmin("menustopped", "MenuStopped_Spawned")
}

public MenuStopped_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	new text[96]
	// Stopping is final, and harmless to repeat.
	ASSERT(pause("dc", STOP_TARGET))
	new row = OpenMenuAt(id, STOP_TARGET)
	formatex(text, charsmax(text), "%d. Stop Target stopped", row)
	ASSERT_MENU(id, text)
	bench_puppet_cmd(id, "menuselect %d", row)
	ASSERT_MSG(id, "", "Plugin ^"tests/pausecfg_stop.test.amxx^" is stopped and cannot be paused or unpaused.")
	ASSERT_STR_EQ(Status(STOP_TARGET), "stopped")
	bench_puppet_cmd(id, "menuselect 10")

	// A plugin that failed is shown as LOCKED, without a key.
	ASSERT_STR_EQ(Status(FAIL_TARGET), "error")
	row = OpenMenuAt(id, FAIL_TARGET)
	ASSERT_MENU(id, "#. Failed Target LOCKED")
	ASSERT_FALSE(MenuKeys(id) & (1 << (row - 1)))
	bench_pass()
}

public test_menu_save_and_clear()
{
	StartWithAdmin("menusaver", "MenuSave_Spawned")
}

public MenuSave_Spawned(id)
{
	SetAccess(id, ADMIN_CFG)
	ASSERT(pause("ac", PAUSE_TARGET))
	bench_puppet_cmd(id, "amx_pausecfgmenu")
	bench_puppet_cmd(id, "menuselect 7")
	ASSERT_MSG(id, "", "* Configuration was already cleared!")
	ASSERT_MENU(id, "Pause/Unpause Plugins 1/")
	bench_puppet_cmd(id, "menuselect 8")
	ASSERT_MSG(id, "", "* Configuration saved successfully")
	ASSERT(file_exists(g_File))
	ASSERT_MENU(id, "8. Save paused ^n")
	bench_puppet_cmd(id, "menuselect 7")
	ASSERT_MSG(id, "", "* Configuration file cleared. Reload the map if needed")
	ASSERT_FALSE(file_exists(g_File))
	bench_pass()
}
