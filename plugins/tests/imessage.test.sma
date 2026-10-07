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
// list as it is. Where the rotation stands is kept across a map change.
//

#include <amxmodx>
#include <amxxbench>

#define TASK_INFO 12345

new g_Puppet
new Float:g_Freq
new bool:g_SetupRan
new BenchMsg:g_Base
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
	g_SetupRan = true
}

public bench_teardown()
{
	// After a map change amxx.cfg has set it again, and g_Freq is gone.
	if (g_SetupRan)
		set_cvar_float("amx_freq_imessage", g_Freq)
}

SetMessages()
{
	new hostname[64]
	get_cvar_string("hostname", hostname, charsmax(hostname))
	formatex(g_Welcome, charsmax(g_Welcome), "Welcome to %s", hostname)
}

public test_messages_rotate_with_their_colours()
{
	SetMessages()

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

// At map end the plugin saves which message comes next (localinfo "lastinfomsg") and starts there
// on the next map. Stopped right after the first message, the next map begins with the second.
public test_rotation_goes_on_after_a_map_change()
{
	SetMessages()
	g_Puppet = bench_puppet("mapreader")
	ASSERT(g_Puppet > 0)
	set_cvar_float("amx_freq_imessage", 0.5)
	ASSERT_EQ(change_task(TASK_INFO, 0.5, 1), 1)
	bench_wait_until("welcome_shown", "stop_and_change", 3.0)
}

public welcome_shown()
{
	return bench_msg_last(g_Puppet, "TextMsg", g_Welcome) != BenchMsg:0
}

public stop_and_change()
{
	// No other message before the map changes, nor while the next one loads: amxx.cfg adds the
	// messages there before it sets amx_freq_imessage, so their task takes the value left here.
	ASSERT_EQ(change_task(TASK_INFO, 100000.0, 1), 1)
	set_cvar_float("amx_freq_imessage", g_Freq)
	bench_change_map("", "new_map")
}

public new_map()
{
	SetMessages()
	g_Freq = get_cvar_float("amx_freq_imessage")
	g_SetupRan = true
	g_Puppet = bench_puppet("newmapreader")
	ASSERT(g_Puppet > 0)
	// What was sent before the map change is still in this test's record, the old puppet's
	// messages under the same player index: only what comes after this counts.
	g_Base = bench_msg_last(g_Puppet)
	// amxx.cfg has added both messages again, and their task waits amx_freq_imessage seconds.
	set_cvar_float("amx_freq_imessage", 0.5)
	ASSERT_EQ(change_task(TASK_INFO, 0.5, 1), 1)
	bench_wait_until("new_map_message", "first_on_new_map", 3.0)
}

public new_map_message()
{
	return bench_msg_next(g_Puppet, g_Base, "TextMsg", g_Welcome) != BenchMsg:0
		|| bench_msg_next(g_Puppet, g_Base, "TextMsg", g_Visit) != BenchMsg:0
}

public first_on_new_map()
{
	ASSERT(bench_msg_next(g_Puppet, g_Base, "TextMsg", g_Visit) != BenchMsg:0)
	ASSERT(bench_msg_next(g_Puppet, g_Base, "TextMsg", g_Welcome) == BenchMsg:0)
	// The saved position is read once, at load.
	new lastinfo[8]
	get_localinfo("lastinfomsg", lastinfo, charsmax(lastinfo))
	ASSERT_STR_EQ(lastinfo, "")
	bench_pass()
}
