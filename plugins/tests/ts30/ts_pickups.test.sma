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
// weapon shows its map text as a TSMessage; a grenade powerup gives one M61 only with 7 free slots and
// fewer than 2 carried, and a refused one stays where it is; throwing the last one brings out the next
// weapon. ../ts_pickups.test.sma is the same on reTS.
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
#define M61			24
#define SKORPION	17
#define BULL		31
#define KATANA		34

// The loadout item bit for kevlar (the buy menu's "tki 16").
#define ITEM_KEVLAR	16

new g_Ground
new g_Pwup
new g_Weapon
new BenchMsg:g_Mark

public plugin_init()
{
	register_plugin("TS Pickup Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_teardown()
{
	if (g_Ground && pev_valid(g_Ground))
		engfunc(EngFunc_RemoveEntity, g_Ground)
	g_Ground = 0
	RemovePowerup()
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

// --- the grenade powerup -----------------------------------------------------------------------

// A grenade powerup gives one M61 through the same gate as any weapon: it needs 7 free slots and
// a stack under 2. A refused one stays where it is. ts_createpwup's powerups come back like a map's
// own, so a taken one hides until then.

public bool:pwup_taken(id)
{
	return pev_valid(g_Pwup) && (pev(g_Pwup, pev_effects) & EF_NODRAW) != 0
}

RemovePowerup()
{
	if (pev_valid(g_Pwup))
		engfunc(EngFunc_RemoveEntity, g_Pwup)
	g_Pwup = 0
}

// One over his head: it lands on him.
DropGrenadePowerup(id)
{
	new Float:origin[3]
	pev(id, pev_origin, origin)
	origin[2] += 48.0
	g_Pwup = ts_createpwup(TSPWUP_GRENADE, origin)
	return g_Pwup
}

// A map's own grenade powerup at his feet.
PlaceGrenadePowerup(id)
{
	g_Pwup = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_powerup"))
	if (g_Pwup <= 0)
		return 0
	new num[8]
	num_to_str(TSPWUP_GRENADE, num, charsmax(num))
	PwupKeyValue(g_Pwup, "pwuptype", num)
	dllfunc(DLLFunc_Spawn, g_Pwup)
	new Float:origin[3]
	pev(id, pev_origin, origin)
	origin[2] += 48.0
	engfunc(EngFunc_SetOrigin, g_Pwup, origin)
	return g_Pwup
}

// A refused powerup has landed, can be touched and is still drawn.
bool:PwupWaiting()
{
	return pev_valid(g_Pwup) && pev(g_Pwup, pev_solid) == SOLID_TRIGGER
		&& !(pev(g_Pwup, pev_effects) & EF_NODRAW)
}

Grenades(id)
{
	new clip, ammo, mode, extra
	if (ts_getuserwpn(id, clip, ammo, mode, extra) != M61)
		return 0
	return clip
}

public test_grenade_powerup_stacks_to_two()
{
	new id = bench_puppet("bomber")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "bomber_spawned", 20.0, "respawn")
}

public bomber_spawned(id)
{
	// Right after the spawn, bare handed.
	ASSERT_EQ(FreeSlots(id), 81)
	ASSERT(DropGrenadePowerup(id) > 0)
	bench_wait_until("pwup_taken", "bomber_took_one", 4.0, id)
}

// The grenade comes out on the next frame.
public bomber_took_one(id)
{
	bench_next("bomber_has_one", 0.3, id)
}

public bomber_has_one(id)
{
	// Taken and wielded.
	ASSERT_EQ(Grenades(id), 1)
	ASSERT_EQ(FreeSlots(id), 74)
	RemovePowerup()
	ASSERT(DropGrenadePowerup(id) > 0)
	bench_wait_until("pwup_taken", "bomber_took_two", 4.0, id)
}

public bomber_took_two(id)
{
	bench_next("bomber_has_two", 0.3, id)
}

public bomber_has_two(id)
{
	// The slots show the second one. ts_getuserwpn's clip still reads 1: it comes from WeaponInfo,
	// which the game sends again only when the weapon or its reserve changes.
	ASSERT_EQ(ts_getuserwpn(id), M61)
	ASSERT_EQ(FreeSlots(id), 67)
	// Two is the most he carries: a third stays on the floor.
	RemovePowerup()
	ASSERT(DropGrenadePowerup(id) > 0)
	bench_next("bomber_refused", 3.0, id)
}

public bomber_refused(id)
{
	ASSERT(PwupWaiting())
	ASSERT_EQ(ts_getuserwpn(id), M61)
	ASSERT_EQ(FreeSlots(id), 67)
	bench_pass()
}

public test_grenade_powerup_needs_seven_slots()
{
	new id = bench_puppet("laden")
	ASSERT(id > 0)
	bench_next("laden_joined", 0.5, id)
}

public laden_joined(id)
{
	// A Barrett (70) and a Glock (10) leave one slot.
	bench_puppet_cmd(id, "tkw %d_0 %d_0", BARRETT, GLOCK18)
	bench_puppet_spawn(id, "laden_spawned", 20.0, "respawn")
}

public laden_spawned(id)
{
	ASSERT_EQ(FreeSlots(id), 1)
	bench_next("laden_settled", 0.5, id)
}

public laden_settled(id)
{
	g_Weapon = ts_getuserwpn(id)
	ASSERT(DropGrenadePowerup(id) > 0)
	bench_next("laden_refused", 3.0, id)
}

public laden_refused(id)
{
	ASSERT(PwupWaiting())
	ASSERT_EQ(FreeSlots(id), 1)
	ASSERT_EQ(ts_getuserwpn(id), g_Weapon)
	// A map's own one is refused the same way and keeps waiting.
	RemovePowerup()
	ASSERT(PlaceGrenadePowerup(id) > 0)
	bench_next("laden_refused_placed", 3.0, id)
}

public laden_refused_placed(id)
{
	ASSERT(PwupWaiting())
	ASSERT_EQ(FreeSlots(id), 1)
	ASSERT_EQ(ts_getuserwpn(id), g_Weapon)
	bench_pass()
}

public test_grenade_powerup_with_room_for_one()
{
	new id = bench_puppet("sniper")
	ASSERT(id > 0)
	bench_next("sniper_joined", 0.5, id)
}

public sniper_joined(id)
{
	// A Barrett alone leaves 11 slots: room for one grenade, not two.
	bench_puppet_cmd(id, "tkw %d_0", BARRETT)
	bench_puppet_spawn(id, "sniper_spawned", 20.0, "respawn")
}

public sniper_spawned(id)
{
	ASSERT_EQ(FreeSlots(id), 11)
	bench_next("sniper_settled", 0.5, id)
}

public sniper_settled(id)
{
	// A map's own one: taken, then hidden until it comes back.
	ASSERT(PlaceGrenadePowerup(id) > 0)
	bench_next("sniper_has_one", 3.0, id)
}

public sniper_has_one(id)
{
	ASSERT(pev_valid(g_Pwup))
	ASSERT(pev(g_Pwup, pev_effects) & EF_NODRAW)
	ASSERT_EQ(Grenades(id), 1)
	ASSERT_EQ(FreeSlots(id), 4)
	RemovePowerup()
	ASSERT(DropGrenadePowerup(id) > 0)
	bench_next("sniper_refused", 3.0, id)
}

public sniper_refused(id)
{
	// One grenade of two, but only 4 slots left.
	ASSERT(PwupWaiting())
	ASSERT_EQ(Grenades(id), 1)
	ASSERT_EQ(FreeSlots(id), 4)
	bench_pass()
}

// Throwing the last grenade: the game takes the M61 off the bar (WStatus owned 0), gives the slots
// back and brings out the best weapon left (WeaponInfo), which the client draws from.
public test_last_grenade_thrown_brings_out_the_next_weapon()
{
	new id = bench_puppet("pitcher")
	ASSERT(id > 0)
	bench_next("pitcher_joined", 0.5, id)
}

public pitcher_joined(id)
{
	// Raging Bull, katana and Skorpion: 40 slots, 41 free.
	bench_puppet_cmd(id, "tkw %d_0 %d_0 %d_0", BULL, KATANA, SKORPION)
	bench_puppet_spawn(id, "pitcher_spawned", 20.0, "respawn")
}

public pitcher_spawned(id)
{
	bench_next("pitcher_settled", 1.0, id)
}

public pitcher_settled(id)
{
	ASSERT_EQ(FreeSlots(id), 41)
	ASSERT(DropGrenadePowerup(id) > 0)
	bench_wait_until("pwup_taken", "pitcher_took", 4.0, id)
}

public pitcher_took(id)
{
	RemovePowerup()
	bench_next("pitcher_holding", 1.5, id)
}

public pitcher_holding(id)
{
	ASSERT_EQ(ts_getuserwpn(id), M61)
	ASSERT_EQ(FreeSlots(id), 34)
	g_Mark = bench_msg_last(id)
	new Float:angles[3]
	pev(id, pev_v_angle, angles)
	angles[0] = -45.0
	bench_puppet_angles(id, angles)
	bench_puppet_input(id, IN_ATTACK)
	bench_next("pitcher_cooked", 0.6, id)
}

public pitcher_cooked(id)
{
	// Letting go throws it.
	bench_puppet_input(id, 0)
	bench_next("pitcher_threw", 2.0, id)
}

public pitcher_threw(id)
{
	ASSERT_EQ(FreeSlots(id), 41)
	ASSERT_EQ(ts_getuserwpn(id), SKORPION)
	new BenchMsg:m = g_Mark, name[32], status = 0, info = 0
	while ((m = bench_msg_next(id, m)) != BenchMsg:0)
	{
		bench_msg_name(m, name, charsmax(name))
		if (equal(name, "WStatus"))
		{
			// Only the M61's own cell changes.
			ASSERT_EQ(bench_msg_int(m, 0), M61)
			ASSERT_EQ(bench_msg_int(m, 1), 0)
			status++
		}
		else if (equal(name, "WeaponInfo"))
		{
			ASSERT_EQ(bench_msg_int(m, 0), SKORPION)
			info++
		}
	}
	ASSERT_EQ(status, 1)
	ASSERT_EQ(info, 1)
	bench_pass()
}

PwupKeyValue(ent, const key[], const value[])
{
	set_kvd(0, KV_ClassName, "ts_powerup")
	set_kvd(0, KV_KeyName, key)
	set_kvd(0, KV_Value, value)
	set_kvd(0, KV_fHandled, 0)
	dllfunc(DLLFunc_KeyValue, ent, 0)
}

KeyValue(ent, const key[], const value[])
{
	set_kvd(0, KV_ClassName, "ts_groundweapon")
	set_kvd(0, KV_KeyName, key)
	set_kvd(0, KV_Value, value)
	set_kvd(0, KV_fHandled, 0)
	dllfunc(DLLFunc_KeyValue, ent, 0)
}
