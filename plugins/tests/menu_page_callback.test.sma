#include <amxmodx>
#include <amxxbench>

// Port of plugins/testsuite/menu_page_callback_test.sma. A puppet opens the menu and pages through
// it with the page callback on and then off. The original's commands are "say testmenu" and
// "say togglecallback"; a chat plugin that handles "say" first (the test server's roleplay mod
// does) swallows them, so they are also registered as the console commands the puppet uses.
//
// The menu has 8 items, 2 per page: page 1 enables 1, 2, More (4) and Exit (5); a middle page
// also Back (3) (amxmodx/newmenus.cpp, Menu::GetTextString).

new g_menuHandle;
new bool:g_isCallbackSet = false;

public plugin_init()
{
	register_plugin("Menu Pagination Callback Test", "1.0.0", "KliPPy");

	register_clcmd("say testmenu", "@Command_TestMenu");
	register_clcmd("say togglecallback", "@Command_ToggleCallback");
	register_clcmd("testmenu", "@Command_TestMenu");
	register_clcmd("togglecallback", "@Command_ToggleCallback");

	g_menuHandle = menu_create("Test menu", "@MenuHandler_TestMenu");
	menu_additem(g_menuHandle, "Item 1");
	menu_additem(g_menuHandle, "Item 2");
	menu_additem(g_menuHandle, "Item 3");
	menu_additem(g_menuHandle, "Item 4");
	menu_additem(g_menuHandle, "Item 5");
	menu_additem(g_menuHandle, "Item 6");
	menu_additem(g_menuHandle, "Item 7");
	menu_additem(g_menuHandle, "item 8");

	menu_setprop(g_menuHandle, MPROP_PERPAGE, 2);
}

public plugin_end()
{
	menu_destroy(g_menuHandle);
}

public bench_teardown()
{
	if (g_isCallbackSet)
	{
		menu_setprop(g_menuHandle, MPROP_PAGE_CALLBACK, NULL_STRING);
		g_isCallbackSet = false;
	}
}

@MenuHandler_TestMenu(id, menu, item)
{
	if(item == MENU_EXIT)
		return PLUGIN_HANDLED;

	new dump1, dump2[1], dump3;
	new itemName[32];
	menu_item_getinfo(menu, item, dump1, dump2, 0, itemName, charsmax(itemName), dump3);

	client_print(id, print_chat, "Selected: %s", itemName);

	return PLUGIN_HANDLED;
}

@PageCallback_TestMenu(id, status)
{
	if(status == MENU_BACK)
		client_print(id, print_chat, "Selected: MENU_BACK");
	else
		client_print(id, print_chat, "Selected: MENU_MORE");
}

@Command_TestMenu(id)
{
	menu_display(id, g_menuHandle);

	return PLUGIN_HANDLED;
}

@Command_ToggleCallback(id)
{
	if(g_isCallbackSet)
	{
		menu_setprop(g_menuHandle, MPROP_PAGE_CALLBACK, NULL_STRING);
		g_isCallbackSet = false;

		client_print(id, print_chat, "Callback set to OFF");
	}
	else
	{
		menu_setprop(g_menuHandle, MPROP_PAGE_CALLBACK, "@PageCallback_TestMenu");
		g_isCallbackSet = true;

		client_print(id, print_chat, "Callback set to ON");
	}
}

// The keys the newest ShowMenu message sent to id enables (bit n = key n+1).
MenuKeys(id)
{
	new BenchMsg:msg = bench_msg_last(id, "ShowMenu");
	if (msg == BenchMsg:0)
		return -1;
	return bench_msg_int(msg, 0);
}

MenuPage(id)
{
	new oldmenu, newmenu, page;
	player_menu_info(id, oldmenu, newmenu, page);
	return page;
}

public test_page_callback()
{
	ASSERT(bench_msg_available());
	new id = bench_puppet("pager");
	ASSERT(id > 0);
	bench_puppet_spawn(id, "Pager_Spawned", 20.0, "respawn");
}

public Pager_Spawned(id)
{
	// callback on: More and Back are reported to the callback
	bench_puppet_cmd(id, "togglecallback");
	ASSERT_MSG(id, "", "Callback set to ON");

	bench_puppet_cmd(id, "testmenu");
	ASSERT_EQ(bench_menu_open(id), g_menuHandle);
	ASSERT_EQ(MenuKeys(id), 0x1B);

	bench_puppet_cmd(id, "menuselect 4");
	ASSERT_MSG(id, "", "Selected: MENU_MORE");
	ASSERT_EQ(MenuPage(id), 1);
	ASSERT_EQ(MenuKeys(id), 0x1F);

	bench_puppet_cmd(id, "menuselect 3");
	ASSERT_MSG(id, "", "Selected: MENU_BACK");
	ASSERT_EQ(MenuPage(id), 0);
	ASSERT_EQ(MenuKeys(id), 0x1B);

	bench_puppet_cmd(id, "menuselect 1");
	ASSERT_MSG(id, "", "Selected: Item 1");
	ASSERT_EQ(bench_menu_open(id), -1);

	// callback off: paging still works, and nothing more is reported
	bench_puppet_cmd(id, "togglecallback");
	ASSERT_MSG(id, "", "Callback set to OFF");

	bench_puppet_cmd(id, "testmenu");
	ASSERT_EQ(bench_menu_open(id), g_menuHandle);
	bench_puppet_cmd(id, "menuselect 4");
	ASSERT_EQ(MenuPage(id), 1);
	bench_puppet_cmd(id, "menuselect 3");
	ASSERT_EQ(MenuPage(id), 0);

	new more = bench_msg_count(id, "", "Selected: MENU_MORE");
	new back = bench_msg_count(id, "", "Selected: MENU_BACK");
	ASSERT_EQ(more, 1);
	ASSERT_EQ(back, 1);

	bench_puppet_cmd(id, "menuselect 5");
	ASSERT_EQ(bench_menu_open(id), -1);
	bench_pass();
}
