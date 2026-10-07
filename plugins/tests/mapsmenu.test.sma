// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for mapsmenu.sma (Maps Menu): the changelevel menu (amx_mapmenu) and the votemap menu
// (amx_votemapmenu), answered by puppets with menuselect. The map change the plugin asks for is
// blocked here in server_changelevel and recorded, so the tests can check which map it asked
// for without ending the run. The map list is read the way the plugin reads it. One test gives
// the plugin other map lists to read at load (a maps.ini of its own, then none at all) by
// changing the map, and puts the files back.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#define TASK_CHECKVOTES		34567
#define TASK_AUTOREFUSE		4545454

new const g_Cvars[][] =
{
	"amx_vote_time", "amx_vote_answers", "amx_vote_delay", "amx_votemap_ratio"
}
new g_Saved[sizeof(g_Cvars)][16]

new g_Maps[64][32]
new g_MapCount

new g_P[4]
new g_PuppetCount
new g_ChangeMap[32]
new bool:g_Blocking
new g_CallerUserId

// A file a test moves aside is kept as <file>.bench; the marker stands for a file that was not there.
#define NO_FILE_MARKER	"; amxxbench: there was no such file"

public plugin_init()
{
	register_plugin("Maps Menu Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("mapsmenu.sma", 199, 199, "More is only offered while a further page exists, and the map list never shrinks")
	bench_coverage_ignore("mapsmenu.sma", 215, 215, "colored_menus() is false on The Specialists")
	bench_coverage_ignore("mapsmenu.sma", 389, 389, "Start Voting only has a key once a map is selected")
	bench_coverage_ignore("mapsmenu.sma", 480, 480, "More is only offered while a further page exists, and the map list never shrinks")
	LoadMaps()
}

// Every map change a plugin asks for during these tests is blocked: one would end the run. Other
// files' tests are left alone.
public server_changelevel(map[])
{
	if (!g_Blocking)
		return PLUGIN_CONTINUE
	copy(g_ChangeMap, charsmax(g_ChangeMap), map)
	return PLUGIN_HANDLED
}

public bench_setup()
{
	// Files left moved aside by a run that stopped before it put them back.
	RestoreMapFiles()
	for (new i = 0; i < sizeof(g_Cvars); i++)
		get_cvar_string(g_Cvars[i], g_Saved[i], charsmax(g_Saved[]))
	// A vote lasts amx_vote_time + 2 seconds.
	set_cvar_num("amx_vote_time", 1)
	set_cvar_num("amx_vote_answers", 1)
	set_cvar_float("amx_last_voting", 0.0)
	g_PuppetCount = 0
	g_ChangeMap[0] = 0
	g_Blocking = true
}

public bench_teardown()
{
	g_Blocking = false
	for (new i = 1; i <= MAX_PLAYERS; i++)
		remove_task(TASK_CHECKVOTES + i, 1)
	remove_task(TASK_AUTOREFUSE, 1)
	RestoreCvars()
	set_cvar_float("amx_last_voting", 0.0)
	RestoreMapFiles()
}

// Puts the vote cvars back once. A test that changes the map calls it first: the copy of this
// file on the new map has no saved values.
RestoreCvars()
{
	if (!g_Saved[0][0])
		return
	for (new i = 0; i < sizeof(g_Cvars); i++)
		set_cvar_string(g_Cvars[i], g_Saved[i])
	g_Saved[0][0] = 0
}

// configs/maps.ini, and the map cycle (mapcyclefile, which is mapcycle.txt here).
MapsIni(path[], len)
{
	get_configsdir(path, len)
	add(path, len, "/maps.ini")
}

MapCycle(path[], len)
{
	get_cvar_string("mapcyclefile", path, len)
}

// Moves file aside as <file>.bench (a marker if there is none), unless it already is.
MoveAside(const file[])
{
	new saved[PLATFORM_MAX_PATH]
	formatex(saved, charsmax(saved), "%s.bench", file)
	if (file_exists(saved))
		return
	if (file_exists(file))
		rename_file(file, saved, 1)
	else
		write_file(saved, NO_FILE_MARKER)
}

// Puts back a file moved aside, dropping whatever a test left in its place.
PutBack(const file[])
{
	new saved[PLATFORM_MAX_PATH], line[64], len
	formatex(saved, charsmax(saved), "%s.bench", file)
	if (!file_exists(saved))
		return
	delete_file(file)
	read_file(saved, 0, line, charsmax(line), len)
	if (equal(line, NO_FILE_MARKER))
		delete_file(saved)
	else
		rename_file(saved, file, 1)
}

RestoreMapFiles()
{
	new path[PLATFORM_MAX_PATH]
	MapsIni(path, charsmax(path))
	PutBack(path)
	MapCycle(path, charsmax(path))
	PutBack(path)
}

// ---------------------------------------------------------------------------------------------
// Helpers

// The maps in the menus: configs/maps.ini, else the map cycle, valid maps only (load_settings).
LoadMaps()
{
	new path[PLATFORM_MAX_PATH]
	get_configsdir(path, charsmax(path))
	add(path, charsmax(path), "/maps.ini")
	if (!file_exists(path))
		get_cvar_string("mapcyclefile", path, charsmax(path))
	if (!file_exists(path))
		copy(path, charsmax(path), "mapcycle.txt")

	new f = fopen(path, "r")
	if (!f)
		return
	new text[256], map[32], len
	while (fgets(f, text, charsmax(text)) && g_MapCount < sizeof(g_Maps))
	{
		if (text[0] == ';' || parse(text, map, charsmax(map)) < 1)
			continue
		if (!is_map_valid(map))
		{
			len = strlen(map) - 4
			if (len < 0 || !equali(map[len], ".bsp"))
				continue
			map[len] = 0
			if (!is_map_valid(map))
				continue
		}
		copy(g_Maps[g_MapCount++], charsmax(g_Maps[]), map)
	}
	fclose(f)
}

Pages(perPage)
{
	return g_MapCount / perPage + ((g_MapCount % perPage) ? 1 : 0)
}

AddPuppet(const name[], bool:bot = false)
{
	new id = bench_puppet(name, bot)
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

// The keys the newest ShowMenu message sent to id enables.
MenuKeys(id)
{
	new BenchMsg:msg = bench_msg_last(id, "ShowMenu")
	return msg == BenchMsg:0 ? -1 : bench_msg_int(msg, 0)
}

public MapChangeAsked()
{
	return g_ChangeMap[0] != 0
}

// ---------------------------------------------------------------------------------------------
// Access

public test_menus_need_access()
{
	ASSERT(AddPuppet("nomapaccess") > 0)
	WaitForPuppets("NoAccess_Ready")
}

public NoAccess_Ready()
{
	new id = g_P[0]
	bench_puppet_cmd(id, "amx_mapmenu")
	bench_puppet_cmd(id, "amx_votemapmenu")
	ASSERT_EQ(bench_msg_count(id, "", "You have no access to that command"), 2)
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_mapmenu

public test_changelevel_menu_pages()
{
	ASSERT(g_MapCount > 8)
	ASSERT(AddPuppet("mappager") > 0)
	WaitForPuppets("Pages_Ready")
}

public Pages_Ready()
{
	new id = g_P[0], text[64]
	SetAccess(id, ADMIN_MAP)
	bench_puppet_cmd(id, "amx_mapmenu")
	formatex(text, charsmax(text), "Changelevel Menu 1/%d", Pages(8))
	ASSERT_MENU(id, text)
	formatex(text, charsmax(text), "1. %s^n", g_Maps[0])
	ASSERT_MENU(id, text)
	formatex(text, charsmax(text), "8. %s^n", g_Maps[7])
	ASSERT_MENU(id, text)
	ASSERT_MENU(id, "9. More...")
	ASSERT_MENU(id, "0. Exit")
	ASSERT_EQ(MenuKeys(id), 0x3FF)

	bench_puppet_cmd(id, "menuselect 9")
	formatex(text, charsmax(text), "Changelevel Menu 2/%d", Pages(8))
	ASSERT_MENU(id, text)
	formatex(text, charsmax(text), "1. %s^n", g_Maps[8])
	ASSERT_MENU(id, text)
	ASSERT_MENU(id, "0. Back")

	// On to the last page, which has no More.
	for (new page = 2; page < Pages(8); page++)
		bench_puppet_cmd(id, "menuselect 9")
	formatex(text, charsmax(text), "Changelevel Menu %d/%d", Pages(8), Pages(8))
	ASSERT_MENU(id, text)
	ASSERT_NO_MENU(id, "More")
	ASSERT_MENU(id, "0. Back")

	// Back to the first page, then Exit closes the menu without a new one.
	for (new page = Pages(8); page > 1; page--)
		bench_puppet_cmd(id, "menuselect 10")
	formatex(text, charsmax(text), "Changelevel Menu 1/%d", Pages(8))
	ASSERT_MENU(id, text)
	new menus = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), menus)
	ASSERT_FALSE(MapChangeAsked())
	bench_pass()
}

public test_changelevel_menu_changes_map()
{
	ASSERT(g_MapCount > 1)
	ASSERT(AddPuppet("mapchanger") > 0)
	ASSERT(AddPuppet("mapwatcher") > 0)
	WaitForPuppets("Change_Ready")
}

public Change_Ready()
{
	new id = g_P[0], text[64]
	SetAccess(id, ADMIN_MAP)
	bench_puppet_cmd(id, "amx_mapmenu")
	bench_puppet_cmd(id, "menuselect 2")
	formatex(text, charsmax(text), "changelevel %s", g_Maps[1])
	ASSERT_MSG(g_P[1], "", text)
	// The change comes two seconds later.
	ASSERT_FALSE(MapChangeAsked())
	bench_wait_until("MapChangeAsked", "Change_Done", 10.0)
}

public Change_Done()
{
	ASSERT_STR_EQ(g_ChangeMap, g_Maps[1])
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_votemapmenu

public test_votemap_menu_pages()
{
	ASSERT(g_MapCount > 7)
	ASSERT(AddPuppet("votepager") > 0)
	WaitForPuppets("VotePages_Ready")
}

public VotePages_Ready()
{
	new id = g_P[0], text[64]
	SetAccess(id, ADMIN_VOTE)
	bench_puppet_cmd(id, "amx_votemapmenu")
	formatex(text, charsmax(text), "Votemap Menu 1/%d", Pages(7))
	ASSERT_MENU(id, text)
	formatex(text, charsmax(text), "7. %s^n", g_Maps[6])
	ASSERT_MENU(id, text)
	// Nothing selected yet: Start Voting is shown without a key.
	ASSERT_MENU(id, "#. Start Voting")
	ASSERT_MENU(id, "9. More...")
	ASSERT_MENU(id, "0. Exit")
	ASSERT_EQ(MenuKeys(id), 0x37F)

	for (new page = 1; page < Pages(7); page++)
		bench_puppet_cmd(id, "menuselect 9")
	formatex(text, charsmax(text), "Votemap Menu %d/%d", Pages(7), Pages(7))
	ASSERT_MENU(id, text)
	ASSERT_NO_MENU(id, "More")
	ASSERT_MENU(id, "0. Back")

	for (new page = Pages(7); page > 1; page--)
		bench_puppet_cmd(id, "menuselect 10")
	formatex(text, charsmax(text), "Votemap Menu 1/%d", Pages(7))
	ASSERT_MENU(id, text)
	new menus = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), menus)
	bench_pass()
}

