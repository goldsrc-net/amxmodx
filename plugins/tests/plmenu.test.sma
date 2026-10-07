// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for plmenu.sma (Players Menu): the kick, ban, slap/slay, team and client commands menus,
// amx_plmenu_bantimes and amx_plmenu_slapdmg. A puppet admin opens each menu and answers it with
// menuselect; other puppets are the players it acts on.
//
// Bans write banned.cfg and listip.cfg in the mod directory; both are saved before each test and
// put back after it, crash-safely (a saved copy or a ".bench-none" marker left by an interrupted
// run means the file there now is that run's), and the bans are lifted. The ban times and slap
// damages are set back to the plugin's defaults.
//
// The client commands test installs its own clcmds.ini (fixtures/plmenu_clcmds.ini), which plmenu
// reads in plugin_init, and changes the map for it; it puts the server's own back the same way
// (a ".bench" copy or a ".bench-none" marker next to it) and changes the map again.
//

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <amxxbench>

new const g_Files[][] = { "banned.cfg", "listip.cfg" }

new g_P[MAX_PLAYERS + 1]
new g_PNum
new g_Banned[MAX_PLAYERS][44]
new g_BannedNum
new g_ClcmdsFile[PLATFORM_MAX_PATH]

public plugin_init()
{
	register_plugin("Players Menu Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	get_configsdir(g_ClcmdsFile, charsmax(g_ClcmdsFile))
	add(g_ClcmdsFile, charsmax(g_ClcmdsFile), "/clcmds.ini")

	bench_coverage_ignore("plmenu.sma", 125, 125, "the cstrike module, which is not loaded on ts")
	bench_coverage_ignore("plmenu.sma", 136, 137, "cstrike and czero only; the server runs ts")
	bench_coverage_ignore("plmenu.sma", 155, 156, "amx_tempban_maxtime missing: admincmd registers it on the server's first map and the engine keeps a cvar for the server's life, so plmenu finds it on every map, even one with admincmd disabled")
	bench_coverage_ignore("plmenu.sma", 207, 221, "runs while AMX Mod X loads plugins, with its debugger off")
	bench_coverage_ignore("plmenu.sma", 224, 224, "a cstrike native called without the module; plmenu only calls them when cstrike is loaded")
	bench_coverage_ignore("plmenu.sma", 365, 365, "colored menus, which AMX Mod X turns off for ts")
	bench_coverage_ignore("plmenu.sma", 425, 425, "an empty ban time list: amx_plmenu_bantimes always leaves at least one")
	bench_coverage_ignore("plmenu.sma", 537, 547, "cstrike teams; the cstrike module is not loaded on ts")
	bench_coverage_ignore("plmenu.sma", 561, 561, "colored menus, which AMX Mod X turns off for ts")
	bench_coverage_ignore("plmenu.sma", 620, 620, "an empty slap list: amx_plmenu_slapdmg always leaves at least two")
	bench_coverage_ignore("plmenu.sma", 708, 708, "colored menus, which AMX Mod X turns off for ts")
	bench_coverage_ignore("plmenu.sma", 761, 776, "TeamInfo and TextMsg handlers registered on cstrike and czero only")
	bench_coverage_ignore("plmenu.sma", 830, 840, "Counter-Strike's class menu (m_iMenu, joinclass), run only with the cstrike module, which is not loaded on ts")
	bench_coverage_ignore("plmenu.sma", 846, 853, "cstrike team change; the cstrike module is not loaded on ts")
	bench_coverage_ignore("plmenu.sma", 864, 864, "Counter-Strike's m_bTeamChanged, set only with the cstrike module, which is not loaded on ts")
	bench_coverage_ignore("plmenu.sma", 869, 871, "mp_limitteams, a Counter-Strike cvar that ts does not have")
	bench_coverage_ignore("plmenu.sma", 879, 882, "allow_spectators, a Counter-Strike cvar that ts does not have")
	bench_coverage_ignore("plmenu.sma", 888, 888, "allow_spectators, a Counter-Strike cvar that ts does not have")
	bench_coverage_ignore("plmenu.sma", 898, 898, "mp_limitteams, a Counter-Strike cvar that ts does not have")
	bench_coverage_ignore("plmenu.sma", 903, 903, "cstrike model reset; the cstrike module is not loaded on ts")
	bench_coverage_ignore("plmenu.sma", 907, 907, "Counter-Strike's m_bTeamChanged, set only with the cstrike module, which is not loaded on ts")
	bench_coverage_ignore("plmenu.sma", 954, 972, "cstrike teams; the cstrike module is not loaded on ts")
	bench_coverage_ignore("plmenu.sma", 989, 989, "colored menus, which AMX Mod X turns off for ts")
	bench_coverage_ignore("plmenu.sma", 1146, 1146, "colored menus, which AMX Mod X turns off for ts")
}

public bench_setup()
{
	new saved[64], none[64]
	for (new i = 0; i < sizeof(g_Files); i++)
	{
		formatex(saved, charsmax(saved), "%s.bench", g_Files[i])
		formatex(none, charsmax(none), "%s.bench-none", g_Files[i])
		if (file_exists(saved) || file_exists(none))
		{
			// Left by a run that stopped before teardown: the file there now is that run's.
			delete_file(g_Files[i])
		}
		else if (file_exists(g_Files[i]))
		{
			rename_file(g_Files[i], saved, 1)
		}
		else
		{
			fclose(fopen(none, "wt"))
		}
	}
	// A run that stopped mid-test may have left 127.0.0.1 banned, which keeps puppets out, or its
	// clcmds.ini in place of the server's.
	server_cmd("removeip 127.0.0.1")
	server_exec()
	RestoreConfig(g_ClcmdsFile)
	g_BannedNum = 0
	g_PNum = 0
}

public bench_teardown()
{
	for (new i = 0; i < g_BannedNum; i++)
	{
		server_cmd("removeid %s", g_Banned[i])
		server_exec()
	}
	server_cmd("removeip 127.0.0.1")
	server_exec()

	new saved[64], none[64]
	for (new i = 0; i < sizeof(g_Files); i++)
	{
		formatex(saved, charsmax(saved), "%s.bench", g_Files[i])
		formatex(none, charsmax(none), "%s.bench-none", g_Files[i])
		delete_file(g_Files[i])
		if (file_exists(saved))
			rename_file(saved, g_Files[i], 1)
		delete_file(none)
	}

	server_cmd("amx_plmenu_bantimes 0 5 10 15 30 45 60")
	server_exec()
	server_cmd("amx_plmenu_slapdmg 0 1 5")
	server_exec()

	RestoreConfig(g_ClcmdsFile)
}

// ---------------------------------------------------------------------------------------------
// Helpers

// Creates count puppets named prefix1..prefixN and calls step once every one is alive.
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
		if (is_user_connected(g_P[i]) && !is_user_alive(g_P[i]) && !is_user_bot(g_P[i]))
		{
			engclient_cmd(g_P[i], "respawn")
			ok = false
		}
	}
	return ok
}

