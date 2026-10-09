// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the original The Specialists 3.0's "powerup <n>" cheat: it works only when the map started
// with sv_cheats 1, and its table is 1 slow pause, 2 a grenade, 3 kung fu and superjump together,
// 4 more clips, 5 double fire rate, anything else slow motion. Impulse 100 turns on no flashlight,
// impulse 204 works without cheats, and impulses 101 and 203 do nothing even with them. Impulses work
// in the attack delay after a spawn.
// ../ts_cheats.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <amxxbench>

new g_Map[32]
new g_Cash

public plugin_init()
{
	register_plugin("TS Cheat Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	get_mapname(g_Map, charsmax(g_Map))
}

// The type the PwUp message last told the player he holds, or -1.
LastHeld(id)
{
	new BenchMsg:msg = bench_msg_last(id, "PwUp")
	if (msg == BenchMsg:0)
		return -1
	return bench_msg_int(msg, 0)
}

public bench_teardown()
{
	set_cvar_num("sv_cheats", 0)
}

// sv_cheats turned on after the map started does not count: the game read it when the map started.
public test_cheats_are_read_at_map_start()
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	new id = bench_puppet("latecheat")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "latecheat_spawned", 20.0, "respawn")
}

public latecheat_spawned(id)
{
	set_cvar_num("sv_cheats", 1)
	g_Cash = ts_getusercash(id)
	bench_puppet_cmd(id, "powerup 5")
	bench_puppet_cmd(id, "cashala")
	bench_next("latecheat_after", 0.5, id)
}

public latecheat_after(id)
{
	ASSERT(LastHeld(id) != TSPWUP_DFIRERATE)
	ASSERT_EQ(ts_getusercash(id), g_Cash)
	// With cheats off, cashala is not a command at all.
	ASSERT_MSG(id, "TextMsg", "Unknown command: cashala")
	bench_pass()
}

public test_powerup_needs_cheats()
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	new id = bench_puppet("nocheat")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "nocheat_spawned", 20.0, "respawn")
}

public nocheat_spawned(id)
{
	bench_puppet_cmd(id, "powerup 1")
	bench_puppet_cmd(id, "powerup 3")
	bench_next("nocheat_after", 0.5, id)
}

public nocheat_after(id)
{
	ASSERT(LastHeld(id) != TSPWUP_SLOWPAUSE)
	ASSERT_EQ(ts_has_fupowerup(id), 0)
	ASSERT_EQ(ts_has_superjump(id), 0)
	bench_pass()
}

// The game reads sv_cheats when the map starts, so the cheats are turned on with a map change, and
// off again with another.
public test_powerup_table()
{
	bench_set_timeout(120.0)
	set_cvar_num("sv_cheats", 1)
	bench_change_map(g_Map, "table_map")
}

public table_map()
{
	new id = bench_puppet("cheater")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "table_spawned", 20.0, "respawn")
}

public table_spawned(id)
{
	bench_puppet_cmd(id, "powerup 3")
	bench_next("table_kungfu", 0.5, id)
}

public table_kungfu(id)
{
	ASSERT_EQ(ts_has_fupowerup(id), 1)
	ASSERT_EQ(ts_has_superjump(id), 1)
	bench_puppet_cmd(id, "powerup 6")
	bench_next("table_six", 0.5, id)
}

public table_six(id)
{
	// 6 is not in the table: slow motion, held.
	ASSERT_EQ(LastHeld(id), TSPWUP_SLOWMO)
	bench_puppet_cmd(id, "powerup 7")
	bench_next("table_seven", 0.5, id)
}

public table_seven(id)
{
	ASSERT_EQ(LastHeld(id), TSPWUP_SLOWMO)
	bench_puppet_cmd(id, "powerup 1")
	bench_next("table_one", 0.5, id)
}

public table_one(id)
{
	ASSERT_EQ(LastHeld(id), TSPWUP_SLOWPAUSE)
	set_cvar_num("sv_cheats", 0)
	bench_change_map(g_Map, "table_restored")
}

public table_restored()
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	bench_pass()
}

// The original's ImpulseCommands (0xcb780) has 99, 201 and 204 and its CheatImpulseCommands no 100:
// impulse 100 turns on no flashlight, whatever mp_flashlight says (here 1 where it exists).
new g_Flashlight

public test_impulse_100_has_no_flashlight()
{
	new id = bench_puppet("flashlighter")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "flashlighter_spawned", 20.0, "respawn")
}