public test_votemap_four_maps_passes_and_is_refused()
{
	ASSERT(g_MapCount > 8)
	ASSERT(AddPuppet("votecaller") > 0)
	ASSERT(AddPuppet("votevoter") > 0)
	WaitForPuppets("Four_Ready")
}

public Four_Ready()
{
	new caller = g_P[0], voter = g_P[1], text[64]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_votemapmenu")
	bench_puppet_cmd(caller, "menuselect 1")
	// A selected map has no key, Start Voting gets one, and the selection is listed.
	formatex(text, charsmax(text), "#. %s^n", g_Maps[0])
	ASSERT_MENU(caller, text)
	ASSERT_MENU(caller, "8. Start Voting")
	formatex(text, charsmax(text), "Selected Maps:^n%s^n", g_Maps[0])
	ASSERT_MENU(caller, text)

	// The first map of page 2 is g_Maps[7].
	bench_puppet_cmd(caller, "menuselect 9")
	bench_puppet_cmd(caller, "menuselect 1")
	formatex(text, charsmax(text), "%s^n%s^n", g_Maps[0], g_Maps[7])
	ASSERT_MENU(caller, text)
	bench_puppet_cmd(caller, "menuselect 10")
	bench_puppet_cmd(caller, "menuselect 2")
	bench_puppet_cmd(caller, "menuselect 3")
	// Four maps: every map loses its key.
	formatex(text, charsmax(text), "#. %s^n", g_Maps[5])
	ASSERT_MENU(caller, text)
	ASSERT_EQ(MenuKeys(caller), 0x380)

	bench_puppet_cmd(caller, "menuselect 8")
	ASSERT_MSG(voter, "", "vote map(s)")
	ASSERT_MENU(voter, "Which map do you want?")
	formatex(text, charsmax(text), "2. %s^n", g_Maps[7])
	ASSERT_MENU(voter, text)
	formatex(text, charsmax(text), "4. %s^n", g_Maps[2])
	ASSERT_MENU(voter, text)
	ASSERT_MENU(voter, "9. None")
	ASSERT_NO_MENU(voter, "Cancel Vote")
	ASSERT_MENU(caller, "0. Cancel Vote")
	ASSERT(task_exists(TASK_CHECKVOTES + caller, 1))

	bench_puppet_cmd(voter, "menuselect 2")
	ASSERT_MSG(voter, "", "votevoter voted for option #2")
	bench_wait_message(caller, "ShowMenu", "The winner", "Four_Result", 10.0)
}