// The Specialists kills a second after a kill (its ClientKill only arms a timer): wait for it.
public PuppetDead(id)
{
	return !is_user_alive(id)
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

// The position (1-based) of player p in the player menus, which list get_players() in order.
PosOf(p)
{
	new players[MAX_PLAYERS], num
	get_players(players, num)
	for (new i = 0; i < num; i++)
		if (players[i] == p)
			return i + 1
	return 0
}

bool:KeyEnabled(id, key)
{
	return (MenuKeys(id) & (1 << (key - 1))) != 0
}

// Remembers p's auth ID so teardown lifts its ban.
RememberBan(p)
{
	get_user_authid(p, g_Banned[g_BannedNum], charsmax(g_Banned[]))
	g_BannedNum++
}

bool:FileHas(const file[], const text[])
{
	new f = fopen(file, "rt")
	if (!f)
		return false
	new line[128], bool:found = false
	while (!found && fgets(f, line, charsmax(line)))
		found = contain(line, text) != -1
	fclose(f)
	return found
}

KickPuppet(p)
{
	server_cmd("kick #%d", get_user_userid(p))
	server_exec()
}

// Puts fixture (empty: no file at all) in place of file, keeping the server's own as file.bench, or
// a file.bench-none marker when it has none. A second call keeps the first one's copy.
SwapConfig(const file[], const fixture[])
{
	new saved[PLATFORM_MAX_PATH], none[PLATFORM_MAX_PATH]
	formatex(saved, charsmax(saved), "%s.bench", file)
	formatex(none, charsmax(none), "%s.bench-none", file)
	if (!file_exists(saved) && !file_exists(none))
	{
		if (file_exists(file))
			rename_file(file, saved, 1)
		else
			fclose(fopen(none, "wt"))
	}
	delete_file(file)
	if (fixture[0])
	{
		new path[PLATFORM_MAX_PATH], line[256]
		bench_fixture(fixture, path, charsmax(path))
		new in = fopen(path, "rt"), out = fopen(file, "wt")
		while (fgets(in, line, charsmax(line)))
			fputs(out, line)
		fclose(in)
		fclose(out)
	}
}

// Puts the server's own file back after SwapConfig.
RestoreConfig(const file[])
{
	new saved[PLATFORM_MAX_PATH], none[PLATFORM_MAX_PATH]
	formatex(saved, charsmax(saved), "%s.bench", file)
	formatex(none, charsmax(none), "%s.bench-none", file)
	if (file_exists(saved))
	{
		delete_file(file)
		rename_file(saved, file, 1)
	}
	else if (file_exists(none))
	{
		delete_file(file)
		delete_file(none)
	}
}

// ---------------------------------------------------------------------------------------------
// Access

public test_no_access()
{
	SpawnPuppets("pnoacc", 1, "NoAccess_Spawned")
}

public NoAccess_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "z")
	bench_puppet_cmd(id, "amx_kickmenu")
	bench_puppet_cmd(id, "amx_banmenu")
	bench_puppet_cmd(id, "amx_slapmenu")
	bench_puppet_cmd(id, "amx_teammenu")
	bench_puppet_cmd(id, "amx_clcmdmenu")
	ASSERT_EQ(bench_msg_count(id, "", "You have no access to that command"), 5)
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Kick

