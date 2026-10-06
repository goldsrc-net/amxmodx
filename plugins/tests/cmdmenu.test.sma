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

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

new const g_Cvars[][] = { "mp_timelimit", "sv_password", "pausable", "sv_voiceenable", "mp_chattime", "mp_logmessages" }
new g_Saved[sizeof(g_Cvars)][32]

new g_P[MAX_PLAYERS + 1]
new g_PNum

public plugin_init()
{
	register_plugin("Commands Menu Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("cmdmenu.sma", 254, 254, "colored menus, which AMX Mod X turns off for ts")
	bench_coverage_ignore("cmdmenu.sma", 449, 449, "colored menus, which AMX Mod X turns off for ts")
}

public bench_setup()
{
	for (new i = 0; i < sizeof(g_Cvars); i++)
		get_cvar_string(g_Cvars[i], g_Saved[i], charsmax(g_Saved[]))
}

public bench_teardown()
{
	for (new i = 0; i < sizeof(g_Cvars); i++)
		set_cvar_string(g_Cvars[i], g_Saved[i])
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
	// "a": amx_pause runs from the server console (admincmd turns pausable on for it).
	server_exec()
	ASSERT_EQ(get_cvar_num("pausable"), 1)
	ASSERT_MSG(id, "", "pause server")
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

// 21 entries make three pages, so the title should read 1/3. cmdmenu.sma:238 adds the remainder
// (21 % 8 = 5) instead of one page for it and shows 1/7.
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
