// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for what the original The Specialists 3.0 gives a player: kevlar holds 10 of the 81 free
// slots, so a loadout too heavy for it gets no vest and a vest leaves less room for weapons; a ground
// weapon shows its map text as a TSMessage. ../ts_pickups.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1
#define BARRETT		18

// The loadout item bit for kevlar (the buy menu's "tki 16").
#define ITEM_KEVLAR	16

new g_Ground

public plugin_init()
{
	register_plugin("TS Pickup Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_teardown()
{
	if (g_Ground && pev_valid(g_Ground))
		engfunc(EngFunc_RemoveEntity, g_Ground)
	g_Ground = 0
}

FreeSlots(id)
{
	return get_ent_data(id, "CBasePlayer", "m_iFreeSlots")
}

Float:Armor(id)
{
	new Float:armor
	pev(id, pev_armorvalue, armor)
	return armor
}

MaxSpeed(id)
{
	new Float:maxspeed
	pev(id, pev_maxspeed, maxspeed)
	return floatround(maxspeed)
}

// --- kevlar and free slots -------------------------------------------------------------------

public test_kevlar_takes_ten_slots()
{
	new id = bench_puppet("vested")
	ASSERT(id > 0)
	// The loadout applies at the spawn; the game takes it once the player is in.
	bench_next("vested_joined", 0.5, id)
}

public vested_joined(id)
{
	bench_puppet_cmd(id, "tki %d", ITEM_KEVLAR)
	bench_puppet_spawn(id, "vested_spawned", 20.0, "respawn")
}

public vested_spawned(id)
{
	ASSERT_EQ(floatround(Armor(id)), 100)
	ASSERT_EQ(FreeSlots(id), 71)
	// The speed follows the slots: 210 + 120 * 71 / 81.
	ASSERT_EQ(MaxSpeed(id), 315)
	bench_pass()
}

public test_no_kevlar_without_ten_free_slots()
{
	new id = bench_puppet("overloaded")
	ASSERT(id > 0)
	bench_next("overloaded_joined", 0.5, id)
}

public overloaded_joined(id)
{
	// A Barrett (70) and a Glock (10) leave one slot; the vest after them does not fit.
	bench_puppet_cmd(id, "tkw %d_0 %d_0", BARRETT, GLOCK18)
	bench_puppet_cmd(id, "tki %d", ITEM_KEVLAR)
	bench_puppet_spawn(id, "overloaded_spawned", 20.0, "respawn")
}

public overloaded_spawned(id)
{
	ASSERT_EQ(FreeSlots(id), 1)
	ASSERT_EQ(floatround(Armor(id)), 0)
	bench_pass()
}

public test_kevlar_leaves_less_room_for_weapons()
{
	new id = bench_puppet("packer")
	ASSERT(id > 0)
	bench_next("packer_joined", 0.5, id)
}

public packer_joined(id)
{
	bench_puppet_cmd(id, "tki %d", ITEM_KEVLAR)
	bench_puppet_spawn(id, "packer_spawned", 20.0, "respawn")
}

public packer_spawned(id)
{
	ts_giveweapon(id, BARRETT, 0, 0)
	ASSERT_EQ(FreeSlots(id), 1)
	ASSERT_EQ(MaxSpeed(id), 211)
	// No room for a Glock now: it stays on the floor and the Barrett stays out.
	ts_giveweapon(id, GLOCK18, 0, 0)
	ASSERT_EQ(FreeSlots(id), 1)
	bench_next("packer_holding", 0.5, id)
}

public packer_holding(id)
{
	ASSERT_EQ(ts_getuserwpn(id), BARRETT)
	bench_pass()
}

// --- a ground weapon -------------------------------------------------------------------------

public test_ground_weapon_text_is_a_tsmessage()
{
	new id = bench_puppet("finder")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "finder_spawned", 20.0, "respawn")
}

public finder_spawned(id)
{
	g_Ground = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_groundweapon"))
	ASSERT(g_Ground > 0)
	new num[8]
	num_to_str(GLOCK18, num, charsmax(num))
	KeyValue(g_Ground, "tsweaponid", num)
	KeyValue(g_Ground, "wduration", "0")
	set_pev(g_Ground, pev_message, "You found a Glock.")
	dllfunc(DLLFunc_Spawn, g_Ground)
	new Float:origin[3]
	pev(id, pev_origin, origin)
	engfunc(EngFunc_SetOrigin, g_Ground, origin)
	dllfunc(DLLFunc_Use, g_Ground, id)

	// Outside the round modes a weapon without a wduration comes back after a minute.
	new Float:nextthink
	pev(g_Ground, pev_nextthink, nextthink)
	ASSERT_EQ(floatround(nextthink - get_gametime()), 60)
	bench_wait_message(id, "TSMessage", "You found a Glock.", "finder_told", 2.0)
}

public finder_told(id)
{
	new BenchMsg:msg = bench_msg_last(id, "TSMessage", "You found a Glock.")
	// Effect 8, held 30.
	ASSERT_EQ(bench_msg_int(msg, 3), 8)
	ASSERT_EQ(bench_msg_int(msg, 4), 30)
	ASSERT_EQ(bench_msg_count(id, "HudText", "You found a Glock."), 0)
	bench_pass()
}

KeyValue(ent, const key[], const value[])
{
	set_kvd(0, KV_ClassName, "ts_groundweapon")
	set_kvd(0, KV_KeyName, key)
	set_kvd(0, KV_Value, value)
	set_kvd(0, KV_fHandled, 0)
	dllfunc(DLLFunc_KeyValue, ent, 0)
}
