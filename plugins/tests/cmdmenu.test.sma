// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for cmdmenu.sma (Commands Menu): the commands, configs and speech menus and the cvars
// menu, as the server's own cmds.ini, configs.ini, speech.ini and cvars.ini define them (the
// plugin reads those once, in plugin_init and plugin_precache, before any test runs). A puppet
// opens each menu and answers it with menuselect. The cvars the menus change are put back after
// every test.
//
// The config files test installs its own cmds.ini, speech.ini and cvars.ini (fixtures/cmdmenu_*)
// and takes configs.ini away, changes the map for them, then takes speech.ini and cvars.ini away
// for a second map. It keeps the server's own files as ".bench" copies (or a ".bench-none" marker
// when there was none), which also tell a later run that an interrupted one left its files there;
// they are put back, and the map changed once more.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

new const g_Cvars[][] = { "mp_timelimit", "sv_password", "pausable", "sv_voiceenable", "mp_chattime", "mp_logmessages" }
new g_Saved[sizeof(g_Cvars)][32]
new bool:g_HaveSaved

new const g_Configs[][] = { "cmds.ini", "configs.ini", "speech.ini", "cvars.ini" }

new g_P[MAX_PLAYERS + 1]
new g_PNum

public plugin_init()
{
	register_plugin("Commands Menu Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("cmdmenu.sma", 254, 254, "colored menus, which AMX Mod X turns off for ts")
	bench_coverage_ignore("cmdmenu.sma", 449, 449, "colored menus, which AMX Mod X turns off for ts")

	// The cvars fixtures/cmdmenu_cvars.ini lists.
	new name[32]
	for (new i = 1; i <= 9; i++)
	{
		formatex(name, charsmax(name), "bench_cvarmenu%d", i)
		register_cvar(name, "a")
	}
}

public bench_setup()
{
	for (new i = 0; i < sizeof(g_Cvars); i++)
		get_cvar_string(g_Cvars[i], g_Saved[i], charsmax(g_Saved[]))
	g_HaveSaved = true
	// Left by a run that stopped before teardown: the files there now are that run's.
	RestoreConfigs()
}

public bench_teardown()
{
	// After a map change this file starts over, with nothing saved; that test changes no cvars.
	if (g_HaveSaved)
	{
		for (new i = 0; i < sizeof(g_Cvars); i++)
			set_cvar_string(g_Cvars[i], g_Saved[i])
	}
	RestoreConfigs()
}

// ---------------------------------------------------------------------------------------------
// Helpers

SpawnPuppets(const prefix[], count, const step[])
{
	g_PNum = 0
	new name[32]
	for (new i = 1; i <= count; i++)
	{
		formatex(name, charsmax(name), "%s%d", prefix, i)
		new id = bench_puppet(name)
		if (!bench_check(id > 0, "puppet created"))
			return
		g_P[g_PNum++] = id
	}
	bench_wait_until("AllAlive", step, 30.0)
}

public AllAlive()
{
	new bool:ok = true
	for (new i = 0; i < g_PNum; i++)
	{
		if (is_user_connected(g_P[i]) && !is_user_alive(g_P[i]))
		{
			engclient_cmd(g_P[i], "respawn")
			ok = false
		}
	}
	return ok
}

SetFlags(id, const flags[])
{
	remove_user_flags(id)
	set_user_flags(id, read_flags(flags))
}

MenuText(id, out[], len)
{
	new BenchMsg:msg = BenchMsg:0, part[256], bool:fresh = true
	out[0] = 0
	while ((msg = bench_msg_next(id, msg, "ShowMenu")) != BenchMsg:0)
	{
		if (fresh)
			out[0] = 0
		bench_msg_text(msg, part, charsmax(part))
		add(out, len, part)
		fresh = bench_msg_int(msg, 2) == 0
	}
}

MenuKeys(id)
{
	new BenchMsg:msg = bench_msg_last(id, "ShowMenu")
	return msg == BenchMsg:0 ? -1 : bench_msg_int(msg, 0)
}

#define ASSERT_MENU(%0,%1)      if (!MenuHas(%0, %1, true)) return
#define ASSERT_NOT_MENU(%0,%1)  if (!MenuHas(%0, %1, false)) return

bool:MenuHas(id, const text[], bool:wanted)
{
	new body[512]
	MenuText(id, body, charsmax(body))
	if ((contain(body, text) != -1) == wanted)
		return true
	replace_all(body, charsmax(body), "^n", "|")
	bench_fail("menu %s ^"%s^": ^"%s^"", wanted ? "lacks" : "has", text, body)
	return false
}

bool:MenuClosed(id)
{
	new oldmenu, newmenu, page
	player_menu_info(id, oldmenu, newmenu, page)
	return oldmenu <= 0
}

ConfigPath(const file[], suffix[], path[], len)
{
	get_configsdir(path, len)
	return format(path, len, "%s/%s%s", path, file, suffix)
}

// Puts fixture (empty: no file at all) in place of configs/file, keeping the server's own as
// file.bench, or a file.bench-none marker when it has none. A second call keeps the first's copy.
SwapConfig(const file[], const fixture[])
{
	new path[PLATFORM_MAX_PATH], saved[PLATFORM_MAX_PATH], none[PLATFORM_MAX_PATH]
	ConfigPath(file, "", path, charsmax(path))
	ConfigPath(file, ".bench", saved, charsmax(saved))
	ConfigPath(file, ".bench-none", none, charsmax(none))
	if (!file_exists(saved) && !file_exists(none))
	{
		if (file_exists(path))
			rename_file(path, saved, 1)
		else
			fclose(fopen(none, "wt"))
	}
	delete_file(path)
	if (fixture[0])
	{
		new from[PLATFORM_MAX_PATH], line[256]
		bench_fixture(fixture, from, charsmax(from))
		new in = fopen(from, "rt"), out = fopen(path, "wt")
		while (fgets(in, line, charsmax(line)))
			fputs(out, line)
		fclose(in)
		fclose(out)
	}
}

// Puts the server's own files back after SwapConfig.
RestoreConfigs()
{
	new path[PLATFORM_MAX_PATH], saved[PLATFORM_MAX_PATH], none[PLATFORM_MAX_PATH]
	for (new i = 0; i < sizeof(g_Configs); i++)
	{
		ConfigPath(g_Configs[i], "", path, charsmax(path))
		ConfigPath(g_Configs[i], ".bench", saved, charsmax(saved))
		ConfigPath(g_Configs[i], ".bench-none", none, charsmax(none))
		if (file_exists(saved))
		{
			delete_file(path)
			rename_file(saved, path, 1)
		}
		else if (file_exists(none))
		{
			delete_file(path)
			delete_file(none)
		}
	}
}

// ---------------------------------------------------------------------------------------------
// Tests

public test_no_access()
{
	SpawnPuppets("cnoacc", 1, "NoAccess_Spawned")
}

public NoAccess_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "z")
	bench_puppet_cmd(id, "amx_cmdmenu")
	ASSERT_EQ(bench_msg_count(id, "", "You have no access to that command"), 1)
	bench_puppet_cmd(id, "amx_cvarmenu")
	ASSERT_EQ(bench_msg_count(id, "", "You have no access to that command"), 2)
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), 0)
	bench_pass()
}