public Four_Result(caller)
{
	new text[96]
	formatex(text, charsmax(text), "Voting successful. Map will be changed to %s", g_Maps[7])
	ASSERT_MSG(g_P[1], "", text)
	formatex(text, charsmax(text), "The winner: %s", g_Maps[7])
	ASSERT_MENU(caller, text)
	ASSERT_MENU(caller, "Do you want to continue?")
	bench_puppet_cmd(caller, "menuselect 2")
	ASSERT_MSG(caller, "", "Result refused")
	ASSERT_FALSE(task_exists(TASK_AUTOREFUSE, 1))
	bench_next("Four_NoChange", 3.0)
}

public Four_NoChange()
{
	ASSERT_FALSE(MapChangeAsked())
	bench_pass()
}

public test_votemap_one_map_accepted()
{
	ASSERT(g_MapCount > 2)
	ASSERT(AddPuppet("onecaller") > 0)
	ASSERT(AddPuppet("onevoter") > 0)
	WaitForPuppets("One_Ready")
}

public One_Ready()
{
	new caller = g_P[0], voter = g_P[1], text[64]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_votemapmenu")
	bench_puppet_cmd(caller, "menuselect 3")
	bench_puppet_cmd(caller, "menuselect 8")
	formatex(text, charsmax(text), "Change map to^n%s?", g_Maps[2])
	ASSERT_MENU(voter, text)
	ASSERT_MENU(voter, "1. Yes")
	ASSERT_EQ(MenuKeys(voter), MENU_KEY_1|MENU_KEY_2)
	bench_puppet_cmd(voter, "menuselect 1")
	bench_wait_message(caller, "ShowMenu", "The winner", "One_Result", 10.0)
}

