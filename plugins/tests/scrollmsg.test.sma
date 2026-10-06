// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for scrollmsg.sma (Scrolling Message): amx_scrollmsg sets the message and how often it
// runs, raised to the time one scroll takes; each run prints it to every console and scrolls it
// across the HUD. After each test the server's own amx_scrollmsg line from amxx.cfg is run again.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#define TASK_SCROLL 123

new g_Puppet
new Float:g_Started
new g_Expected[128]

public plugin_init()
{
	register_plugin("Scrolling Message Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_teardown()
{
	RerunConfig("amx_scrollmsg")
}

// Runs the lines of amxx.cfg that start with command.
RerunConfig(const command[])
{
	new path[PLATFORM_MAX_PATH], line[512], first[64]
	get_configsdir(path, charsmax(path))
	add(path, charsmax(path), "/amxx.cfg")
	new f = fopen(path, "rt")
	if (!f)
		return
	while (fgets(f, line, charsmax(line)))
	{
		trim(line)
		parse(line, first, charsmax(first))
		if (equal(first, command))
			server_cmd("%s", line)
	}
	fclose(f)
	server_exec()
}

// Whether a HUD message whose text is exactly text was sent to id this test.
bool:HudSent(id, const text[])
{
	new BenchMsg:msg = BenchMsg:0, got[256]
	while ((msg = bench_msg_next(id, msg, "svc_temp_entity", text)) != BenchMsg:0)
	{
		bench_msg_string(msg, bench_msg_args(msg) - 1, got, charsmax(got))
		if (equal(got, text))
			return true
	}
	return false
}

public test_short_frequency_is_raised_to_one_scroll()
{
	g_Puppet = bench_puppet("scrollreader")
	ASSERT(g_Puppet > 0)

	new hostname[64]
	get_cvar_string("hostname", hostname, charsmax(hostname))
	formatex(g_Expected, charsmax(g_Expected), "Hi %s", hostname)

	// "Hi %hostname%" is 13 characters: one scroll takes (13 + 48) * 0.4 = 24 seconds, so the
	// 5 seconds asked for become 24.
	server_cmd("amx_scrollmsg ^"Hi %%hostname%%^" 5")
	server_exec()
	g_Started = get_gametime()
	ASSERT(task_exists(TASK_SCROLL, 1))
	bench_wait_until("message_printed", "scroll_started", 30.0)
}

public message_printed()
{
	return bench_msg_last(g_Puppet, "TextMsg", g_Expected) != BenchMsg:0
}

public scroll_started()
{
	new Float:elapsed = get_gametime() - g_Started
	if (!bench_check(elapsed > 23.0 && elapsed < 25.5, "first run after 24 seconds"))
		return
	// The HUD shows a growing window of the message, with the host name in it.
	bench_wait_until("whole_message_shown", "window_moves", 10.0)
}

public whole_message_shown()
{
	return HudSent(g_Puppet, g_Expected)
}

public window_moves()
{
	// Once the text reaches the middle of the screen the window starts dropping letters.
	bench_wait_until("first_letter_dropped", "dropped", 20.0)
}

public first_letter_dropped()
{
	return HudSent(g_Puppet, g_Expected[1])
}

public dropped()
{
	ASSERT(HudSent(g_Puppet, "H"))
	ASSERT(HudSent(g_Puppet, "Hi"))
	bench_pass()
}

public test_zero_frequency_disables_the_message()
{
	server_cmd("amx_scrollmsg ^"Nothing to see^" 0")
	server_exec()
	ASSERT_FALSE(task_exists(TASK_SCROLL, 1))
	bench_pass()
}

public test_long_frequency_is_kept()
{
	server_cmd("amx_scrollmsg ^"Kept^" 0")
	server_exec()
	ASSERT_FALSE(task_exists(TASK_SCROLL, 1))
	server_cmd("amx_scrollmsg ^"Kept^" 100")
	server_exec()
	ASSERT(task_exists(TASK_SCROLL, 1))
	bench_pass()
}