// cmds.ini has one entry, "Pause" (amx_pause, flags "ad"): run from the server console, then
// back to the menu.
public test_commands_menu_runs_server_command()
{
	SpawnPuppets("ccmd", 1, "Commands_Spawned")
}

public Commands_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "u")
	set_cvar_num("pausable", 0)
	bench_puppet_cmd(id, "amx_cmdmenu")
	ASSERT_MENU(id, "Commands Menu 1/1^n^n1. Pause^n^n0. Exit")
	ASSERT_EQ(MenuKeys(id), MENU_KEY_1|MENU_KEY_0)

	new before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 1")
	// "d": the menu comes back.
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before + 1)
	ASSERT_MENU(id, "Commands Menu 1/1")
	// "a": amx_pause runs from the server console (admincmd turns pausable on for it and has the
	// player's client pause the game).
	server_exec()
	ASSERT_EQ(get_cvar_num("pausable"), 1)
	ASSERT_MSG(id, "", "pause server")
	ASSERT_MSG(id, "stufftext", "pause;pauseAck")
	bench_pass()
}

// configs.ini has every entry commented out.
public test_configs_menu_empty()
{
	SpawnPuppets("ccfg", 1, "Configs_Spawned")
}

public Configs_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "u")
	bench_puppet_cmd(id, "amx_cfgmenu")
	ASSERT_MENU(id, "Configs Menu 1/1^n^n^n0. Exit")
	ASSERT_EQ(MenuKeys(id), MENU_KEY_0)
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT(MenuClosed(id))
	bench_pass()
}

// speech.ini has 21 entries ("cd": to every client, back to the menu): pages of 8, 8 and 5.
public test_speech_menu_pages()
{
	SpawnPuppets("cspk", 1, "Speech_Spawned")
}

