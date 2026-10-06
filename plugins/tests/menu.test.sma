// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/menutest.sma. A puppet opens each menu with the original command and
// answers it with menuselect, the way a player does. The keys each page enables (the ShowMenu
// message's slot bits) and the item each key selects are derived from amxmodx/newmenus.cpp
// (Menu::GetTextString and Menu::PagekeyToItem).
//

#include <amxmodx>
#include <amxxbench>

public plugin_init()
{
	register_plugin("Menu Tests", "1.0", "BAILOPAN")

	register_clcmd("menu_test1", "Test_Menu1")
	register_clcmd("menu_test2", "Test_Menu2")
	register_clcmd("menu_test3", "Test_Menu3")
	register_clcmd("menu_test4", "Test_Menu4")
	register_clcmd("menu_test5", "Test_Menu5")
}

public Test_Menu1(id, level, cid)
{
	new menu = menu_create("Character Upgrade:", "Test_Menu1_Handler")
	menu_additem(menu, "Gabezilla 1", "1", 0)
	menu_additem(menu, "Gabezilla 2", "2", 0)
	menu_additem(menu, "Gabezilla 3", "3", 0)
	menu_additem(menu, "Gabezilla 4", "4", 0)
	menu_additem(menu, "Gabezilla 5", "5", 0)
	menu_additem(menu, "Gabezilla 6", "6", 0)
	menu_addblank(menu, 7)
	menu_additem(menu, "Gabezilla 7", "7", 0)
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)
	menu_display(id, menu, 0)
	return PLUGIN_HANDLED
}

public Test_Menu2(id, level, cid)
{
	new menu = menu_create("Character Upgrade:", "Test_Menu1_Handler")
	menu_additem(menu, "Gabezilla 1", "1", 0)
	menu_additem(menu, "Gabezilla 2", "2", 0)
	menu_additem(menu, "Gabezilla 3", "3", 0)
	menu_additem(menu, "Gabezilla 4", "4", 0)
	menu_additem(menu, "Gabezilla 5", "5", 0)
	menu_additem(menu, "Gabezilla 6", "6", 0)
	menu_display(id, menu, 0)
	return PLUGIN_HANDLED
}

