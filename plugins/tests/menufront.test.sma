// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for menufront.sma (Menus Front-End): the admin menu (amxmodmenu) with its default items,
// access and paging, the client menu (amx_menu), and adding items with amx_addmenuitem and
// amx_addclientmenuitem up to the 127-item limit. A puppet opens the menus and answers them with
// menuselect.
//
// The plugin has no way to remove an item, so a test that adds items ends by changing the map,
// which takes them away, and checks the menu is back to the items it found (CountItems counts them
// instead of assuming how many there are).
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#define MAXITEMS 127

new g_P[MAX_PLAYERS + 1]
new g_PNum
new g_Count
new g_CountCmd[16]

public plugin_init()
{
	register_plugin("Menus Front-End Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("menufront.sma", 178, 178, "a page past the last one: the admin menu always has its 16 default items and no key leads past the last page")
	bench_coverage_ignore("menufront.sma", 205, 208, "colored menus, which AMX Mod X turns off for ts")
	bench_coverage_ignore("menufront.sma", 264, 267, "colored menus, which AMX Mod X turns off for ts")
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

// Item lines in a page's text: "1. " to "8. " (enabled) and "#. " (greyed).
CountItemLines(const body[])
{
	new n = 0
	for (new i = 0; body[i]; )
	{
		if ((body[i] == '#' || ('1' <= body[i] <= '8')) && body[i + 1] == '.')
			n++
		while (body[i] && body[i] != '^n')
			i++
		if (body[i])
			i++
	}
	return n
}

// Opens the menu with cmd and walks its pages; returns how many items it lists. The last page
// is left open.
CountItems(id, const cmd[])
{
	new body[512], total = 0
	bench_puppet_cmd(id, cmd)
	for (new page = 0; page < 20; page++)
	{
		MenuText(id, body, charsmax(body))
		total += CountItemLines(body)
		if (!(MenuKeys(id) & MENU_KEY_9))
			break
		bench_puppet_cmd(id, "menuselect 9")
	}
	return total
}

// Opens the menu with cmd at page (0-based).
OpenPage(id, const cmd[], page)
{
	bench_puppet_cmd(id, cmd)
	for (new i = 0; i < page; i++)
		bench_puppet_cmd(id, "menuselect 9")
}

AddItem(const cmd[], const text[], const command[], const flags[], const plugin[])
{
	server_cmd("%s ^"%s^" ^"%s^" ^"%s^" ^"%s^"", cmd, text, command, flags, plugin)
	server_exec()
}

// Changes the map to take the added items away; on the new map, the menu opened with cmd must
// list count items again.
ClearItems(const cmd[], count)
{
	bench_change_map("", equal(cmd, "amx_menu") ? "Cleared_ClientMap" : "Cleared_AdminMap", count)
}

public Cleared_AdminMap(count)
{
	g_Count = count
	copy(g_CountCmd, charsmax(g_CountCmd), "amxmodmenu")
	SpawnPuppets("fclear", 1, "Cleared_Spawned")
}

public Cleared_ClientMap(count)
{
	g_Count = count
	copy(g_CountCmd, charsmax(g_CountCmd), "amx_menu")
	SpawnPuppets("fclear", 1, "Cleared_Spawned")
}

public Cleared_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "abcdefghijklmnopqrstuv")
	ASSERT_EQ(CountItems(id, g_CountCmd), g_Count)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Tests

public test_no_access()
{
	SpawnPuppets("fnoacc", 1, "NoAccess_Spawned")
}

public NoAccess_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "z")
	bench_puppet_cmd(id, "amxmodmenu")
	ASSERT_MSG(id, "", "You have no access to that command")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), 0)
	bench_pass()
}

// An admin with every flag: the 16 default items on pages 1 and 2, all enabled but Restrict
// Weapons (restmenu is not loaded on ts), then pluginmenu's two items on page 3.
public test_full_admin_pages()
{
	SpawnPuppets("ffull", 1, "Full_Spawned")
}

