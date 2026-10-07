// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for TSX's ts_getuserammo and ts_setuserammo on the original The Specialists 3.0 game
// library, where they work through the gamedata (CTSGun, s_weapon_status, CBasePlayer). A gun's
// ammo is the reserve of its caliber, which the next reload takes from; the grenade and the knives
// count in their own clip, and every unit holds free slots that a throw gives back.
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
#define BERETTA		2
#define UZI			3
#define DEAGLE		12
#define FLAG		29
#define KATANA		34
#define M61			24
#define KNIFE		25
#define SEALKNIFE	35

new g_Clip
new g_Other
new g_AmmoCount = -1

public plugin_init()
{
	register_plugin("TSX Ammo Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_teardown()
{
	if (g_AmmoCount != -1)
	{
		set_cvar_num("ammocount", g_AmmoCount)
		g_AmmoCount = -1
	}

	// A thrown knife stays where it lands (a thrown grenade goes off by itself).
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "knife")))
		engfunc(EngFunc_RemoveEntity, ent)
}

FreeSlots(id)
{
	return get_ent_data(id, "CBasePlayer", "m_iFreeSlots")
}

Float:MaxSpeed(id)
{
	new Float:speed
	pev(id, pev_maxspeed, speed)
	return speed
}

// GetSpeedBySlots in the game: 210 with no free slots, 330 from 81 up.
SpeedBySlots(slots)
{
	if (slots > 80)
		return 330
	return floatround(float(slots) * 120.0 / 81.0 + 210.0, floatround_tozero)
}

// The reserve in the last WeaponInfo the game sent the player about weapon, or -1.
LastReserve(id, weapon)
{
	new BenchMsg:msg = bench_msg_last(id, "WeaponInfo")
	if (msg == BenchMsg:0 || bench_msg_int(msg, 0) != weapon)
		return -1
	return bench_msg_int(msg, 2)
}

// --- a gun's reserve -------------------------------------------------------------------------

public test_reserve_is_per_caliber_and_reaches_the_hud()
{
	g_Other = bench_puppet("bystander")
	ASSERT(g_Other > 0)
	bench_puppet_spawn(g_Other, "reserve_other_spawned", 20.0, "respawn")
}

public reserve_other_spawned(other)
{
	ts_giveweapon(other, GLOCK18, 0, 0)
	ts_setuserammo(other, GLOCK18, 5)
	new id = bench_puppet("loader")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "reserve_spawned", 20.0, "respawn")
}

public reserve_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	ASSERT_EQ(ts_setuserammo(id, GLOCK18, 40), 1)
	ASSERT_EQ(ts_getuserammo(id, GLOCK18), 40)
	// Every 9mm gun reloads from the same rounds; the .50 AE reserve is apart.
	ASSERT_EQ(ts_getuserammo(id, UZI), 40)
	ASSERT_EQ(ts_getuserammo(id, BERETTA), 40)
	ASSERT_EQ(ts_getuserammo(id, DEAGLE), 0)
	// Only this player's gun: the one standing next to him keeps his.
	ASSERT_EQ(ts_getuserammo(g_Other, GLOCK18), 5)

	// The game sends the new reserve to the player's HUD itself.
	bench_wait_until("reserve_sent", "reserve_shown", 2.0, id)
}

public reserve_sent(id)
{
	return LastReserve(id, GLOCK18) == 40
}

public reserve_shown(id)
{
	new clip, ammo
	ASSERT_EQ(ts_getuserwpn(id, clip, ammo), GLOCK18)
	ASSERT_EQ(ammo, 40)
	bench_pass()
}

public test_reload_takes_the_reserve_that_was_set()
{
	new id = bench_puppet("reloader")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "reload_spawned", 20.0, "respawn")
}

public reload_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	ASSERT_EQ(ts_setuserammo(id, GLOCK18, 0), 1)
	ASSERT_EQ(ts_getuserammo(id, GLOCK18), 0)
	// A few shots, once the gun is out, leave room in the clip.
	bench_next("reload_fire", 1.0, id)
}

public reload_fire(id)
{
	bench_puppet_input(id, IN_ATTACK)
	bench_next("reload_empty", 0.2, id)
}

public reload_empty(id)
{
	bench_puppet_input(id, 0)
	ASSERT_EQ(ts_setuserammo(id, GLOCK18, 3), 1)
	bench_wait_until("reload_three_sent", "reload_ready", 2.0, id)
}

public reload_three_sent(id)
{
	return LastReserve(id, GLOCK18) == 3
}