public test_kick()
{
	SpawnPuppets("pkick", 3, "Kick_Spawned")
}

public Kick_Spawned()
{
	new admin = g_P[0], target = g_P[1], immune = g_P[2]
	SetFlags(admin, "c")
	SetFlags(immune, "a")
	bench_puppet_cmd(admin, "amx_kickmenu")
	new line[32]
	ASSERT_MENU(admin, "Kick Menu 1/1^n^n")
	formatex(line, charsmax(line), "%d. pkick1 *^n", PosOf(admin))
	ASSERT_MENU(admin, line)
	formatex(line, charsmax(line), "%d. pkick2^n", PosOf(target))
	ASSERT_MENU(admin, line)
	ASSERT_MENU(admin, "#. pkick3^n")
	ASSERT_MENU(admin, "^n0. Exit")
	ASSERT(KeyEnabled(admin, PosOf(target)))
	ASSERT_FALSE(KeyEnabled(admin, PosOf(immune)))

	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_FALSE(is_user_connected(target))
	ASSERT_MSG(admin, "", "ADMIN pkick1: kick pkick2")
	ASSERT_NOT_MENU(admin, "pkick2")

	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	ASSERT(MenuClosed(admin))
	bench_pass()
}

// Nine players, eight per page: the ninth is alone on page 2. Kicking it leaves page 2 empty, and
// the menu falls back to the first page.
public test_kick_pages()
{
	SpawnPuppets("pkp", 9, "KickPages_Spawned")
}

public KickPages_Spawned()
{
	new admin = g_P[0], last = g_P[8]
	SetFlags(admin, "c")
	ASSERT_EQ(PosOf(last), 9)
	bench_puppet_cmd(admin, "amx_kickmenu")
	ASSERT_MENU(admin, "Kick Menu 1/2^n")
	ASSERT_MENU(admin, "8. pkp8^n^n9. More...^n0. Exit")
	ASSERT_NOT_MENU(admin, "pkp9")
	bench_puppet_cmd(admin, "menuselect 9")
	ASSERT_MENU(admin, "Kick Menu 2/2^n^n1. pkp9^n^n0. Back")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_MENU(admin, "Kick Menu 1/2^n")
	bench_puppet_cmd(admin, "menuselect 9")

	bench_puppet_cmd(admin, "menuselect 1")
	ASSERT_FALSE(is_user_connected(last))
	ASSERT_MSG(admin, "", "ADMIN pkp1: kick pkp9")
	ASSERT_MENU(admin, "Kick Menu 1/1^n")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Ban

// Permanent by default: bots and immune players are greyed, and the ban is announced. The plugin
// bans by auth ID with "banid 0 #<userid> kick", which the engine refuses for a fake client
// ("Couldn't find #userid"), so the puppet stays connected and banned.cfg gets nothing.
public test_ban_permanent()
{
	SpawnPuppets("pban", 3, "BanPerm_Spawned")
}

public BanPerm_Spawned()
{
	new admin = g_P[0], target = g_P[1], immune = g_P[2]
	new bot = bench_puppet("pbanbot", true)
	ASSERT(bot > 0)
	SetFlags(admin, "dl")
	SetFlags(immune, "a")
	bench_puppet_cmd(admin, "amx_banmenu")
	ASSERT_MENU(admin, "Ban Menu 1/1^n^n")
	ASSERT_MENU(admin, "#. pbanbot^n")
	ASSERT_MENU(admin, "#. pban3^n")
	ASSERT_MENU(admin, "^n8. Ban permanently^n^n0. Exit")
	ASSERT_FALSE(KeyEnabled(admin, PosOf(bot)))
	ASSERT(KeyEnabled(admin, PosOf(target)))

	RememberBan(target)
	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "ADMIN pban1: ban pban2 permanently")
	ASSERT_MSG(target, "", "ADMIN pban1: ban pban2 permanently")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)
	bench_pass()
}

// 8 steps through the ban times (5, 10, 15, 30, 45, 60, then permanent again); a timed ban is
// announced with its minutes.
public test_ban_times()
{
	SpawnPuppets("pbt", 2, "BanTimes_Spawned")
}

public BanTimes_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "dl")
	bench_puppet_cmd(admin, "amx_banmenu")
	new const times[] = { 5, 10, 15, 30, 45, 60 }
	new line[32]
	for (new i = 0; i < sizeof(times); i++)
	{
		bench_puppet_cmd(admin, "menuselect 8")
		formatex(line, charsmax(line), "^n8. Ban for %d minutes^n", times[i])
		ASSERT_MENU(admin, line)
	}
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Ban permanently^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Ban for 5 minutes^n")

	RememberBan(target)
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "ADMIN pbt1: ban pbt2 for 5 min")
	ASSERT_MENU(admin, "^n8. Ban for 5 minutes^n")
	bench_pass()
}