public Full_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "abcdefghijklmnopqrstuv")
	bench_puppet_cmd(id, "amxmodmenu")
	ASSERT_MENU(id, "AMX Mod X Menu 1/")
	ASSERT_MENU(id, "^n^n1. Kick Player^n2. Ban Player^n3. Slap/Slay Player^n4. Team Player ^n^n5. Changelevel^n6. Vote for maps ^n^n7. Speech Stuff^n8. Client Commands^n^n9. More...^n0. Exit")
	ASSERT_EQ(MenuKeys(id), 0x3FF)

	bench_puppet_cmd(id, "menuselect 9")
	ASSERT_MENU(id, "AMX Mod X Menu 2/")
	ASSERT_MENU(id, "^n^n1. Server Commands^n2. Cvars Settings^n3. Configuration^n4. Language Settings^n5. Stats Settings ^n^n6. Pause Plugins^n#. Restrict Weapons^n8. Teleport Player^n^n9. More...^n0. Back")
	ASSERT_EQ(MenuKeys(id), 0x3BF)

	// pluginmenu's items name it by file name, not plugin name.
	bench_puppet_cmd(id, "menuselect 9")
	ASSERT_MENU(id, "AMX Mod X Menu 3/")
	ASSERT_MENU(id, "^n^n1. Plugin Cvars^n2. Plugin Commands^n")
	ASSERT(MenuKeys(id) & (MENU_KEY_1|MENU_KEY_2))

	// The last page has Back and no More.
	new pages = 3
	while (MenuKeys(id) & MENU_KEY_9)
	{
		bench_puppet_cmd(id, "menuselect 9")
		pages++
	}
	ASSERT_MENU(id, "^n0. Back")
	ASSERT_NOT_MENU(id, "9. More")
	new header[32]
	formatex(header, charsmax(header), "AMX Mod X Menu %d/%d^n", pages, pages)
	ASSERT_MENU(id, header)

	// Back to the first page, then out.
	for (new i = 1; i < pages; i++)
		bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MENU(id, "AMX Mod X Menu 1/")
	new before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before)
	ASSERT(MenuClosed(id))
	bench_pass()
}

// An admin with kick and menu access: only the items those flags reach are enabled.
public test_limited_admin()
{
	SpawnPuppets("flim", 1, "Limited_Spawned")
}

public Limited_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "cu")
	bench_puppet_cmd(id, "amxmodmenu")
	ASSERT_MENU(id, "^n^n1. Kick Player^n#. Ban Player^n#. Slap/Slay Player^n#. Team Player ^n^n#. Changelevel^n#. Vote for maps ^n^n7. Speech Stuff^n#. Client Commands^n")
	ASSERT_EQ(MenuKeys(id), MENU_KEY_1|MENU_KEY_7|MENU_KEY_9|MENU_KEY_0)
	bench_pass()
}

// Picking an item closes the menu and has the player run the item's command (client_cmd: a
// stufftext, which a puppet does not execute).
public test_item_closes_menu()
{
	SpawnPuppets("fitem", 1, "Item_Spawned")
}

public Item_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "cu")
	bench_puppet_cmd(id, "amxmodmenu")
	new before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 1")
	ASSERT_MSG(id, "stufftext", "amx_kickmenu")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before)
	ASSERT(MenuClosed(id))
	bench_pass()
}

// amx_addmenuitem needs four arguments; text that is not a language key is shown as is, and an
// item whose plugin is not loaded is greyed.
public test_add_admin_items()
{
	SpawnPuppets("fadd", 1, "AddAdmin_Spawned")
}

public AddAdmin_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "abcdefghijklmnopqrstuv")
	new count = CountItems(id, "amxmodmenu")
	ASSERT(count >= 18)
	bench_set_timeout(60.0)

	server_cmd("amx_addmenuitem ^"Bench Short^" bench_short")
	server_exec()
	ASSERT_EQ(CountItems(id, "amxmodmenu"), count)

	AddItem("amx_addmenuitem", "Bench Item", "bench_item", "", "Menus Front-End")
	AddItem("amx_addmenuitem", "Bench Hidden", "bench_hidden", "", "No Such Plugin")
	ASSERT_EQ(CountItems(id, "amxmodmenu"), count + 2)

	new line[32]
	OpenPage(id, "amxmodmenu", count / 8)
	formatex(line, charsmax(line), "^n%d. Bench Item^n", count % 8 + 1)
	ASSERT_MENU(id, line)
	ASSERT(MenuKeys(id) & (1 << (count % 8)))
	OpenPage(id, "amxmodmenu", (count + 1) / 8)
	ASSERT_MENU(id, "^n#. Bench Hidden^n")
	ASSERT_FALSE(MenuKeys(id) & (1 << ((count + 1) % 8)))
	ClearItems("amxmodmenu", count)
}

