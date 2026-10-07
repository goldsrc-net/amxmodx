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
// currentmap", "say ff", the map change at intermission, and the map cycle position kept across
// map changes. amx_nextmap, mp_friendlyfire and mp_chattime are put back after each test.
//

#include <amxmodx>
#include <amxxbench>

new g_Puppet
new g_NextMap[32]
new g_FriendlyFire
new Float:g_ChatTime
new g_CycleNext[32]
new Float:g_FloodTime
new bool:g_SetupRan

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
	g_SetupRan = true
	RestoreCycle()
}

public bench_teardown()
{
	RestoreCycle()
	// After a map change the test that made it has put back what it changed, and the values
	// saved at setup are gone.
	if (!g_SetupRan)
		return
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

// The map the plugin picked from the map cycle at load: the one at the position it keeps in
// localinfo "lastmapcycle" ("<mapcyclefile> <position>").
CycleNext()
{
	new value[80], cycle[64], pos[8]
	get_localinfo("lastmapcycle", value, charsmax(value))
	parse(value, cycle, charsmax(cycle), pos, charsmax(pos))
	CycleMap(str_to_num(pos), g_CycleNext, charsmax(g_CycleNext))
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

// At intermission the plugin makes mp_chattime 2 seconds longer and changes to amx_nextmap after
// the old mp_chattime; at map end it takes the 2 seconds back.
public test_intermission_changes_the_map()
{
	// No other one-off task pending (ID 0 is the one the change uses).
	ASSERT_FALSE(task_exists(0, 1))
	new Float:chattime = get_cvar_float("mp_chattime")
	set_cvar_float("mp_chattime", 0.5)
	new map[32]
	get_mapname(map, charsmax(map))
	set_cvar_string("amx_nextmap", map)
	emessage_begin(MSG_ALL, SVC_INTERMISSION)
	emessage_end()

	ASSERT(floatabs(get_cvar_float("mp_chattime") - 2.5) < 0.01)
	ASSERT(task_exists(0, 1))
	bench_expect_map_change("after_intermission", _:chattime)
}

public after_intermission(Float:chattime)
{
	ASSERT(floatabs(get_cvar_float("mp_chattime") - 0.5) < 0.01)
	set_cvar_float("mp_chattime", chattime)
	bench_pass()
}

// The valid maps of the map cycle, as the plugin counts them; n from 1.
CycleMap(n, map[], len)
{
	new cycle[64], line[64], count = 0
	get_cvar_string("mapcyclefile", cycle, charsmax(cycle))
	map[0] = EOS
	new f = fopen(cycle, "rt")
	if (!f)
		return 0
	while (fgets(f, line, charsmax(line)))
	{
		trim(line)
		if (!isalnum(line[0]) || !is_map_valid(line))
			continue
		if (++count == n)
			copy(map, len, line)
	}
	fclose(f)
	return count
}

// The plugin keeps "<mapcyclefile> <position>" in localinfo "lastmapcycle" and goes on from there
// on the next map. First with a map cycle of this test's (lines not starting with a letter or
// digit, and maps that do not exist, are skipped), from its second map; then with the server's,
// from past the end, which starts over.
#define TEST_CYCLE "bench_mapcycle.txt"

// Where the server's mapcyclefile is kept across the map changes.
new const CYCLE_KEY[] = "bench_nextmap_cycle"

RestoreCycle()
{
	new cycle[64]
	get_localinfo(CYCLE_KEY, cycle, charsmax(cycle))
	if (cycle[0])
	{
		set_cvar_string("mapcyclefile", cycle)
		set_localinfo(CYCLE_KEY, "")
	}
	delete_file(TEST_CYCLE)
}

public test_map_cycle_position_carries_over()
{
	new cycle[64]
	get_cvar_string("mapcyclefile", cycle, charsmax(cycle))
	ASSERT(cycle[0] != EOS)
	set_localinfo(CYCLE_KEY, cycle)
	new f = fopen(TEST_CYCLE, "wt")
	ASSERT(f)
	fputs(f, "// maps^nts_lobby^n^nno_such_map^nts_awaken^nts_hammertime^nts_central^n")
	fclose(f)
	set_cvar_string("mapcyclefile", TEST_CYCLE)
	set_localinfo("lastmapcycle", "bench_mapcycle.txt 2")
	bench_set_timeout(120.0)
	bench_change_map("", "from_the_second")
}

bool:CycleAt(const map[], const cycle[], pos)
{
	new value[80], expected[80]
	get_cvar_string("amx_nextmap", value, charsmax(value))
	if (!__bench_str_eq(value, map))
		return false
	get_localinfo("lastmapcycle", value, charsmax(value))
	formatex(expected, charsmax(expected), "%s %d", cycle, pos)
	return __bench_str_eq(value, expected)
}

public from_the_second()
{
	// Past ts_lobby and ts_awaken: the third map.
	if (!CycleAt("ts_hammertime", TEST_CYCLE, 3))
		return
	RestoreCycle()
	new cycle[64], value[80]
	get_cvar_string("mapcyclefile", cycle, charsmax(cycle))
	formatex(value, charsmax(value), "%s 999", cycle)
	set_localinfo("lastmapcycle", value)
	bench_change_map("", "from_the_start")
}

public from_the_start()
{
	new cycle[64], first[32]
	get_cvar_string("mapcyclefile", cycle, charsmax(cycle))
	CycleMap(1, first, charsmax(first))
	if (!CycleAt(first, cycle, 1))
		return
	bench_pass()
}