public One_Result(caller)
{
	bench_puppet_cmd(caller, "menuselect 1")
	ASSERT_MSG(g_P[1], "", "Result accepted")
	bench_wait_until("MapChangeAsked", "One_Changed", 10.0)
}

public One_Changed()
{
	ASSERT_STR_EQ(g_ChangeMap, g_Maps[2])
	bench_pass()
}

public test_votemap_caller_leaves_before_result()
{
	ASSERT(g_MapCount > 3)
	ASSERT(AddPuppet("leavingcaller") > 0)
	ASSERT(AddPuppet("stayingvoter") > 0)
	WaitForPuppets("Leave_Ready")
}

public Leave_Ready()
{
	new caller = g_P[0], voter = g_P[1]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_votemapmenu")
	bench_puppet_cmd(caller, "menuselect 4")
	bench_puppet_cmd(caller, "menuselect 8")
	bench_puppet_cmd(voter, "menuselect 1")
	g_CallerUserId = get_user_userid(caller)
	server_cmd("kick #%d", g_CallerUserId)
	server_exec()
	// With nobody to confirm it, the winner is changed to straight away.
	bench_wait_until("MapChangeAsked", "Leave_Changed", 15.0)
}

public Leave_Changed()
{
	new text[96]
	formatex(text, charsmax(text), "Voting successful. Map will be changed to %s", g_Maps[3])
	ASSERT_MSG(g_P[1], "", text)
	ASSERT_STR_EQ(g_ChangeMap, g_Maps[3])
	bench_pass()
}

