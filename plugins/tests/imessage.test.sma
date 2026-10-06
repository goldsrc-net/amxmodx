// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for imessage.sma (Info. Messages): the messages amxx.cfg adds with amx_imessage are shown
// in turn on every HUD and console, in their own colours, every amx_freq_imessage seconds. The
// plugin has no command to remove a message, so the tests use the two amxx.cfg adds and leave the
// list as it is.
//

#include <amxmodx>
#include <amxxbench>

#define TASK_INFO 12345

new g_Puppet
new Float:g_Freq
new g_Welcome[128]
new g_Visit[] = "This server is using AMX Mod X^nVisit http://www.amxmodx.org"
new g_First[128]
new g_Second[128]

public plugin_init()
{
	register_plugin("Info. Messages Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("imessage.sma", 52, 52, "infoMessage only runs from the task setMessage starts after adding a message, and nothing removes one, so the list is never empty there")
}

public bench_setup()
{
	g_Freq = get_cvar_float("amx_freq_imessage")
}

public bench_teardown()
{
	set_cvar_float("amx_freq_imessage", g_Freq)
}

public test_messages_rotate_with_their_colours()
{
	new hostname[64]
	get_cvar_string("hostname", hostname, charsmax(hostname))
	formatex(g_Welcome, charsmax(g_Welcome), "Welcome to %s", hostname)

	g_Puppet = bench_puppet("inforeader")
	ASSERT(g_Puppet > 0)
	// Every half second from now: the waiting task (up to 180 seconds away) is brought forward.
	set_cvar_float("amx_freq_imessage", 0.5)
	ASSERT_EQ(change_task(TASK_INFO, 0.5, 1), 1)
	bench_wait_until("any_message", "first_shown", 2.0)
}

public any_message()
{
	return bench_msg_last(g_Puppet, "TextMsg", g_Welcome) != BenchMsg:0
		|| bench_msg_last(g_Puppet, "TextMsg", g_Visit) != BenchMsg:0
}

public first_shown()
{
	if (bench_msg_last(g_Puppet, "TextMsg", g_Welcome) != BenchMsg:0)
	{
		copy(g_First, charsmax(g_First), g_Welcome)
		copy(g_Second, charsmax(g_Second), g_Visit)
	}
	else
	{
		copy(g_First, charsmax(g_First), g_Visit)
		copy(g_Second, charsmax(g_Second), g_Welcome)
	}
	bench_wait_until("second_message", "second_shown", 2.0)
}

public second_message()
{
	return bench_msg_last(g_Puppet, "TextMsg", g_Second) != BenchMsg:0
}

public second_shown()
{
	// Back to the first one: the list wraps around.
	bench_wait_until("first_again", "check_hud", 2.0)
}

public first_again()
{
	return bench_msg_count(g_Puppet, "TextMsg", g_First) >= 2
}

public check_hud()
{
	// "%hostname%" is replaced and "\n" becomes a line break; each message has its colour,
	// "000255100" and "000100255" in amxx.cfg.
	ASSERT(CheckHud(g_Welcome, 0, 255, 100))
	ASSERT(CheckHud(g_Visit, 0, 100, 255))
	bench_pass()
}

bool:CheckHud(const text[], r, g, b)
{
	new BenchMsg:msg = bench_msg_last(g_Puppet, "svc_temp_entity", text)
	if (!bench_check(msg != BenchMsg:0, "HUD message shown"))
		return false
	new got[256]
	bench_msg_string(msg, bench_msg_args(msg) - 1, got, charsmax(got))
	if (!bench_check(bool:equal(got, text), "HUD text"))
		return false
	// TE_TEXTMESSAGE: type, channel, x, y, effect, then r, g, b of the text.
	return bench_check(bench_msg_int(msg, 5) == r && bench_msg_int(msg, 6) == g && bench_msg_int(msg, 7) == b, "HUD colour")
}