// A player without a unique auth ID (STEAM_ID_LAN) is banned by IP instead, into listip.cfg.
public test_ban_lan_id_by_ip()
{
	g_PNum = 0
	g_P[g_PNum++] = bench_puppet("pip1")
	g_P[g_PNum++] = bench_puppet("pip2", false, "STEAM_ID_LAN")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_wait_until("AllAlive", "BanIp_Spawned", 30.0)
}

public BanIp_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "dl")
	new authid[44]
	get_user_authid(target, authid, charsmax(authid))
	ASSERT_STR_EQ(authid, "STEAM_ID_LAN")
	bench_puppet_cmd(admin, "amx_banmenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "ADMIN pip1: ban pip2 permanently")
	ASSERT(FileHas("listip.cfg", "127.0.0.1"))
	bench_pass()
}

// An admin with only temporary ban access ("v") cannot ban permanently, nor for longer than
// amx_tempban_maxtime.
public test_temp_admin_limits()
{
	SpawnPuppets("ptmp", 2, "TempLimits_Spawned")
}

public TempLimits_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "v")
	bench_puppet_cmd(admin, "amx_banmenu")
	ASSERT_MENU(admin, "^n8. Ban permanently^n")
	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "You have no access to that command")
	ASSERT(is_user_connected(target))
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)

	server_cmd("amx_plmenu_bantimes 99999")
	server_exec()
	bench_puppet_cmd(admin, "amx_banmenu")
	ASSERT_MENU(admin, "^n8. Ban for 99999 minutes^n")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_EQ(bench_msg_count(admin, "", "You have no access to that command"), 2)
	ASSERT(is_user_connected(target))
	bench_pass()
}

// amx_plmenu_bantimes without arguments only prints its usage; with arguments it replaces the
// list the menu cycles through.
public test_bantimes_command()
{
	SpawnPuppets("pbcmd", 1, "BanCmd_Spawned")
}

public BanCmd_Spawned()
{
	new admin = g_P[0]
	SetFlags(admin, "d")
	server_cmd("amx_plmenu_bantimes")
	server_exec()
	ASSERT_MSG(0, "server", "usage: amx_plmenu_bantimes <time1> [time2] [time3] ...")
	bench_puppet_cmd(admin, "amx_banmenu")
	ASSERT_MENU(admin, "^n8. Ban permanently^n")

	server_cmd("amx_plmenu_bantimes 7 0")
	server_exec()
	bench_puppet_cmd(admin, "amx_banmenu")
	ASSERT_MENU(admin, "^n8. Ban for 7 minutes^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Ban permanently^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Ban for 7 minutes^n")
	bench_pass()
}

// Eight players: seven on the first page, one on the second. Once the last one leaves, the second
// page is empty and the menu falls back to the first.
public test_ban_pages()
{
	SpawnPuppets("pbp", 8, "BanPages_Spawned")
}

public BanPages_Spawned()
{
	new admin = g_P[0], last = g_P[7]
	SetFlags(admin, "dl")
	bench_puppet_cmd(admin, "amx_banmenu")
	ASSERT_MENU(admin, "Ban Menu 1/2^n")
	ASSERT_MENU(admin, "^n9. More...^n0. Exit")
	ASSERT_NOT_MENU(admin, "pbp8")
	bench_puppet_cmd(admin, "menuselect 9")
	ASSERT_MENU(admin, "Ban Menu 2/2^n^n1. pbp8^n")
	ASSERT_MENU(admin, "^n0. Back")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_MENU(admin, "Ban Menu 1/2^n")
	bench_puppet_cmd(admin, "menuselect 9")

	RememberBan(last)
	bench_puppet_cmd(admin, "menuselect 1")
	ASSERT_MSG(admin, "", "ADMIN pbp1: ban pbp8 permanently")
	ASSERT_MENU(admin, "Ban Menu 2/2^n")
	KickPuppet(last)
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "Ban Menu 1/1^n")

	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	ASSERT(MenuClosed(admin))
	bench_pass()
}

// An admin with ADMIN_BAN ("d") but not ADMIN_RCON can ban permanently from the menu, as amx_ban
// lets them (once refused: the menu tested ~flags & (ADMIN_BAN | ADMIN_RCON), either flag missing).
public test_ban_flag_without_rcon_bans_permanently()
{
	SpawnPuppets("pbug", 2, "BanNoRcon_Spawned")
}

public BanNoRcon_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "d")
	RememberBan(target)
	bench_puppet_cmd(admin, "amx_banmenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_EQ(bench_msg_count(admin, "", "You have no access to that command"), 0)
	ASSERT_MSG(admin, "", "ADMIN pbug1: ban pbug2 permanently")
	bench_pass()
}