// The votes are counted the same when only bots are left (checkVotes counts at least one player).
public test_votemap_with_only_a_bot_left()
{
	ASSERT(g_MapCount > 4)
	ASSERT(AddPuppet("botcaller") > 0)
	ASSERT(AddPuppet("benchbot", true) > 0)
	WaitForPuppets("Bot_Ready")
}

public Bot_Ready()
{
	new caller = g_P[0], bot = g_P[1]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_votemapmenu")
	bench_puppet_cmd(caller, "menuselect 5")
	bench_puppet_cmd(caller, "menuselect 8")
	ASSERT_EQ(MenuKeys(bot), MENU_KEY_1|MENU_KEY_2)
	// Chat is not sent to bots, so only the result shows the vote counted.
	bench_puppet_cmd(bot, "menuselect 1")
	ASSERT_MSG(caller, "", "benchbot voted for option #1")
	server_cmd("kick #%d", get_user_userid(caller))
	server_exec()
	ASSERT_EQ(get_playersnum(), 1)
	bench_wait_until("MapChangeAsked", "Bot_Changed", 15.0)
}

public Bot_Changed()
{
	ASSERT_STR_EQ(g_ChangeMap, g_Maps[4])
	bench_pass()
}

public test_votemap_fails_without_votes()
{
	ASSERT(AddPuppet("lonevoter") > 0)
	WaitForPuppets("Fail_Ready")
}

public Fail_Ready()
{
	new caller = g_P[0]
	SetAccess(caller, ADMIN_VOTE)
	bench_puppet_cmd(caller, "amx_votemapmenu")
	bench_puppet_cmd(caller, "menuselect 1")
	bench_puppet_cmd(caller, "menuselect 8")
	bench_wait_message(caller, "", "Voting failed", "Fail_Checked", 10.0)
}

public Fail_Checked(caller)
{
	ASSERT_EQ(bench_msg_count(caller, "ShowMenu", "The winner"), 0)
	ASSERT_FALSE(MapChangeAsked())
	bench_pass()
}

public test_votemap_cancelled_by_caller()
{
	ASSERT(AddPuppet("cancelcaller") > 0)
	ASSERT(AddPuppet("quietvoter") > 0)
	WaitForPuppets("Cancel_Ready")
}

public Cancel_Ready()
{
	new caller = g_P[0], voter = g_P[1]
	SetAccess(caller, ADMIN_VOTE)
	set_cvar_num("amx_vote_answers", 0)
	bench_puppet_cmd(caller, "amx_votemapmenu")
	bench_puppet_cmd(caller, "menuselect 1")
	bench_puppet_cmd(caller, "menuselect 2")
	bench_puppet_cmd(caller, "menuselect 8")
	// amx_vote_answers 0: the vote is counted without being announced.
	bench_puppet_cmd(voter, "menuselect 1")
	ASSERT_EQ(bench_msg_count(voter, "", "voted for"), 0)
	ASSERT(task_exists(TASK_CHECKVOTES + caller, 1))
	bench_puppet_cmd(caller, "menuselect 10")
	ASSERT_MSG(voter, "", "Voting has been canceled")
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES + caller, 1))
	ASSERT(get_cvar_float("amx_last_voting") > 0.0)
	bench_pass()
}

public test_votemap_refused_while_busy_or_too_soon()
{
	ASSERT(AddPuppet("busycaller") > 0)
	WaitForPuppets("Busy_Ready")
}

