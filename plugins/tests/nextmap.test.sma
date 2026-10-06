// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for nextmap.sma (NextMap): "say nextmap" with valid and invalid amx_nextmap values, "say
// currentmap", "say ff", and what the plugin does at intermission. The map change itself would end
// the run: the intermission test makes mp_chattime long, then removes the change before it runs.
// amx_nextmap, mp_friendlyfire and mp_chattime are put back after each test.
//

#include <amxmodx>
#include <amxxbench>

new g_Puppet
new g_NextMap[32]
new g_FriendlyFire
new Float:g_ChatTime
new g_CycleNext[32]
new Float:g_FloodTime

public plugin_init()
{
	register_plugin("NextMap Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_setup()
{
	get_cvar_string("amx_nextmap", g_NextMap, charsmax(g_NextMap))
	g_FriendlyFire = get_cvar_num("mp_friendlyfire")
	g_ChatTime = get_cvar_float("mp_chattime")
	// Anti Flood would answer the second "say" in a row instead of this plugin.
	g_FloodTime = get_cvar_float("amx_flood_time")
	set_cvar_float("amx_flood_time", 0.0)
	g_Puppet = 0
}

public bench_teardown()
{
	set_cvar_string("amx_nextmap", g_NextMap)
	set_cvar_num("mp_friendlyfire", g_FriendlyFire)
	set_cvar_float("mp_chattime", g_ChatTime)
	set_cvar_float("amx_flood_time", g_FloodTime)
}

bool:StartPuppet(const name[])
{
	g_Puppet = bench_puppet(name)
	return bench_check(g_Puppet > 0, "puppet created")
}

// The map the plugin picked from the map cycle at load: the first valid one, on a fresh server.
CycleNext()
{
	new cycle[64], line[64]
	get_cvar_string("mapcyclefile", cycle, charsmax(cycle))
	new f = fopen(cycle, "rt")
	g_CycleNext[0] = EOS
	if (!f)
		return
	while (fgets(f, line, charsmax(line)))
	{
		trim(line)
		if (line[0] && is_map_valid(line))
		{
			copy(g_CycleNext, charsmax(g_CycleNext), line)
			break
		}
	}
	fclose(f)
}

SayNextMap(const value[])
{
	set_cvar_string("amx_nextmap", value)
	bench_puppet_say(g_Puppet, "nextmap")
}

public test_say_nextmap()
{
	if (!StartPuppet("nextasker"))
		return
	SayNextMap("ts_lobby")
	ASSERT_MSG(g_Puppet, "TextMsg", "Next Map: ts_lobby")
	bench_pass()
}

public test_unknown_nextmap_falls_back_to_the_map_cycle()
{
	if (!StartPuppet("fallback"))
		return
	CycleNext()
	ASSERT(g_CycleNext[0] != EOS)
	SayNextMap("no_such_map")

	new expected[64], value[32]
	formatex(expected, charsmax(expected), "Next Map: %s", g_CycleNext)
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	// The cvar is corrected too.
	get_cvar_string("amx_nextmap", value, charsmax(value))
	ASSERT_STR_EQ(value, g_CycleNext)
	bench_pass()
}

public test_nextmap_with_bsp_extension()
{
	if (!StartPuppet("bspname"))
		return
	SayNextMap("ts_lobby.bsp")
	// Shown without the extension; the cvar is left alone.
	ASSERT_MSG(g_Puppet, "TextMsg", "Next Map: ts_lobby^n")
	new value[32]
	get_cvar_string("amx_nextmap", value, charsmax(value))
	ASSERT_STR_EQ(value, "ts_lobby.bsp")
	bench_pass()
}

public test_short_invalid_nextmap()
{
	if (!StartPuppet("shortname"))
		return
	CycleNext()
	SayNextMap("ab")
	new value[32]
	get_cvar_string("amx_nextmap", value, charsmax(value))
	ASSERT_STR_EQ(value, g_CycleNext)
	bench_pass()
}

public test_invalid_bsp_name()
{
	if (!StartPuppet("badbsp"))
		return
	CycleNext()
	SayNextMap("no_such_map.bsp")
	new value[32]
	get_cvar_string("amx_nextmap", value, charsmax(value))
	ASSERT_STR_EQ(value, g_CycleNext)
	bench_pass()
}

public test_say_currentmap()
{
	if (!StartPuppet("whereami"))
		return
	bench_puppet_say(g_Puppet, "currentmap")
	new map[32], expected[64]
	get_mapname(map, charsmax(map))
	formatex(expected, charsmax(expected), "Played map: %s", map)
	ASSERT_MSG(g_Puppet, "TextMsg", expected)
	bench_pass()
}

public test_say_ff()
{
	if (!StartPuppet("ffasker"))
		return
	set_cvar_num("mp_friendlyfire", 0)
	bench_puppet_say(g_Puppet, "ff")
	ASSERT_MSG(g_Puppet, "TextMsg", "Friendly fire: Off")
	set_cvar_num("mp_friendlyfire", 1)
	bench_puppet_say(g_Puppet, "ff")
	ASSERT_MSG(g_Puppet, "TextMsg", "Friendly fire: On")
	bench_pass()
}

public test_intermission_schedules_the_change()
{
	// No other one-off task pending (ID 0 is the one the change uses).
	ASSERT_FALSE(task_exists(0, 1))
	set_cvar_float("mp_chattime", 100000.0)
	emessage_begin(MSG_ALL, SVC_INTERMISSION)
	emessage_end()

	// mp_chattime is made 2 seconds longer and the change waits for the old value.
	ASSERT(floatabs(get_cvar_float("mp_chattime") - 100002.0) < 0.01)
	new found = task_exists(0, 1)
	// Remove it (and TS Stats' end of map stats task) before checking anything else.
	remove_task(0, 1)
	ASSERT(found)

	// At map end the plugin takes the 2 seconds back.
	ASSERT(callfunc_begin("plugin_end", "nextmap.amxx") == 1)
	callfunc_end()
	ASSERT(floatabs(get_cvar_float("mp_chattime") - 100000.0) < 0.01)
	bench_pass()
}