// A temporary ban from the menu is recorded for admincmd, so the admin who made it can lift it with
// amx_unban (once lost: g_tempBans was read only for a non-zero xvar id, and 0 is a valid one).
public test_temp_ban_can_be_lifted_by_its_admin()
{
	SpawnPuppets("punb", 2, "TempUnban_Spawned")
}

public TempUnban_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "v")
	new authid[44]
	get_user_authid(target, authid, charsmax(authid))
	RememberBan(target)
	bench_puppet_cmd(admin, "amx_banmenu")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Ban for 5 minutes^n")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "ADMIN punb1: ban punb2 for 5 min")

	bench_puppet_cmd(admin, "amx_unban ^"%s^"", authid)
	ASSERT_EQ(bench_msg_count(admin, "", "You can only unban players that you have recently banned"), 0)
	ASSERT_MSG(admin, "", "unban")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Slap/slay

// 8 steps through 0, 1 and 5 damage and slay; a slap never takes more health than the player
// has.
public test_slap_and_slay()
{
	SpawnPuppets("pslap", 2, "Slap_Spawned")
}

public Slap_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "e")
	set_pev(target, pev_health, 100.0)
	bench_puppet_cmd(admin, "amx_slapmenu")
	ASSERT_MENU(admin, "Slap/Slay Menu 1/1^n^n")
	ASSERT_MENU(admin, "^n8. Slap with 0 damage^n^n0. Exit")
	new line[32]
	formatex(line, charsmax(line), "%d. pslap1 *   ", PosOf(admin))
	ASSERT_MENU(admin, line)
	formatex(line, charsmax(line), "%d. pslap2   ", PosOf(target))
	ASSERT_MENU(admin, line)

	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_EQ(get_user_health(target), 100)
	ASSERT_MSG(admin, "", "ADMIN pslap1: slap pslap2 with 0 damage")

	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slap with 1 damage^n")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_EQ(get_user_health(target), 99)

	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slap with 5 damage^n")
	set_pev(target, pev_health, 3.0)
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT(is_user_alive(target))
	ASSERT_EQ(get_user_health(target), 3)
	ASSERT_MSG(admin, "", "ADMIN pslap1: slap pslap2 with 5 damage")

	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slay^n")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "ADMIN pslap1: slay pslap2")
	bench_wait_until("PuppetDead", "Slay_Dead", 5.0, target)
}

// The menu drawn next greys the slain player.
public Slay_Dead()
{
	new admin = g_P[0]
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slap with 0 damage^n")
	ASSERT_MENU(admin, "#. pslap2   ")
	bench_pass()
}

// A player who dies after the menu was drawn is refused.
public test_slap_dead_target_refused()
{
	SpawnPuppets("psdead", 2, "SlapDead_Spawned")
}

public SlapDead_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "e")
	bench_puppet_cmd(admin, "amx_slapmenu")
	ASSERT(KeyEnabled(admin, PosOf(target)))
	user_kill(target, 1)
	bench_wait_until("PuppetDead", "SlapDead_Dead", 5.0, target)
}

public SlapDead_Dead()
{
	new admin = g_P[0], target = g_P[1]
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "That action can't be performed on dead client ^"psdead2^"")
	ASSERT_EQ(bench_msg_count(admin, "", "slay psdead2"), 0)
	bench_pass()
}

// amx_plmenu_slapdmg without arguments only prints its usage; with arguments it replaces the
// damages, slay always added last.
public test_slapdmg_command()
{
	SpawnPuppets("psdmg", 2, "SlapCmd_Spawned")
}

public SlapCmd_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "e")
	server_cmd("amx_plmenu_slapdmg")
	server_exec()
	ASSERT_MSG(0, "server", "usage: amx_plmenu_slapdmg <dmg1> [dmg2] [dmg3] ...")
	bench_puppet_cmd(admin, "amx_slapmenu")
	ASSERT_MENU(admin, "^n8. Slap with 0 damage^n")

	server_cmd("amx_plmenu_slapdmg 7")
	server_exec()
	set_pev(target, pev_health, 100.0)
	bench_puppet_cmd(admin, "amx_slapmenu")
	ASSERT_MENU(admin, "^n8. Slap with 7 damage^n")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_EQ(get_user_health(target), 93)
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slay^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slap with 7 damage^n")
	bench_pass()
}

// Eight players, seven per page; immune players are greyed.
public test_slap_pages()
{
	SpawnPuppets("psp", 8, "SlapPages_Spawned")
}