public reload_ready(id)
{
	g_Clip = bench_msg_int(bench_msg_last(id, "WeaponInfo"), 1)
	ASSERT(g_Clip < 17)
	bench_puppet_input(id, IN_RELOAD)
	bench_wait_until("reload_done", "reloaded", 5.0, id)
}

public reload_done(id)
{
	return LastReserve(id, GLOCK18) != 3 && LastReserve(id, GLOCK18) != -1
}

public reloaded(id)
{
	bench_puppet_input(id, 0)
	new taken = min(17 - g_Clip, 3)
	ASSERT_EQ(bench_msg_int(bench_msg_last(id, "WeaponInfo"), 1), g_Clip + taken)
	ASSERT_EQ(LastReserve(id, GLOCK18), 3 - taken)
	ASSERT_EQ(ts_getuserammo(id, GLOCK18), 3 - taken)
	bench_pass()
}

public test_reserve_stops_at_the_max_carry()
{
	g_AmmoCount = get_cvar_num("ammocount")
	set_cvar_num("ammocount", 0)
	new id = bench_puppet("hoarder")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "hoard_spawned", 20.0, "respawn")
}

public hoard_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	// With ammocount 0 a player carries 210 rounds of 9mm and 70 of .50 AE (Set_ammo_count).
	ASSERT_EQ(ts_setuserammo(id, GLOCK18, 10000), 1)
	ASSERT_EQ(ts_getuserammo(id, GLOCK18), 210)
	ASSERT_EQ(ts_setuserammo(id, DEAGLE, 10000), 1)
	ASSERT_EQ(ts_getuserammo(id, DEAGLE), 70)
	ASSERT_EQ(ts_setuserammo(id, GLOCK18, 100), 1)
	ASSERT_EQ(ts_getuserammo(id, GLOCK18), 100)
	// The game applies a new ammocount on its next think.
	set_cvar_num("ammocount", 1)
	bench_next("hoard_fewer", 0.5, id)
}

public hoard_fewer(id)
{
	// With ammocount 1, 90 rounds of 9mm.
	ASSERT_EQ(ts_setuserammo(id, GLOCK18, 10000), 1)
	ASSERT_EQ(ts_getuserammo(id, GLOCK18), 90)
	bench_pass()
}

// --- the grenade and the knives --------------------------------------------------------------

public test_grenades_count_in_the_clip_and_hold_slots()
{
	new id = bench_puppet("grenadier")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "grenade_spawned", 20.0, "respawn")
}

public grenade_spawned(id)
{
	new slots = FreeSlots(id)
	ts_giveweapon(id, M61, 1, 0)
	// One grenade takes 7 slots.
	ASSERT_EQ(ts_getuserammo(id, M61), 1)
	ASSERT_EQ(FreeSlots(id), slots - 7)

	ASSERT_EQ(ts_setuserammo(id, M61, 3), 1)
	ASSERT_EQ(ts_getuserammo(id, M61), 3)
	ASSERT_EQ(FreeSlots(id), slots - 21)

	// More than the free slots hold is refused, and nothing changes.
	new most = 3 + (slots - 21) / 7
	ASSERT_EQ(ts_setuserammo(id, M61, most + 1), 0)
	ASSERT_EQ(ts_getuserammo(id, M61), 3)
	ASSERT_EQ(ts_setuserammo(id, M61, most), 1)
	ASSERT_EQ(ts_setuserammo(id, M61, 3), 1)
	ASSERT_EQ(FreeSlots(id), slots - 21)

	// Once it is out, pull the pin and let go: one grenade leaves and gives its slots back.
	g_Clip = slots
	bench_next("grenade_pull", 1.0, id)
}

public grenade_pull(id)
{
	bench_puppet_input(id, IN_ATTACK)
	bench_next("grenade_release", 0.3, id)
}

public grenade_release(id)
{
	bench_puppet_input(id, 0)
	bench_wait_until("grenade_thrown", "grenade_counted", 3.0, id)
}

// The slots come back once the throw is over.
public grenade_thrown(id)
{
	return ts_getuserammo(id, M61) != 3 && FreeSlots(id) != g_Clip - 21
}

public grenade_counted(id)
{
	ASSERT_EQ(ts_getuserammo(id, M61), 2)
	ASSERT_EQ(FreeSlots(id), g_Clip - 14)
	bench_pass()
}

public test_stack_moves_the_speed_with_the_slots()
{
	new id = bench_puppet("laden")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "laden_spawned", 20.0, "respawn")
}