// The client menu: empty until items are added, then items for everyone, items that need
// access, items of a plugin that is not loaded, and a second page.
public test_client_menu()
{
	SpawnPuppets("fcli", 1, "Client_Spawned")
}

public Client_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "z")
	new count = CountItems(id, "amx_menu")
	if (count == 0)
	{
		bench_puppet_cmd(id, "amx_menu")
		ASSERT_MENU(id, "AMX Mod X Client Menu 1/0^n^n^n0. Exit")
		ASSERT_EQ(MenuKeys(id), MENU_KEY_0)
	}
	bench_set_timeout(60.0)

	server_cmd("amx_addclientmenuitem ^"Bench Short^" bench_short")
	server_exec()
	ASSERT_EQ(CountItems(id, "amx_menu"), count)

	new text[32]
	for (new i = 1; i <= 8; i++)
	{
		formatex(text, charsmax(text), "Bench Client %d", i)
		AddItem("amx_addclientmenuitem", text, "bench_client", "", "Menus Front-End")
	}
	AddItem("amx_addclientmenuitem", "KICK_PLAYER", "amx_kickmenu", "c", "plmenu.amxx")
	AddItem("amx_addclientmenuitem", "Bench Client Hidden", "bench_hidden", "", "No Such Plugin")
	ASSERT_EQ(CountItems(id, "amx_menu"), count + 10)

	// Items count + 8 and + 9: the language key, greyed without "c", and the missing plugin.
	new line[40]
	OpenPage(id, "amx_menu", (count + 8) / 8)
	formatex(line, charsmax(line), "^n#. Kick Player^n")
	ASSERT_MENU(id, line)
	OpenPage(id, "amx_menu", (count + 9) / 8)
	ASSERT_MENU(id, "^n#. Bench Client Hidden^n")

	// With "c" the language key item is enabled.
	SetFlags(id, "c")
	OpenPage(id, "amx_menu", (count + 8) / 8)
	formatex(line, charsmax(line), "^n%d. Kick Player^n", (count + 8) % 8 + 1)
	ASSERT_MENU(id, line)

	// First page: More, then Back from the second.
	bench_puppet_cmd(id, "amx_menu")
	ASSERT_MENU(id, "AMX Mod X Client Menu 1/")
	ASSERT_MENU(id, "^n9. More...^n0. Exit")
	bench_puppet_cmd(id, "menuselect 9")
	ASSERT_MENU(id, "AMX Mod X Client Menu 2/")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MENU(id, "AMX Mod X Client Menu 1/")

	// An item closes the menu and its command goes to the player with client_cmd.
	new before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 1")
	if (count == 0)
	{
		ASSERT_MSG(id, "stufftext", "bench_client")
	}
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before)
	ASSERT(MenuClosed(id))

	bench_puppet_cmd(id, "amx_menu")
	before = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), before)
	ClearItems("amx_menu", count)
}

// Both menus stop at 127 items: the 128th is refused (and logged).
public test_item_limit()
{
	SpawnPuppets("flimit", 1, "Limit_Spawned")
}

public Limit_Spawned()
{
	new id = g_P[0]
	SetFlags(id, "abcdefghijklmnopqrstuv")
	new count = CountItems(id, "amxmodmenu")
	bench_set_timeout(60.0)
	for (new i = count; i < MAXITEMS + 2; i++)
		AddItem("amx_addmenuitem", "Bench Filler", "bench_filler", "", "Menus Front-End")
	ASSERT_EQ(CountItems(id, "amxmodmenu"), MAXITEMS)
	ASSERT_MENU(id, "AMX Mod X Menu 16/16^n")

	new clientCount = CountItems(id, "amx_menu")
	for (new i = clientCount; i < MAXITEMS + 2; i++)
		AddItem("amx_addclientmenuitem", "Bench Filler", "bench_filler", "", "Menus Front-End")
	ASSERT_EQ(CountItems(id, "amx_menu"), MAXITEMS)
	ASSERT_MENU(id, "AMX Mod X Client Menu 16/16^n")
	ClearItems("amxmodmenu", count)
}