public SlapPages_Spawned()
{
	new admin = g_P[0], immune = g_P[1], last = g_P[7]
	SetFlags(admin, "e")
	SetFlags(immune, "a")
	bench_puppet_cmd(admin, "amx_slapmenu")
	ASSERT_MENU(admin, "Slap/Slay Menu 1/2^n")
	ASSERT_MENU(admin, "#. psp2   ")
	ASSERT_FALSE(KeyEnabled(admin, PosOf(immune)))
	ASSERT_MENU(admin, "^n9. More...^n0. Exit")
	bench_puppet_cmd(admin, "menuselect 9")
	ASSERT_MENU(admin, "Slap/Slay Menu 2/2^n^n1. psp8   ")
	ASSERT_MENU(admin, "^n0. Back")

	bench_puppet_cmd(admin, "menuselect 1")
	ASSERT_MSG(admin, "", "ADMIN psp1: slap psp8 with 0 damage")
	ASSERT_MENU(admin, "Slap/Slay Menu 2/2^n")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_MENU(admin, "Slap/Slay Menu 1/2^n")
	bench_puppet_cmd(admin, "menuselect 9")

	KickPuppet(last)
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "Slap/Slay Menu 1/1^n")

	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	ASSERT(MenuClosed(admin))
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Team

// 7 toggles silent transfers, 8 steps through TERRORIST, CT and SPECTATOR. On ts every player's
// team number is 0, which the menu counts as spectator, so the SPECTATOR choice greys them all.
public test_team_menu_options()
{
	SpawnPuppets("ptm", 3, "TeamOptions_Spawned")
}

public TeamOptions_Spawned()
{
	new admin = g_P[0], target = g_P[1], immune = g_P[2]
	SetFlags(admin, "m")
	SetFlags(immune, "a")
	bench_puppet_cmd(admin, "amx_teammenu")
	ASSERT_MENU(admin, "Team Menu 1/1^n^n")
	ASSERT_MENU(admin, "^n7. Silent Transfer: No^n8. Transfer to TERRORIST^n^n0. Exit")
	new line[32]
	formatex(line, charsmax(line), "%d. ptm1 *   ", PosOf(admin))
	ASSERT_MENU(admin, line)
	formatex(line, charsmax(line), "%d. ptm2   ", PosOf(target))
	ASSERT_MENU(admin, line)
	ASSERT_MENU(admin, "#. ptm3   ")
	ASSERT(KeyEnabled(admin, PosOf(target)))
	ASSERT_FALSE(KeyEnabled(admin, PosOf(immune)))
	ASSERT_EQ(MenuKeys(admin) & (MENU_KEY_7|MENU_KEY_8|MENU_KEY_0), MENU_KEY_7|MENU_KEY_8|MENU_KEY_0)

	bench_puppet_cmd(admin, "menuselect 7")
	ASSERT_MENU(admin, "7. Silent Transfer: Yes^n")
	bench_puppet_cmd(admin, "menuselect 7")
	ASSERT_MENU(admin, "7. Silent Transfer: No^n")

	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "8. Transfer to CT^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "8. Transfer to SPECTATOR^n")
	ASSERT_MENU(admin, "#. ptm2   ")
	ASSERT_FALSE(KeyEnabled(admin, PosOf(target)))
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "8. Transfer to TERRORIST^n")
	bench_pass()
}

// A player who left after the menu was drawn: nothing happens but the menu being drawn again.
public test_team_player_gone()
{
	SpawnPuppets("ptg", 2, "TeamGone_Spawned")
}

public TeamGone_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "m")
	bench_puppet_cmd(admin, "amx_teammenu")
	new key = PosOf(target)
	ASSERT(KeyEnabled(admin, key))
	KickPuppet(target)
	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", key)
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)
	ASSERT_EQ(bench_msg_count(admin, "", "transfer"), 0)
	bench_pass()
}

// Eight players, six per page.
public test_team_pages()
{
	SpawnPuppets("ptp", 8, "TeamPages_Spawned")
}

public TeamPages_Spawned()
{
	new admin = g_P[0], last = g_P[7]
	SetFlags(admin, "m")
	bench_puppet_cmd(admin, "amx_teammenu")
	ASSERT_MENU(admin, "Team Menu 1/2^n")
	ASSERT_MENU(admin, "^n9. More...^n0. Exit")
	bench_puppet_cmd(admin, "menuselect 9")
	ASSERT_MENU(admin, "Team Menu 2/2^n^n1. ptp7   ")
	ASSERT_MENU(admin, "2. ptp8   ")
	ASSERT_MENU(admin, "^n0. Back")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_MENU(admin, "Team Menu 1/2^n")
	bench_puppet_cmd(admin, "menuselect 9")

	KickPuppet(last)
	KickPuppet(g_P[6])
	bench_puppet_cmd(admin, "menuselect 7")
	ASSERT_MENU(admin, "Team Menu 1/1^n")

	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	ASSERT(MenuClosed(admin))
	bench_pass()
}

// Transferring a player on a mod other than Counter-Strike completes (once stopped by a run time
// error: Counter-Strike's CBasePlayer members, which the gamedata only has for cstrike, were used on
// any mod with fakemeta).
public test_team_transfer()
{
	SpawnPuppets("ptt", 2, "TeamTransfer_Spawned")
}

public TeamTransfer_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "m")
	bench_puppet_cmd(admin, "amx_teammenu")
	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "ADMIN ptt1: transfer ptt2 to TERRORIST")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)
	bench_wait_until("PuppetDead", "TeamTransfer_Dead", 5.0, target)
}