public Busy_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_VOTE)
	set_cvar_float("amx_last_voting", get_gametime() + 100.0)
	bench_puppet_cmd(id, "amx_votemapmenu")
	ASSERT_MSG(id, "", "There is already one voting...")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), 0)

	// A vote starts while the menu is open.
	set_cvar_float("amx_last_voting", 0.0)
	bench_puppet_cmd(id, "amx_votemapmenu")
	bench_puppet_cmd(id, "menuselect 1")
	set_cvar_float("amx_last_voting", get_gametime() + 100.0)
	bench_puppet_cmd(id, "menuselect 8")
	ASSERT_EQ(bench_msg_count(id, "", "There is already one voting..."), 2)

	// The last vote ended a second ago, and amx_vote_delay asks for a minute between votes.
	set_cvar_float("amx_last_voting", get_gametime() - 1.0)
	set_cvar_num("amx_vote_delay", 60)
	bench_puppet_cmd(id, "amx_votemapmenu")
	bench_puppet_cmd(id, "menuselect 1")
	bench_puppet_cmd(id, "menuselect 8")
	ASSERT_MSG(id, "", "Voting not allowed at this time")
	ASSERT_FALSE(task_exists(TASK_CHECKVOTES + id, 1))
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The map list, read once when the plugin loads

// The plugin's own maps.ini: comments, blank lines, names too short to end in ".bsp" and maps
// that do not exist are skipped, and a ".bsp" ending is cut off. Then no maps.ini and no map
// cycle: both menus say there are no maps. The files are put back and the map changed once more,
// so the tests after this one see the usual list.
public test_map_list_read_at_load()
{
	bench_set_timeout(180.0)
	ASSERT(is_map_valid("ts_lobby"))
	new path[PLATFORM_MAX_PATH]
	MapsIni(path, charsmax(path))
	MoveAside(path)
	write_file(path, "; Maps for mapsmenu.test.sma")
	write_file(path, "")
	write_file(path, "ab")
	write_file(path, "ts_lobby.bsp")
	write_file(path, "bench_nosuch.bsp")
	write_file(path, "bench_nosuch")
	write_file(path, "ts_lobby")
	RestoreCvars()
	bench_change_map("", "OwnList_Loaded")
}

public OwnList_Loaded()
{
	ASSERT(AddPuppet("listreader") > 0)
	WaitForPuppets("OwnList_Ready")
}

public OwnList_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_MAP|ADMIN_VOTE)
	bench_puppet_cmd(id, "amx_mapmenu")
	ASSERT_MENU(id, "Changelevel Menu 1/1^n^n1. ts_lobby^n2. ts_lobby^n^n0. Exit")
	ASSERT_EQ(MenuKeys(id), MENU_KEY_1|MENU_KEY_2|MENU_KEY_0)
	bench_puppet_cmd(id, "menuselect 10")
	bench_puppet_cmd(id, "amx_votemapmenu")
	ASSERT_MENU(id, "Votemap Menu 1/1^n^n1. ts_lobby^n2. ts_lobby^n^n#. Start Voting")
	bench_puppet_cmd(id, "menuselect 10")

	// No maps.ini, and no map cycle either.
	new path[PLATFORM_MAX_PATH]
	MapsIni(path, charsmax(path))
	delete_file(path)
	MapCycle(path, charsmax(path))
	ASSERT_STR_EQ(path, "mapcycle.txt")
	MoveAside(path)
	ASSERT_FALSE(file_exists(path))
	bench_change_map("", "NoList_Loaded")
}

public NoList_Loaded()
{
	ASSERT(AddPuppet("nolistreader") > 0)
	WaitForPuppets("NoList_Ready")
}

public NoList_Ready()
{
	new id = g_P[0]
	SetAccess(id, ADMIN_MAP|ADMIN_VOTE)
	new menus = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "amx_mapmenu")
	bench_puppet_cmd(id, "amx_votemapmenu")
	// Each command tells the console and the chat, and opens no menu.
	ASSERT_EQ(bench_msg_count(id, "", "There are no maps in menu"), 4)
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), menus)

	RestoreMapFiles()
	ASSERT(file_exists("mapcycle.txt"))
	bench_change_map("", "Restored_Loaded")
}

public Restored_Loaded()
{
	// This copy of the file read the usual list again in its plugin_init.
	ASSERT(g_MapCount > 8)
	bench_pass()
}
