// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for antiflood.sma (Anti Flood): a fifth chat line inside amx_flood_time is refused with
// a warning, the count drops again with quiet chat, and amx_flood_time 0 turns the check off.
// The plugin keeps its counters per player slot, so the flood test talks the count back down to
// zero before it ends.
//

#include <amxmodx>
#include <amxxbench>

new Float:g_SavedFloodTime
new g_Puppet
new g_Drained

public plugin_init()
{
	register_plugin("Anti Flood Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_setup()
{
	g_SavedFloodTime = get_cvar_float("amx_flood_time")
	g_Puppet = 0
	g_Drained = 0
}

public bench_teardown()
{
	set_cvar_float("amx_flood_time", g_SavedFloodTime)
}

public test_fifth_line_is_refused()
{
	set_cvar_float("amx_flood_time", 0.75)
	g_Puppet = bench_puppet("chatty")
	ASSERT(g_Puppet > 0)
	bench_next("flood", 0.1)
}

public flood()
{
	// The first line starts the window, the next three raise the count to three, the fifth is
	// refused.
	for (new i = 1; i <= 4; i++)
		bench_puppet_say(g_Puppet, fmt("floodline%d", i))
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Stop flooding the server!"), 0)
	bench_puppet_say(g_Puppet, "floodline5")
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Stop flooding the server!"), 1)
	// The refusal holds the player off for amx_flood_time + 3 seconds: two seconds on, a line is
	// still refused.
	bench_next("still_held", 2.0)
}

public still_held()
{
	bench_puppet_say(g_Puppet, "floodline6")
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Stop flooding the server!"), 2)
	bench_next("drain", 4.0)
}

public drain()
{
	// Each line said after the window has closed takes one off the count.
	bench_puppet_say(g_Puppet, "quiet")
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Stop flooding the server!"), 2)
	if (++g_Drained < 3)
	{
		bench_next("drain", 1.0)
		return
	}
	bench_next("drained", 1.0)
}

public drained()
{
	// Back at zero: four quick lines pass again.
	for (new i = 1; i <= 4; i++)
		bench_puppet_say(g_Puppet, fmt("again%d", i))
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Stop flooding the server!"), 2)
	// Leave the slot at zero for whoever uses it next.
	g_Drained = 0
	bench_next("drain_again", 4.0)
}

public drain_again()
{
	bench_puppet_say(g_Puppet, "quiet")
	if (++g_Drained < 3)
	{
		bench_next("drain_again", 1.0)
		return
	}
	bench_pass()
}

public test_zero_flood_time_allows_everything()
{
	set_cvar_float("amx_flood_time", 0.0)
	g_Puppet = bench_puppet("unlimited")
	ASSERT(g_Puppet > 0)
	bench_next("say_a_lot", 0.1)
}

public say_a_lot()
{
	for (new i = 1; i <= 8; i++)
		bench_puppet_say(g_Puppet, fmt("line%d", i))
	ASSERT_EQ(bench_msg_count(g_Puppet, "", "Stop flooding the server!"), 0)
	bench_pass()
}