public Test_Menu1_Handler(id, menu, item)
{
	client_print(id, print_chat, "Menu (%d->%d): Chose %d", menu, id, item)
	if (item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	new cmd[32], name[32], access

	menu_item_getinfo(menu, item, access, cmd, 31, name, 31, access)

	client_print(id, print_chat, "Menu resolved to: %s (%s)", name, cmd)

	menu_destroy(menu)

	return PLUGIN_HANDLED
}

public Test_Menu3(id)
{
   new mHandleID = menu_create("Test Menu 3", "Test_Menu3_Handler")
   menu_additem(mHandleID, "test1", "1", 0)
   menu_additem(mHandleID, "test2", "2", 0)
   menu_additem(mHandleID, "test3", "3", 0)
   menu_additem(mHandleID, "test4", "4", 0)
   menu_additem(mHandleID, "test5", "5", 0)
   menu_additem(mHandleID, "test6", "6", 0)
   menu_additem(mHandleID, "test7", "7", 0)
   menu_additem(mHandleID, "test8", "8", 0)
   menu_additem(mHandleID, "test9", "9", 0)
   menu_additem(mHandleID, "test10", "10", 0)
   menu_additem(mHandleID, "test11", "11", 0)
   menu_addblank(mHandleID, 1)  // add blank got problem
   menu_setprop(mHandleID, MPROP_PERPAGE, 5)

   menu_display(id, mHandleID, 0)

   return PLUGIN_HANDLED
}

public Test_Menu3_Handler(id, menu, item)
{
   if (item == MENU_EXIT)
   {
	   menu_destroy(menu)
	   return PLUGIN_HANDLED
   }

   client_print(id, print_chat, "item = %d", item)

   menu_destroy(menu)

   return PLUGIN_HANDLED
}

public Test_Menu4(id)
{
   new mHandleID = menu_create("Test Menu 4", "Test_Menu4_Handler")
   menu_setprop(mHandleID, MPROP_PERPAGE, 0)
   menu_additem(mHandleID, "test1", "1", 0)
   menu_additem(mHandleID, "test2", "2", 0)
   menu_additem(mHandleID, "test3", "3", 0)
   menu_additem(mHandleID, "test4", "4", 0)
   menu_additem(mHandleID, "test5", "5", 0)
   menu_additem(mHandleID, "test6", "6", 0)
   menu_additem(mHandleID, "test7", "7", 0)
   menu_additem(mHandleID, "test8", "8", 0)
   menu_additem(mHandleID, "test9", "9", 0)

   menu_display(id, mHandleID, 0)

   return PLUGIN_HANDLED
}

public Test_Menu4_Handler(id, menu, item)
{
   if (item == MENU_EXIT)
   {
	   menu_destroy(menu)
	   return PLUGIN_HANDLED
   }

   client_print(id, print_chat, "item = %d", item)

   menu_destroy(menu)

   return PLUGIN_HANDLED
}

public Test_Menu5(id)
{
   new mHandleID = menu_create("Test Menu 5", "Test_Menu5_Handler")
   menu_additem(mHandleID, "test1", "1", 0)
   menu_additem(mHandleID, "test2", "2", 0)
   menu_additem(mHandleID, "test3", "3", 0)
   menu_additem(mHandleID, "test4", "4", 0)
   menu_additem(mHandleID, "test5", "5", 0)
   menu_additem(mHandleID, "test6", "6", 0)
   menu_additem(mHandleID, "test7", "7", 0)
   menu_additem(mHandleID, "test8", "8", 0)
   menu_additem(mHandleID, "test9", "9", 0)
   menu_additem(mHandleID, "test10", "10", 0)
   menu_additem(mHandleID, "test11", "11", 0)
   menu_addblank(mHandleID, 1)  // add blank got problem
   menu_setprop(mHandleID, MPROP_EXIT, MEXIT_NEVER)

   menu_display(id, mHandleID, 0)

   return PLUGIN_HANDLED
}

public Test_Menu5_Handler(id, menu, item)
{
   if (item == MENU_EXIT)
   {
	   menu_destroy(menu)
	   return PLUGIN_HANDLED
   }

   client_print(id, print_chat, "item = %d", item)

   menu_destroy(menu)

   return PLUGIN_HANDLED
}

// ---------------------------------------------------------------------------------------------
// Tests

// The keys the newest ShowMenu message sent to id enables (bit n = key n+1, bit 9 = key 0).
MenuKeys(id)
{
	new BenchMsg:msg = bench_msg_last(id, "ShowMenu")
	if (msg == BenchMsg:0)
		return -1
	return bench_msg_int(msg, 0)
}

MenuPage(id)
{
	new oldmenu, newmenu, page
	player_menu_info(id, oldmenu, newmenu, page)
	return page
}

StartWithPuppet(const name[], const step[])
{
	if (!bench_check(bench_msg_available(), "message capture is available"))
		return
	new id = bench_puppet(name)
	if (!bench_check(id > 0, "puppet created"))
		return
	bench_puppet_spawn(id, step, 20.0, "respawn")
}

// Menu 1: a blank added with menu_addblank(menu, 7) after item 6 does not take a number (only
// slot=1 does), so "Gabezilla 7" is key 7; MEXIT_NEVER leaves no exit key.
public test_menu1_blank_and_no_exit()
{
	StartWithPuppet("menu1", "Menu1_Spawned")
}

public Menu1_Spawned(id)
{
	bench_puppet_cmd(id, "menu_test1")
	ASSERT(bench_menu_open(id) >= 0)
	ASSERT_EQ(MenuKeys(id), 0x7F)

	bench_puppet_cmd(id, "menuselect 7")
	ASSERT_MSG(id, "", "Chose 6")
	ASSERT_MSG(id, "", "Menu resolved to: Gabezilla 7 (7)")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

// Menu 2: six items on one page of seven, so the exit key is 0.
public test_menu2_item_and_exit()
{
	StartWithPuppet("menu2", "Menu2_Spawned")
}

public Menu2_Spawned(id)
{
	bench_puppet_cmd(id, "menu_test2")
	ASSERT(bench_menu_open(id) >= 0)
	ASSERT_EQ(MenuKeys(id), 0x23F)

	bench_puppet_cmd(id, "menuselect 3")
	ASSERT_MSG(id, "", "Chose 2")
	ASSERT_MSG(id, "", "Menu resolved to: Gabezilla 3 (3)")
	ASSERT_EQ(bench_menu_open(id), -1)

	bench_puppet_cmd(id, "menu_test2")
	ASSERT(bench_menu_open(id) >= 0)
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_MSG(id, "", "Chose -3")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

// Menu 3: eleven items, five per page, and a numbered blank after the last item. Page 1 has
// items 1-5, More (7) and Exit (8); page 2 adds Back (6); on page 3 key 1 is test11 (item 10).
public test_menu3_paged_blank()
{
	StartWithPuppet("menu3", "Menu3_Spawned")
}

public Menu3_Spawned(id)
{
	bench_puppet_cmd(id, "menu_test3")
	new menu = bench_menu_open(id)
	ASSERT(menu >= 0)
	ASSERT_EQ(MenuKeys(id), 0xDF)

	bench_puppet_cmd(id, "menuselect 7")
	ASSERT_EQ(bench_menu_open(id), menu)
	ASSERT_EQ(MenuPage(id), 1)
	ASSERT_EQ(MenuKeys(id), 0xFF)

	bench_puppet_cmd(id, "menuselect 7")
	ASSERT_EQ(bench_menu_open(id), menu)
	ASSERT_EQ(MenuPage(id), 2)
	ASSERT_EQ(MenuKeys(id), 0xA1)

	bench_puppet_cmd(id, "menuselect 1")
	ASSERT_MSG(id, "", "item = 10")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

// Menu 4: MPROP_PERPAGE 0 shows all nine items on one page, with no exit key.
public test_menu4_unpaginated()
{
	StartWithPuppet("menu4", "Menu4_Spawned")
}

public Menu4_Spawned(id)
{
	bench_puppet_cmd(id, "menu_test4")
	ASSERT(bench_menu_open(id) >= 0)
	ASSERT_EQ(MenuKeys(id), 0x1FF)

	bench_puppet_cmd(id, "menuselect 9")
	ASSERT_MSG(id, "", "item = 8")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}

// Menu 5: eleven items, seven per page, a numbered blank after the last item and MEXIT_NEVER.
// Page 1 has items 1-7 and More (9); page 2 has test8-test11 (1-4) and Back (8).
public test_menu5_paged_blank_no_exit()
{
	StartWithPuppet("menu5", "Menu5_Spawned")
}

public Menu5_Spawned(id)
{
	bench_puppet_cmd(id, "menu_test5")
	new menu = bench_menu_open(id)
	ASSERT(menu >= 0)
	ASSERT_EQ(MenuKeys(id), 0x17F)

	bench_puppet_cmd(id, "menuselect 9")
	ASSERT_EQ(bench_menu_open(id), menu)
	ASSERT_EQ(MenuPage(id), 1)
	ASSERT_EQ(MenuKeys(id), 0x8F)

	bench_puppet_cmd(id, "menuselect 4")
	ASSERT_MSG(id, "", "item = 10")
	ASSERT_EQ(bench_menu_open(id), -1)
	bench_pass()
}