public TeamTransfer_Dead()
{
	bench_pass()
}

// The same for SPECTATOR, silently (once stopped by reading CBasePlayer::m_iMenu, which the gamedata
// only has for cstrike). On ts every player starts with team number 0, which the menu counts as
// spectator; with pev_team set, the ScoreInfo ts sends when the target dies gives it a non-zero
// one, so the SPECTATOR choice lists it.
public test_team_transfer_spectator_silent()
{
	SpawnPuppets("pts", 2, "TeamSpec_Spawned")
}

public TeamSpec_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "m")
	set_pev(target, pev_team, 1)
	user_kill(target, 1)
	bench_wait_until("PuppetDead", "TeamSpec_Killed", 5.0, target)
}

public TeamSpec_Killed()
{
	new admin = g_P[0], target = g_P[1]
	ASSERT(get_user_team(target) > 0)
	bench_puppet_cmd(admin, "amx_teammenu")
	bench_puppet_cmd(admin, "menuselect 7")
	bench_puppet_cmd(admin, "menuselect 8")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "7. Silent Transfer: Yes^n8. Transfer to SPECTATOR^n")
	ASSERT(KeyEnabled(admin, PosOf(target)))
	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	set_pev(target, pev_team, 0)
	ASSERT_MSG(admin, "", "ADMIN pts1: transfer pts2 to SPECTATOR")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)
	bench_pass()
}

// A silent transfer to a team: the plugin does not kill the player itself (the game's own jointeam
// then decides what happens to them, which on The Specialists is a respawn).
public test_team_transfer_silent()
{
	SpawnPuppets("ptl", 2, "TeamSilent_Spawned")
}

public TeamSilent_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "m")
	bench_puppet_cmd(admin, "amx_teammenu")
	bench_puppet_cmd(admin, "menuselect 7")
	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	ASSERT_MSG(admin, "", "ADMIN ptl1: transfer ptl2 to TERRORIST")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Client commands

// clcmds.ini has four entries, all "u": 8 steps through them. "Slay player" ("bd") runs on the
// admin's console and returns to the menu; "Kick player" ("b") does not return. The commands go
// to the admin with client_cmd (stufftext, which a puppet does not execute).
public test_clcmd_menu()
{
	SpawnPuppets("pcl", 2, "Clcmd_Spawned")
}

public Clcmd_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "mu")
	bench_puppet_cmd(admin, "amx_clcmdmenu")
	ASSERT_MENU(admin, "Client Cmds Menu 1/1^n^n")
	ASSERT_MENU(admin, "^n8. Kick player^n^n0. Exit")
	new line[32]
	formatex(line, charsmax(line), "%d. pcl1 *^n", PosOf(admin))
	ASSERT_MENU(admin, line)
	formatex(line, charsmax(line), "%d. pcl2^n", PosOf(target))
	ASSERT_MENU(admin, line)

	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slay player^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slap with 1 dmg.^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Ban for 5 minutes^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Kick player^n")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Slay player^n")

	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	new cmd[32]
	formatex(cmd, charsmax(cmd), "amx_slay #%d", get_user_userid(target))
	ASSERT_MSG(admin, "stufftext", cmd)
	ASSERT_EQ(bench_msg_count(target, "stufftext"), 0)
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)
	ASSERT_MENU(admin, "^n8. Slay player^n")

	// A player who left: no command, and "d" still brings the menu back.
	new key = PosOf(target)
	KickPuppet(target)
	before = bench_msg_count(admin, "ShowMenu")
	new stuffed = bench_msg_count(admin, "stufftext")
	bench_puppet_cmd(admin, "menuselect %d", key)
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)
	ASSERT_EQ(bench_msg_count(admin, "stufftext"), stuffed)

	// "Kick player" has no "d": the menu closes.
	bench_puppet_cmd(admin, "menuselect 8")
	bench_puppet_cmd(admin, "menuselect 8")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Kick player^n")
	before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(admin))
	formatex(cmd, charsmax(cmd), "amx_kick #%d", get_user_userid(admin))
	ASSERT_MSG(admin, "stufftext", cmd)
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	ASSERT(MenuClosed(admin))
	bench_pass()
}

// Eight players, seven per page; immune players are greyed.
public test_clcmd_pages()
{
	SpawnPuppets("pcp", 8, "ClcmdPages_Spawned")
}

public ClcmdPages_Spawned()
{
	new admin = g_P[0], immune = g_P[1], last = g_P[7]
	SetFlags(admin, "mu")
	SetFlags(immune, "a")
	bench_puppet_cmd(admin, "amx_clcmdmenu")
	ASSERT_MENU(admin, "Client Cmds Menu 1/2^n")
	ASSERT_MENU(admin, "#. pcp2^n")
	ASSERT_MENU(admin, "^n9. More...^n0. Exit")
	bench_puppet_cmd(admin, "menuselect 9")
	ASSERT_MENU(admin, "Client Cmds Menu 2/2^n^n1. pcp8^n")
	ASSERT_MENU(admin, "^n0. Back")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_MENU(admin, "Client Cmds Menu 1/2^n")
	bench_puppet_cmd(admin, "menuselect 9")

	KickPuppet(last)
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "Client Cmds Menu 1/1^n")

	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect 10")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	ASSERT(MenuClosed(admin))
	bench_pass()
}

