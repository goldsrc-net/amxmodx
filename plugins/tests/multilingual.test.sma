// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for multilingual.sma (Multi-Lingual System): the hint shown after joining, and the
// amx_langmenu menu a player answers to pick and save a personal language.
// amx_client_languages and amx_language_display_msg are put back after each test.
//

#include <amxmodx>
#include <amxxbench>

new g_Puppet
new g_ClientLanguages
new g_DisplayMsg

public plugin_init()
{
	register_plugin("Multi-Lingual System Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_dictionary("multilingual.txt")
	register_dictionary("languages.txt")

	bench_coverage_ignore("multilingual.sma", 88, 88, "both callers of showMenu return first when amx_client_languages is 0")
}

public bench_setup()
{
	g_ClientLanguages = get_cvar_num("amx_client_languages")
	g_DisplayMsg = get_cvar_num("amx_language_display_msg")
	set_cvar_num("amx_client_languages", 1)
	set_cvar_num("amx_language_display_msg", 1)
	g_Puppet = 0
}

public bench_teardown()
{
	set_cvar_num("amx_client_languages", g_ClientLanguages)
	set_cvar_num("amx_language_display_msg", g_DisplayMsg)
}

bool:StartPuppet(const name[])
{
	g_Puppet = bench_puppet(name)
	return bench_check(g_Puppet > 0, "puppet created")
}

// The text of the newest menu sent to the puppet (the Language Menu fits in one message).
MenuText(text[], len)
{
	text[0] = EOS
	new BenchMsg:msg = bench_msg_last(g_Puppet, "ShowMenu")
	if (msg != BenchMsg:0)
		bench_msg_text(msg, text, len)
}

// The menu is in the player's language (player), the language it offers in its own (index).
bool:MenuShowsLanguage(index, const player[] = "en")
{
	new code[3], name[64], label[64], text[512]
	get_lang(index, code)
	formatex(name, charsmax(name), "%L", code, "LANG_NAME")
	formatex(label, charsmax(label), "%L", player, "PERSO_LANG")
	MenuText(text, charsmax(text))
	if (contain(text, label) == -1 || contain(text, name) == -1)
	{
		bench_fail("menu ^"%s^" does not offer ^"%s %s^"", text, label, name)
		return false
	}
	return true
}

LangIndex(const code[])
{
	new other[3]
	for (new i = 0; i < get_langsnum(); i++)
	{
		get_lang(i, other)
		if (equali(other, code))
			return i
	}
	return -1
}

public test_hint_after_joining()
{
	if (!StartPuppet("newcomer"))
		return
	// Ten seconds after joining.
	bench_wait_message(g_Puppet, "TextMsg", "Type 'amx_langmenu' in the console", "hint_shown", 12.0)
}

public hint_shown()
{
	bench_pass()
}

public test_menu_disabled()
{
	if (!StartPuppet("nomenu"))
		return
	set_cvar_num("amx_client_languages", 0)
	bench_puppet_cmd(g_Puppet, "amx_langmenu")
	ASSERT_MSG(g_Puppet, "TextMsg", "[AMXX] Language menu disabled.")
	ASSERT_EQ(bench_msg_count(g_Puppet, "ShowMenu", "Language Menu"), 0)
	bench_pass()
}

public test_menu_starts_at_the_server_language()
{
	if (!StartPuppet("serverlang"))
		return
	new server[3]
	get_cvar_string("amx_language", server, charsmax(server))
	bench_puppet_cmd(g_Puppet, "amx_langmenu")
	ASSERT(MenuShowsLanguage(LangIndex(server)))
	bench_pass()
}

public test_pick_and_save_the_next_language()
{
	if (!StartPuppet("polyglot"))
		return
	bench_puppet_setinfo(g_Puppet, "lang", "en")
	bench_puppet_cmd(g_Puppet, "amx_langmenu")
	new index = LangIndex("en")
	ASSERT(MenuShowsLanguage(index))

	// 1 shows the next language.
	bench_puppet_cmd(g_Puppet, "menuselect 1")
	ASSERT(MenuShowsLanguage(index + 1))

	// 2 saves it, and the reply comes in that language.
	new code[3], name[64], expected[128], lang[8]
	get_lang(index + 1, code)
	formatex(name, charsmax(name), "%L", code, "LANG_NAME")
	formatex(expected, charsmax(expected), "%L", code, "SET_LANG_USER", name)
	bench_puppet_cmd(g_Puppet, "menuselect 2")
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	get_user_info(g_Puppet, "lang", lang, charsmax(lang))
	ASSERT_STR_EQ(lang, code)
	bench_pass()
}

public test_last_language_wraps_to_the_first()
{
	if (!StartPuppet("wrapper"))
		return
	new last[3]
	get_lang(get_langsnum() - 1, last)
	bench_puppet_setinfo(g_Puppet, "lang", last)
	bench_puppet_cmd(g_Puppet, "amx_langmenu")
	ASSERT(MenuShowsLanguage(get_langsnum() - 1, last))
	bench_puppet_cmd(g_Puppet, "menuselect 1")
	ASSERT(MenuShowsLanguage(0, last))
	bench_pass()
}

public test_saving_the_same_language_says_nothing()
{
	if (!StartPuppet("samelang"))
		return
	bench_puppet_setinfo(g_Puppet, "lang", "en")
	bench_puppet_cmd(g_Puppet, "amx_langmenu")
	bench_puppet_cmd(g_Puppet, "menuselect 2")
	ASSERT_EQ(bench_msg_count(g_Puppet, "TextMsg", "Your language has been set"), 0)
	bench_pass()
}

public test_unknown_language_starts_at_the_first()
{
	if (!StartPuppet("unknownlang"))
		return
	bench_puppet_setinfo(g_Puppet, "lang", "zz")
	bench_puppet_cmd(g_Puppet, "amx_langmenu")
	// An unknown language reads in the server's.
	new server[3]
	get_cvar_string("amx_language", server, charsmax(server))
	ASSERT(MenuShowsLanguage(0, server))
	bench_pass()
}

public test_answer_ignored_once_disabled()
{
	if (!StartPuppet("latecomer"))
		return
	bench_puppet_cmd(g_Puppet, "amx_langmenu")
	ASSERT_EQ(bench_msg_count(g_Puppet, "ShowMenu", "Language Menu"), 1)
	set_cvar_num("amx_client_languages", 0)
	bench_puppet_cmd(g_Puppet, "menuselect 1")
	// No new menu.
	ASSERT_EQ(bench_msg_count(g_Puppet, "ShowMenu", "Language Menu"), 1)
	bench_pass()
}