public Speech_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "u")
	bench_puppet_cmd(id, "amx_speechmenu")
	ASSERT_MENU(id, "1. Hello!^n2. Don't think so^n")
	ASSERT_MENU(id, "8. Seeya^n^n9. More...^n0. Exit")
	ASSERT_EQ(MenuKeys(id), 0x3FF)

	bench_puppet_cmd(id, "menuselect 9")
	ASSERT_MENU(id, "1. Man that sounded bad^n")
	ASSERT_MENU(id, "8. You thinkin?^n^n9. More...^n0. Back")

	bench_puppet_cmd(id, "menuselect 9")
	ASSERT_MENU(id, "1. Open fire Gordon!^n")
	ASSERT_MENU(id, "5. No sir^n^n0. Back")
	ASSERT_EQ(MenuKeys(id), 0x21F)

	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MENU(id, "1. Man that sounded bad^n")

	// Picking an entry sends it to every client and shows the same page again.
	new before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 2")
	ASSERT_MSG(id, "stufftext", "spk ^"vox/hello and die^"")
	ASSERT(bench_msg_count(id, "ShowMenu") > before)
	ASSERT_MENU(id, "1. Man that sounded bad^n")

	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MENU(id, "1. Hello!^n")
	before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before)
	ASSERT(MenuClosed(id))
	bench_pass()
}

// 21 entries make three pages: the title reads 1/3 (once 1/7, the remainder 21 % 8 = 5 added
// instead of one page for it).
public test_speech_menu_page_count()
{
	SpawnPuppets("cspc", 1, "SpeechCount_Spawned")
}

public SpeechCount_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "u")
	bench_puppet_cmd(id, "amx_speechmenu")
	ASSERT_MENU(id, "Speech Menu 1/3^n")
	bench_pass()
}

// cvars.ini lists six cvars; picking one sets the next of its values, wrapping around, and a
// value that is not in the list goes back to the first.
public test_cvars_menu_cycles_values()
{
	SpawnPuppets("ccvar", 1, "Cvars_Spawned")
}

public Cvars_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "gu")
	set_cvar_num("pausable", 0)
	set_cvar_num("mp_chattime", 7)
	bench_puppet_cmd(id, "amx_cvarmenu")
	ASSERT_MENU(id, "Cvars Menu 1/1^n^n1. mp_timelimit")
	ASSERT_MENU(id, "3. pausable    0^n")
	ASSERT_MENU(id, "5. mp_chattime    7^n")
	ASSERT_MENU(id, "6. mp_logmessages")
	ASSERT_EQ(MenuKeys(id), 0x23F)

	bench_puppet_cmd(id, "menuselect 3")
	ASSERT_EQ(get_cvar_num("pausable"), 1)
	ASSERT_MENU(id, "3. pausable    1^n")
	bench_puppet_cmd(id, "menuselect 3")
	ASSERT_EQ(get_cvar_num("pausable"), 0)

	bench_puppet_cmd(id, "menuselect 5")
	ASSERT_EQ(get_cvar_num("mp_chattime"), 0)
	ASSERT_MENU(id, "5. mp_chattime    0^n")
	bench_puppet_cmd(id, "menuselect 5")
	ASSERT_EQ(get_cvar_num("mp_chattime"), 1)

	new before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before)
	ASSERT(MenuClosed(id))
	bench_pass()
}

// Every cvars.ini entry needs "u": an admin with only "g" gets an empty menu.
public test_cvars_menu_without_entry_access()
{
	SpawnPuppets("cempty", 1, "CvarsEmpty_Spawned")
}

public CvarsEmpty_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "g")
	bench_puppet_cmd(id, "amx_cvarmenu")
	ASSERT_MENU(id, "Cvars Menu 1/0^n^n^n0. Exit")
	ASSERT_EQ(MenuKeys(id), MENU_KEY_0)
	bench_pass()
}

// The config files on a new map. cmds.ini: a separator ("-", not a key), "bd" on the admin's
// console and back to the menu, "c" on every client's, "a" from the server console, and an entry
// needing "l" left out. No configs.ini: an empty menu. speech.ini: vox, mp3, a leading slash and
// custom wavs, which plugin_precache precaches when the file exists. cvars.ini: nine cvars, so a
// second page. Then a map without speech.ini and cvars.ini, and back to the server's own files.
public test_config_files()
{
	bench_set_timeout(180.0)
	SwapConfig("cmds.ini", "cmdmenu_cmds.ini")
	SwapConfig("configs.ini", "")
	SwapConfig("speech.ini", "cmdmenu_speech.ini")
	SwapConfig("cvars.ini", "cmdmenu_cvars.ini")
	bench_change_map("", "Configs_Map")
}

