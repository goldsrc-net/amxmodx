// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for timeleft.sma (TimeLeft): "say thetime", "say timeleft", the amx_timeleft cvar and the
// countdown amx_time_display sets up. The countdown test brings the end of the map to two minutes
// away and puts mp_timelimit back before it comes. After each test mp_timelimit, amx_time_voice
// and the server's amx_time_display line from amxx.cfg are restored.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#define TASK_TIMEREMAIN_SHORT 8648458
#define TASK_TIMEREMAIN_LARGE 34543

new g_Puppet
new Float:g_TimeLimit
new g_TimeVoice
new g_Wanted[64]
new Float:g_FloodTime

public plugin_init()
{
	register_plugin("TimeLeft Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_setup()
{
	g_TimeLimit = get_cvar_float("mp_timelimit")
	g_TimeVoice = get_cvar_num("amx_time_voice")
	// Anti Flood would answer the second "say" in a row instead of this plugin.
	g_FloodTime = get_cvar_float("amx_flood_time")
	set_cvar_float("amx_flood_time", 0.0)
	g_Puppet = 0
}

public bench_teardown()
{
	set_cvar_float("mp_timelimit", g_TimeLimit)
	set_cvar_num("amx_time_voice", g_TimeVoice)
	set_cvar_float("amx_flood_time", g_FloodTime)
	RerunConfig("amx_time_display")
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

bool:StartPuppet(const name[])
{
	g_Puppet = bench_puppet(name)
	return bench_check(g_Puppet > 0, "puppet created")
}

public test_say_thetime_prints_the_date_and_time()
{
	if (!StartPuppet("clockwatcher"))
		return
	set_cvar_num("amx_time_voice", 1)
	bench_puppet_say(g_Puppet, "thetime")

	new expected[64]
	get_time("The time:   %m/%d/%Y - ", expected, charsmax(expected))
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	bench_pass()
}

public test_say_thetime_without_voice()
{
	if (!StartPuppet("quietclock"))
		return
	set_cvar_num("amx_time_voice", 0)
	bench_puppet_say(g_Puppet, "thetime")
	ASSERT_MSG(g_Puppet, "TextMsg", "The time:")
	bench_pass()
}

public test_say_timeleft()
{
	if (!StartPuppet("timeasker"))
		return
	set_cvar_num("amx_time_voice", 1)
	bench_puppet_say(g_Puppet, "timeleft")

	new left = get_timeleft(), expected[64]
	formatex(expected, charsmax(expected), "Time Left:  %d:%02d", left / 60, left % 60)
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	bench_pass()
}

public test_say_timeleft_over_an_hour()
{
	if (!StartPuppet("longmap"))
		return
	// Over an hour left: the voice says hours too.
	set_cvar_float("mp_timelimit", 150.0)
	set_cvar_num("amx_time_voice", 1)
	bench_puppet_say(g_Puppet, "timeleft")

	new left = get_timeleft(), expected[64]
	ASSERT(left > 3600)
	formatex(expected, charsmax(expected), "Time Left:  %d:%02d", left / 60, left % 60)
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	bench_pass()
}

public test_say_timeleft_without_voice()
{
	if (!StartPuppet("quietleft"))
		return
	set_cvar_num("amx_time_voice", 0)
	bench_puppet_say(g_Puppet, "timeleft")
	ASSERT_MSG(g_Puppet, "TextMsg", "Time Left:  ")
	bench_pass()
}

public test_say_timeleft_without_time_limit()
{
	if (!StartPuppet("nolimit"))
		return
	set_cvar_float("mp_timelimit", 0.0)
	bench_puppet_say(g_Puppet, "timeleft")
	ASSERT_MSG(g_Puppet, "TextMsg", "No Time Limit")
	bench_pass()
}

public test_amx_timeleft_follows_the_clock()
{
	// The cvar is refreshed every 0.8 seconds.
	bench_next("timeleft_cvar", 1.0)
}

public timeleft_cvar()
{
	new left = get_timeleft(), value[16], expected[16]
	get_cvar_string("amx_timeleft", value, charsmax(value))
	// Up to a second may have passed since the last refresh.
	formatex(expected, charsmax(expected), "%02d:%02d", left / 60, left % 60)
	if (!equal(value, expected))
	{
		left++
		formatex(expected, charsmax(expected), "%02d:%02d", left / 60, left % 60)
	}
	ASSERT_STR_EQ(value, expected)
	bench_pass()
}

// The countdown. amx_time_display entries are "<flags> <seconds>": a = white text, b = voice,
// c = no "remaining", d = no "hours/minutes/seconds", e = every second below the time given.
// Each test brings the end of the map close and puts mp_timelimit back before it comes.
public test_time_display_whole_minutes()
{
	if (!StartPuppet("minutes"))
		return
	server_cmd("amx_time_display ^"ab 120^"")
	server_exec()
	set_cvar_float("mp_timelimit", (get_gametime() + 124.5) / 60.0)
	WaitHud("2 minutes", "two_minutes")
}

public two_minutes()
{
	set_cvar_float("mp_timelimit", g_TimeLimit)
	bench_pass()
}

public test_time_display_counts_down()
{
	if (!StartPuppet("countdown"))
		return
	server_cmd("amx_time_display ^"a 61^" ^"bcd 60^" ^"a 59^" ^"ae 55^"")
	server_exec()
	set_cvar_float("mp_timelimit", (get_gametime() + 63.5) / 60.0)
	WaitHud("1 minute 1 second", "one_minute_one_second")
}

WaitHud(const text[], const step[])
{
	copy(g_Wanted, charsmax(g_Wanted), text)
	bench_wait_until("hud_shown", step, 10.0)
}

public hud_shown()
{
	return HudSent(g_Puppet, g_Wanted)
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

public one_minute_one_second()
{
	WaitHud("59 seconds", "fifty_nine")
}

public fifty_nine()
{
	// "bcd 60" speaks only, so 60 was never shown.
	ASSERT_FALSE(HudSent(g_Puppet, "1 minute"))
	// Below 55 seconds it counts every second, on a one second task.
	WaitHud("54 seconds", "counting")
}

public counting()
{
	ASSERT(task_exists(TASK_TIMEREMAIN_LARGE, 1))
	ASSERT_FALSE(task_exists(TASK_TIMEREMAIN_SHORT, 1))
	WaitHud("53 seconds", "counting_on")
}

public counting_on()
{
	// More time again: the countdown stops and the 0.8 second task comes back.
	set_cvar_float("mp_timelimit", g_TimeLimit)
	bench_wait_until("short_task_back", "countdown_stopped", 5.0)
}

public short_task_back()
{
	return task_exists(TASK_TIMEREMAIN_SHORT, 1)
}

public countdown_stopped()
{
	ASSERT_FALSE(task_exists(TASK_TIMEREMAIN_LARGE, 1))
	bench_pass()
}