// An admin who can open the menu but reaches none of clcmds.ini's commands sees "No cmds
// available", and key 8 (which cycles the commands) is off: with nothing to cycle, pressing it once
// divided by zero (g_menuOption % g_menuSelectNum).
public test_clcmd_menu_without_commands()
{
	SpawnPuppets("pcn", 2, "ClcmdNone_Spawned")
}

public ClcmdNone_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "m")
	bench_puppet_cmd(admin, "amx_clcmdmenu")
	ASSERT_MENU(admin, "^n8. No cmds available^n")
	ASSERT_MENU(admin, "#. pcn2^n")
	ASSERT_FALSE(KeyEnabled(admin, PosOf(target)))
	ASSERT_EQ(MenuKeys(admin), MENU_KEY_0)

	// A press of the disabled key is ignored: no run time error, no new menu.
	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	bench_pass()
}

// clcmds.ini as fixtures/plmenu_clcmds.ini has it, read on a new map: "a" runs the command from the
// server console, "b" on the admin's, "c" on the player's, each with %userid% and %authid% filled
// in and \' turned into a quote; "d" brings the menu back. An entry needing "l" is left out. Then a
// map without clcmds.ini, where the menu has no commands, and back to the server's own.
public test_clcmds_ini()
{
	bench_set_timeout(180.0)
	SwapConfig(g_ClcmdsFile, "plmenu_clcmds.ini")
	bench_change_map("", "ClcmdsIni_Map")
}

public ClcmdsIni_Map()
{
	SpawnPuppets("pci", 2, "ClcmdsIni_Spawned")
}

public ClcmdsIni_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	new authid[44], text[96]
	get_user_authid(target, authid, charsmax(authid))
	SetFlags(admin, "mu")
	bench_puppet_cmd(admin, "amx_clcmdmenu")
	ASSERT_MENU(admin, "^n8. Server echo^n")

	// "ad": the server runs it, and the menu comes back.
	new before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	formatex(text, charsmax(text), "bench_clcmd #%d", get_user_userid(target))
	ASSERT_MSG(0, "server", text)
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)
	ASSERT_EQ(bench_msg_count(admin, "stufftext"), 0)

	// "b": on the admin's console; the menu closes.
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Admin echo^n")
	before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	formatex(text, charsmax(text), "echo bench_admin %s", authid)
	ASSERT_MSG(admin, "stufftext", text)
	ASSERT_EQ(bench_msg_count(target, "stufftext"), 0)
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before)
	ASSERT(MenuClosed(admin))

	// "cd": on the player's console, quoted; the menu comes back.
	bench_puppet_cmd(admin, "amx_clcmdmenu")
	bench_puppet_cmd(admin, "menuselect 8")
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Player echo^n")
	before = bench_msg_count(admin, "ShowMenu")
	bench_puppet_cmd(admin, "menuselect %d", PosOf(target))
	formatex(text, charsmax(text), "echo ^"bench_player %s^"", authid)
	ASSERT_MSG(target, "stufftext", text)
	ASSERT_EQ(bench_msg_count(admin, "ShowMenu"), before + 1)

	// Three entries for "u": the fourth press is the first again.
	bench_puppet_cmd(admin, "menuselect 8")
	ASSERT_MENU(admin, "^n8. Server echo^n")
	ASSERT_EQ(bench_msg_count(0, "server", "bench_rcon"), 0)

	SwapConfig(g_ClcmdsFile, "")
	bench_change_map("", "ClcmdsNone_Map")
}

public ClcmdsNone_Map()
{
	SpawnPuppets("pcz", 2, "ClcmdsNone_Spawned")
}

public ClcmdsNone_Spawned()
{
	new admin = g_P[0], target = g_P[1]
	SetFlags(admin, "mu")
	bench_puppet_cmd(admin, "amx_clcmdmenu")
	ASSERT_MENU(admin, "#. pcz2^n")
	ASSERT_MENU(admin, "^n8. No cmds available^n")
	ASSERT_FALSE(KeyEnabled(admin, PosOf(target)))

	RestoreConfig(g_ClcmdsFile)
	bench_change_map("", "ClcmdsBack_Map")
}

public ClcmdsBack_Map()
{
	SpawnPuppets("pcb", 1, "ClcmdsBack_Spawned")
}

public ClcmdsBack_Spawned()
{
	new admin = g_P[0]
	SetFlags(admin, "mu")
	bench_puppet_cmd(admin, "amx_clcmdmenu")
	ASSERT_MENU(admin, "^n8. Kick player^n")
	bench_pass()
}