public Configs_Map()
{
	SpawnPuppets("cini", 2, "ConfigsCmds_Spawned")
}

public ConfigsCmds_Spawned()
{
	new id = g_P[0], other = g_P[1]
	SetFlags(id, "u")
	bench_puppet_cmd(id, "amx_cmdmenu")
	ASSERT_MENU(id, "Commands Menu 1/1^n^n-----^n2. Admin echo^n3. All echo^n4. Server echo^n^n0. Exit")
	ASSERT_EQ(MenuKeys(id), MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_0)

	// "bd": the admin's console only, then the menu again.
	new before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 2")
	ASSERT_MSG(id, "stufftext", "echo bench_admin")
	ASSERT_EQ(bench_msg_count(other, "stufftext"), 0)
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before + 1)

	// "c": every client's console; the menu closes.
	before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 3")
	ASSERT_MSG(id, "stufftext", "echo bench_all")
	ASSERT_MSG(other, "stufftext", "echo bench_all")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before)
	ASSERT(MenuClosed(id))

	// "a": the server console.
	bench_puppet_cmd(id, "amx_cmdmenu")
	bench_puppet_cmd(id, "menuselect 4")
	server_exec()
	ASSERT_MSG(0, "server", "bench_server")
	ASSERT_EQ(bench_msg_count(id, "stufftext", "bench_server"), 0)

	// No configs.ini.
	bench_puppet_cmd(id, "amx_cfgmenu")
	ASSERT_MENU(id, "Configs Menu 1/1^n^n^n0. Exit")

	// speech.ini: every entry with four fields is listed, whatever its sound.
	bench_puppet_cmd(id, "amx_speechmenu")
	ASSERT_MENU(id, "Speech Menu 1/1^n^n1. Vox^n2. Mp3^n3. Mp3 loop^n4. Slash^n5. Wav^n6. Missing^n7. Say^n^n0. Exit")
	bench_puppet_cmd(id, "menuselect 4")
	ASSERT_MSG(other, "stufftext", "spk ^"/debris/bustcrate1^"")

	// cvars.ini: eight cvars on the first page, the ninth on the second.
	SetFlags(id, "gu")
	bench_puppet_cmd(id, "amx_cvarmenu")
	ASSERT_MENU(id, "Cvars Menu 1/2^n^n1. bench_cvarmenu1    a^n")
	ASSERT_MENU(id, "8. bench_cvarmenu8    a^n^n9. More...^n0. Exit")
	ASSERT_EQ(MenuKeys(id), 0x3FF)
	bench_puppet_cmd(id, "menuselect 9")
	ASSERT_MENU(id, "Cvars Menu 2/2^n^n1. bench_cvarmenu9    a^n^n0. Back")
	bench_puppet_cmd(id, "menuselect 1")
	ASSERT_MENU(id, "Cvars Menu 2/2^n^n1. bench_cvarmenu9    b^n")
	bench_puppet_cmd(id, "menuselect 1")
	ASSERT_MENU(id, "1. bench_cvarmenu9    a^n")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MENU(id, "Cvars Menu 1/2^n")

	SwapConfig("speech.ini", "")
	SwapConfig("cvars.ini", "")
	bench_change_map("", "ConfigsNone_Map")
}

public ConfigsNone_Map()
{
	SpawnPuppets("cnone", 1, "ConfigsNone_Spawned")
}

public ConfigsNone_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "gu")
	bench_puppet_cmd(id, "amx_speechmenu")
	ASSERT_MENU(id, "Speech Menu 1/1^n^n^n0. Exit")
	bench_puppet_cmd(id, "amx_cvarmenu")
	ASSERT_MENU(id, "Cvars Menu 1/0^n^n^n0. Exit")

	RestoreConfigs()
	bench_change_map("", "ConfigsBack_Map")
}

public ConfigsBack_Map()
{
	SpawnPuppets("cback", 1, "ConfigsBack_Spawned")
}

public ConfigsBack_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "gu")
	bench_puppet_cmd(id, "amx_cmdmenu")
	ASSERT_MENU(id, "Commands Menu 1/1^n^n1. Pause^n")
	bench_puppet_cmd(id, "amx_speechmenu")
	ASSERT_MENU(id, "Speech Menu 1/3^n")
	bench_puppet_cmd(id, "amx_cvarmenu")
	ASSERT_MENU(id, "Cvars Menu 1/1^n^n1. mp_timelimit")
	bench_pass()
}