public laden_spawned(id)
{
	ts_giveweapon(id, M61, 1, 0)
	bench_next("laden_ready", 0.2, id)
}

public laden_ready(id)
{
	// The speed the game gave him for the grenade he picked up.
	new speed = floatround(MaxSpeed(id))
	ASSERT_EQ(speed, SpeedBySlots(FreeSlots(id)))
	ASSERT(FreeSlots(id) <= 80)

	// Two more take 14 slots and slow him as the game's own pickups would.
	ASSERT_EQ(ts_setuserammo(id, M61, 3), 1)
	ASSERT_EQ(floatround(MaxSpeed(id)), SpeedBySlots(FreeSlots(id)))
	ASSERT(floatround(MaxSpeed(id)) < speed)

	// And back to one grenade, back to the speed the game gave him.
	ASSERT_EQ(ts_setuserammo(id, M61, 1), 1)
	ASSERT_EQ(floatround(MaxSpeed(id)), speed)
	bench_pass()
}

public test_thrown_knife_comes_off_the_count()
{
	new id = bench_puppet("thrower")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "knife_spawned", 20.0, "respawn")
}

public knife_spawned(id)
{
	new slots = FreeSlots(id)
	ts_giveweapon(id, KNIFE, 1, 0)
	ASSERT_EQ(ts_setuserammo(id, KNIFE, 4), 1)
	ASSERT_EQ(ts_getuserammo(id, KNIFE), 4)
	ASSERT_EQ(FreeSlots(id), slots - 4)
	g_Clip = slots
	bench_next("knife_throw", 1.0, id)
}

public knife_throw(id)
{
	bench_puppet_input(id, IN_ATTACK2)
	bench_wait_until("knife_thrown", "knife_counted", 3.0, id)
}

public knife_thrown(id)
{
	return ts_getuserammo(id, KNIFE) != 4
}

public knife_counted(id)
{
	bench_puppet_input(id, 0)
	ASSERT_EQ(ts_getuserammo(id, KNIFE), 3)
	ASSERT_EQ(FreeSlots(id), g_Clip - 3)
	bench_pass()
}

// --- what is refused -------------------------------------------------------------------------

public test_weapons_without_ammo_and_missing_stacks()
{
	new id = bench_puppet("unarmed")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "unarmed_spawned", 20.0, "respawn")
}

public unarmed_spawned(id)
{
	// Kung fu, the flag and the katana have no ammo.
	ASSERT_EQ(ts_setuserammo(id, 0, 10), 0)
	ASSERT_EQ(ts_setuserammo(id, FLAG, 10), 0)
	ASSERT_EQ(ts_setuserammo(id, KATANA, 10), 0)
	ASSERT_EQ(ts_getuserammo(id, KATANA), 0)
	// A grenade or knife the player does not carry has no count to set.
	ASSERT_EQ(ts_getuserammo(id, SEALKNIFE), 0)
	ASSERT_EQ(ts_setuserammo(id, SEALKNIFE, 2), 0)
	ASSERT_EQ(ts_getuserammo(id, SEALKNIFE), 0)
	// A stack is at least one.
	ts_giveweapon(id, SEALKNIFE, 1, 0)
	ASSERT_EQ(ts_setuserammo(id, SEALKNIFE, 0), 0)
	ASSERT_EQ(ts_getuserammo(id, SEALKNIFE), 1)
	bench_pass()
}

public test_player_without_a_gun()
{
	// Not spawned yet: no weapon_tsgun.
	new id = bench_puppet("waiting")
	ASSERT(id > 0)
	bench_next("waiting_joined", 0.5, id)
}

public waiting_joined(id)
{
	ASSERT_FALSE(is_user_alive(id))
	ASSERT_EQ(ts_setuserammo(id, GLOCK18, 10), 0)
	ASSERT_EQ(ts_getuserammo(id, GLOCK18), 0)
	bench_pass()
}

public test_bad_weapon_id()
{
	new id = bench_puppet("typo")
	ASSERT(id > 0)
	// The error ends this function; the test passes in the next step.
	bench_next("refused", 0.0)
	bench_expect_error("Weapon 38 is not valid")
	ts_setuserammo(id, 38, 10)
}

public refused()
{
	bench_pass()
}

public test_negative_ammo()
{
	new id = bench_puppet("negative")
	ASSERT(id > 0)
	bench_next("refused", 0.0)
	bench_expect_error("Invalid ammo amount: -1")
	ts_setuserammo(id, GLOCK18, -1)
}