public flashlighter_spawned(id)
{
	new cvar = get_cvar_pointer("mp_flashlight")
	g_Flashlight = cvar ? get_pcvar_num(cvar) : -1
	if (cvar)
		set_pcvar_num(cvar, 1)
	bench_puppet_input(id, 0, 0.0, 0.0, 0.0, 100)
	bench_next("flashlighter_pressed", 0.5, id)
}

public flashlighter_pressed(id)
{
	bench_puppet_input(id, 0)
	new cvar = get_cvar_pointer("mp_flashlight")
	if (cvar && g_Flashlight != -1)
		set_pcvar_num(cvar, g_Flashlight)
	server_print("ts_cheats: after impulse 100, effects %d (mp_flashlight %s)", pev(id, pev_effects), cvar ? "registered" : "absent")
	ASSERT_EQ(pev(id, pev_effects) & EF_DIMLIGHT, 0)
	bench_pass()
}

// Impulse 204 is in the original's ImpulseCommands (0xcb9b0): ForceClientDllUpdate without cheats,
// which re-tells the player his spectator state at once (Spectator idx, 0). (Pressed 1.5 s after the
// spawn: reTS's ItemPostFrame skips the impulses while the spawn's attack delay runs.)
public test_impulse_204_needs_no_cheats()
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	new id = bench_puppet("updater")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "updater_spawned", 20.0, "respawn")
}

new BenchMsg:g_UpdateMark

public updater_spawned(id)
{
	bench_next("updater_ready", 1.5, id)
}

public updater_ready(id)
{
	g_UpdateMark = bench_msg_last(id, "Spectator")
	bench_puppet_input(id, 0, 0.0, 0.0, 0.0, 204)
	bench_next("updater_pressed", 0.5, id)
}

public updater_pressed(id)
{
	bench_puppet_input(id, 0)
	new count = 0
	for (new BenchMsg:msg = bench_msg_next(id, g_UpdateMark, "Spectator"); msg != BenchMsg:0;
		msg = bench_msg_next(id, msg, "Spectator"))
		if (bench_msg_int(msg, 0) == id && bench_msg_int(msg, 1) == 0)
			count++
	server_print("ts_cheats: Spectator (self, 0) after impulse 204: %d", count)
	ASSERT_EQ(count, 1)
	bench_pass()
}

// The original's CheatImpulseCommands table (0xcba3c) has 102-107, 195-197, 199 and 202: with
// cheats on, impulse 203 removes nothing the player looks at and impulse 101 gives no Half-Life
// weapons.
new g_Target
new bool:g_Aimed
new g_Turns

public test_cheat_impulses_not_in_the_table()
{
	bench_set_timeout(120.0)
	set_cvar_num("sv_cheats", 1)
	bench_change_map(g_Map, "impulses_map")
}

public impulses_map()
{
	new id = bench_puppet("impulser")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "impulses_spawned", 20.0, "respawn")
}

public impulses_spawned(id)
{
	// let him settle on the floor first
	bench_next("impulses_place", 1.0, id)
}

public impulses_place(id)
{
	g_Turns = 0
	impulses_turn(id)
}

// Places the target 40 units ahead at eye height, a quarter turn further each try, until his view
// line meets it first (not a wall or anything else).
public impulses_turn(id)
{
	new Float:eye[3], Float:ofs[3], Float:angles[3], Float:fwd[3]
	if (g_Target > 0 && pev_valid(g_Target))
	{
		if (LookedAt(id) == g_Target)
		{
			impulses_aimed(id)
			return
		}
		engfunc(EngFunc_RemoveEntity, g_Target)
		g_Target = 0
	}
	ASSERT(g_Turns < 4)
	pev(id, pev_origin, eye)
	pev(id, pev_view_ofs, ofs)
	angles[1] = 90.0 * g_Turns++
	engfunc(EngFunc_MakeVectors, angles)
	global_get(glb_v_forward, fwd)
	for (new i = 0; i < 3; i++)
		eye[i] += ofs[i] + fwd[i] * 40.0
	// a solid point entity that takes damage, thinking 0.6 s from now: a SUB_Remove think set by
	// impulse 203 would remove it then
	g_Target = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"))
	ASSERT(g_Target > 0)
	dllfunc(DLLFunc_Spawn, g_Target)
	set_pev(g_Target, pev_solid, SOLID_BBOX)
	set_pev(g_Target, pev_takedamage, 1.0)
	engfunc(EngFunc_SetSize, g_Target, Float:{-8.0, -8.0, -8.0}, Float:{8.0, 8.0, 8.0})
	engfunc(EngFunc_SetOrigin, g_Target, eye)
	set_pev(g_Target, pev_nextthink, get_gametime() + 0.6)
	bench_puppet_look_at(id, eye)
	bench_next("impulses_turn", 0.2, id)
}

// The entity the puppet's view line hits first, as UTIL_FindEntityForward traces it.
LookedAt(id)
{
	new Float:eye[3], Float:ofs[3], Float:angles[3], Float:fwd[3], Float:end[3]
	pev(id, pev_origin, eye)
	pev(id, pev_view_ofs, ofs)
	pev(id, pev_v_angle, angles)
	engfunc(EngFunc_MakeVectors, angles)
	global_get(glb_v_forward, fwd)
	for (new i = 0; i < 3; i++)
	{
		eye[i] += ofs[i]
		end[i] = eye[i] + fwd[i] * 8192.0
	}
	engfunc(EngFunc_TraceLine, eye, end, 0, id, 0)
	return get_tr2(0, TR_pHit)
}

public impulses_aimed(id)
{
	g_Aimed = LookedAt(id) == g_Target
	set_pev(g_Target, pev_nextthink, get_gametime() + 0.5)
	bench_puppet_input(id, 0, 0.0, 0.0, 0.0, 203)
	bench_next("impulses_101", 0.1, id)
}

public impulses_101(id)
{
	bench_puppet_input(id, 0, 0.0, 0.0, 0.0, 101)
	bench_next("impulses_after", 1.0, id)
}

public impulses_after(id)
{
	bench_puppet_input(id, 0)
	new targetLeft = pev_valid(g_Target) ? 1 : 0
	new given = 0
	new const names[][] = {"weapon_crowbar", "weapon_9mmhandgun", "weapon_shotgun", "weapon_9mmAR",
		"weapon_357", "weapon_crossbow", "weapon_rpg", "weapon_gauss", "weapon_egon", "weapon_hornetgun",
		"weapon_handgrenade", "weapon_tripmine", "weapon_satchel", "weapon_snark"}
	for (new i = 0; i < sizeof(names); i++)
		if (engfunc(EngFunc_FindEntityByString, -1, "classname", names[i]) > 0)
			given++
	server_print("ts_cheats: after impulses 203 and 101: aimed at the target %d, target left %d, Half-Life weapons %d",
		g_Aimed, targetLeft, given)
	if (targetLeft)
		engfunc(EngFunc_RemoveEntity, g_Target)
	new ok = g_Aimed && targetLeft == 1 && given == 0
	set_cvar_num("sv_cheats", 0)
	bench_change_map(g_Map, "impulses_restored", ok ? 1 : 0)
}

public impulses_restored(ok)
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	ASSERT_EQ(ok, 1)
	bench_pass()
}

// ImpulseCommands runs during the attack delay a spawn sets (TSInit: 1 s) while the player has no
// weapon in hand (ItemPostFrame, 0xcc4ff): impulse 204 0.2 s after the spawn re-tells him his
// spectator state at once.
new BenchMsg:g_EarlyMark

public test_impulse_in_the_spawn_attack_delay()
{
	new id = bench_puppet("earlyupdater")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "early_spawned", 20.0, "respawn")
}

public early_spawned(id)
{
	bench_next("early_ready", 0.2, id)
}

public early_ready(id)
{
	g_EarlyMark = bench_msg_last(id, "Spectator")
	bench_puppet_input(id, 0, 0.0, 0.0, 0.0, 204)
	bench_next("early_pressed", 0.3, id)
}

public early_pressed(id)
{
	bench_puppet_input(id, 0)
	new count = 0
	for (new BenchMsg:msg = bench_msg_next(id, g_EarlyMark, "Spectator"); msg != BenchMsg:0;
		msg = bench_msg_next(id, msg, "Spectator"))
		if (bench_msg_int(msg, 0) == id && bench_msg_int(msg, 1) == 0)
			count++
	server_print("ts_cheats: Spectator (self, 0) 0.3 s after impulse 204 at 0.2 s: %d", count)
	ASSERT_EQ(count, 1)
	bench_pass()
}
