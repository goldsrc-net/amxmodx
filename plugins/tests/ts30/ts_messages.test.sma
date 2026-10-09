// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for when The Specialists 3.0 sends its HUD messages. CTSGun::UpdateClientData
// (0x758c8) runs at most every 0.1 s; it sends WeaponInfo when the weapon's type or its caliber's
// reserve changes, not for its clip, fire mode or attachments (the client keeps those), and a
// WStatus per weapon slot when the player comes to own it or stops, so a newcomer with nothing but
// kung fu, whose slot is never owned, is sent none. TSArmor carries the armor truncated, and goes out while the armor differs from
// that whole number (0x82057). From a death until the player spectates two CurWeapon 0 0 0 go out,
// both from RemoveAllItems (PlayerDeathThink strips the dead player, 0x7ec15, then StartObserver),
// none with the stock SDK's dead marker, and the death clears the player's field of view (pev->fov,
// 0x7f48d). ActItems comes from the player's own update (0x823c7), with the akimbo tag 0x40 that
// CTSGun::GetActiveItems adds.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <tsx>
#include <tsfun>
#include <amxxbench>

#define GLOCK18		1

new g_P
new g_After[32]
new g_Count
new g_Reserve
new BenchMsg:g_Mark

public plugin_init()
{
	register_plugin("TS Message Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

// Holds buttons for a fifth of a second, then calls step(id).
Hold(id, buttons, const step[])
{
	copy(g_After, charsmax(g_After), step)
	bench_puppet_input(id, buttons)
	bench_next("Released", 0.2, id)
}

public Released(id)
{
	bench_puppet_input(id, 0)
	bench_next(g_After, 0.0, id)
}

new g_Ready[32]

// A puppet, alive, holding a Glock-18 with ammo in reserve, then step(id).
Armed(const name[], const step[])
{
	copy(g_Ready, charsmax(g_Ready), step)
	g_P = bench_puppet(name)
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "armed_spawned", 20.0, "respawn")
}

public armed_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 100, 0)
	bench_wait_until("holds_glock", "armed_holds", 3.0, id)
}

public bool:holds_glock(id)
{
	new BenchMsg:msg = bench_msg_last(id, "WeaponInfo")
	return msg != BenchMsg:0 && bench_msg_int(msg, 0) == GLOCK18
}

public armed_holds(id)
{
	// The gun is out a moment after it comes.
	bench_next(g_Ready, 1.0, id)
}

// --- WeaponInfo ------------------------------------------------------------------------------

// Shots change the clip, firemode the fire mode: no WeaponInfo for either (the shots land on a
// target, so they were fired). A change of the reserve sends one, with the new reserve.
new g_Target

public test_weapon_info_for_type_and_reserve_only()
{
	g_Target = bench_puppet("infotarget")
	ASSERT(g_Target > 0)
	bench_puppet_spawn(g_Target, "info_target_up", 20.0, "respawn")
}

public info_target_up(id)
{
	Armed("infoplayer", "info_ready")
}

public info_ready(id)
{
	ASSERT(bench_puppet_face(id, g_Target, 100.0))
	new Float:target[3]
	pev(g_Target, pev_origin, target)
	bench_puppet_look_at(id, target)
	set_pev(g_Target, pev_health, 500.0)
	g_Count = bench_msg_count(id, "WeaponInfo")
	Hold(id, IN_ATTACK, "info_fired")
}

public info_fired(id)
{
	bench_next("info_firemode", 0.5, id)
}

public info_firemode(id)
{
	new Float:hp
	pev(g_Target, pev_health, hp)
	ASSERT(hp < 500.0)
	bench_puppet_cmd(id, "firemode")
	bench_next("info_checked", 0.5, id)
}

public info_checked(id)
{
	ASSERT_EQ(bench_msg_count(id, "WeaponInfo"), g_Count)
	g_Reserve = ts_getuserammo(id, GLOCK18)
	ts_setuserammo(id, GLOCK18, g_Reserve - 10)
	bench_next("info_reserve", 0.5, id)
}

public info_reserve(id)
{
	ASSERT_EQ(bench_msg_count(id, "WeaponInfo"), g_Count + 1)
	ASSERT_EQ(bench_msg_int(bench_msg_last(id, "WeaponInfo"), 2), g_Reserve - 10)
	bench_pass()
}

// The update runs at most every 0.1 s: run twice in one frame (Ham_Item_UpdateClientData on the
// gun), each after a change of the reserve, it sends at most one of the two.
new g_Gun

public test_weapon_info_waits_a_tenth_of_a_second()
{
	Armed("throttleplayer", "throttle_ready")
}

public throttle_ready(id)
{
	g_Gun = -1
	while ((g_Gun = engfunc(EngFunc_FindEntityByString, g_Gun, "classname", "weapon_tsgun")) > 0)
		if (pev(g_Gun, pev_owner) == id)
			break
	ASSERT(g_Gun > 0)
	g_Reserve = ts_getuserammo(id, GLOCK18)
	ts_setuserammo(id, GLOCK18, g_Reserve - 5)
	ExecuteHamB(Ham_Item_UpdateClientData, g_Gun, id)
	ts_setuserammo(id, GLOCK18, g_Reserve - 6)
	ExecuteHamB(Ham_Item_UpdateClientData, g_Gun, id)
	bench_next("throttle_done", 0.5, id)
}

bool:SentReserve(id, reserve)
{
	for (new BenchMsg:m = bench_msg_next(id, BenchMsg:0, "WeaponInfo"); m != BenchMsg:0; m = bench_msg_next(id, m, "WeaponInfo"))
		if (bench_msg_int(m, 2) == reserve)
			return true
	return false
}

public throttle_done(id)
{
	ASSERT_FALSE(SentReserve(id, g_Reserve - 5) && SentReserve(id, g_Reserve - 6))
	// The reserve the gun was left with goes out at a later update.
	ASSERT(SentReserve(id, g_Reserve - 6))
	bench_pass()
}

// --- WStatus ---------------------------------------------------------------------------------

// A newcomer with nothing yet but his hands is sent no WStatus: kung fu's slot is not owned.
public test_newcomer_wstatus_only_for_what_he_holds()
{
	g_P = bench_puppet("newcomer")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "newcomer_spawned", 20.0, "respawn")
}

public newcomer_spawned(id)
{
	bench_next("newcomer_settled", 1.0, id)
}

public newcomer_settled(id)
{
	new count = 0
	for (new BenchMsg:m = bench_msg_next(id, BenchMsg:0, "WStatus"); m != BenchMsg:0; m = bench_msg_next(id, m, "WStatus"))
	{
		count++
		server_print("ts_messages: the newcomer's WStatus: %d %d %d", bench_msg_int(m, 0), bench_msg_int(m, 1), bench_msg_int(m, 2))
		if (bench_msg_int(m, 1) != 1)
		{
			bench_fail("a WStatus for weapon %d, which he does not own", bench_msg_int(m, 0))
			return
		}
	}
	server_print("ts_messages: the newcomer's WStatus messages: %d", count)
	ASSERT_EQ(count, 0)
	bench_pass()
}

// --- TSArmor ---------------------------------------------------------------------------------

// 57.75 armor goes out as 57, and again at every update while the armor is not a whole number.
public test_tsarmor_is_the_armor_truncated()
{
	g_P = bench_puppet("armored")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "armor_spawned", 20.0, "respawn")
}

public armor_spawned(id)
{
	set_pev(id, pev_armorvalue, 57.75)
	bench_next("armor_sent", 0.2, id)
}

public armor_sent(id)
{
	new BenchMsg:msg = bench_msg_last(id, "TSArmor")
	ASSERT(msg != BenchMsg:0)
	ASSERT_EQ(bench_msg_int(msg, 0), 57)
	g_Count = bench_msg_count(id, "TSArmor")
	bench_next("armor_again", 0.3, id)
}

public armor_again(id)
{
	ASSERT(bench_msg_count(id, "TSArmor") > g_Count)
	set_pev(id, pev_armorvalue, 40.0)
	bench_next("armor_whole", 0.2, id)
}

public armor_whole(id)
{
	ASSERT_EQ(bench_msg_int(bench_msg_last(id, "TSArmor"), 0), 40)
	g_Count = bench_msg_count(id, "TSArmor")
	bench_next("armor_quiet", 0.3, id)
}

public armor_quiet(id)
{
	ASSERT_EQ(bench_msg_count(id, "TSArmor"), g_Count)
	bench_pass()
}

// --- the death -------------------------------------------------------------------------------

// From his death until he spectates, the player is sent two CurWeapon 0 0 0, from the strip in
// PlayerDeathThink and from StartObserver's, and none with the stock SDK's dead marker (0, 255,
// 255); the death clears his field of view.
public test_death_to_spectating()
{
	bench_set_timeout(30.0)
	Armed("dier", "death_ready")
}

public death_ready(id)
{
	set_pev(id, pev_fov, 40.0)
	g_Mark = bench_msg_last(id)
	user_kill(id, 1)
	bench_wait_until("dead", "death_dead", 5.0, id)
}

public bool:dead(id)
{
	return !is_user_alive(id)
}

public death_dead(id)
{
	new Float:fov
	pev(id, pev_fov, fov)
	ASSERT(fov == 0.0)
	bench_wait_until("observing", "death_observing", 10.0, id)
}

public bool:observing(id)
{
	return pev(id, pev_iuser1) != 0
}

public death_observing(id)
{
	new count = 0
	for (new BenchMsg:m = bench_msg_next(id, g_Mark, "CurWeapon"); m != BenchMsg:0; m = bench_msg_next(id, m, "CurWeapon"))
	{
		count++
		server_print("ts_messages: CurWeapon %d %d %d", bench_msg_int(m, 0), bench_msg_int(m, 1), bench_msg_int(m, 2))
		ASSERT_EQ(bench_msg_int(m, 0), 0)
		ASSERT_EQ(bench_msg_int(m, 1), 0)
		ASSERT_EQ(bench_msg_int(m, 2), 0)
	}
	server_print("ts_messages: CurWeapon messages from the death to spectating: %d", count)
	ASSERT_EQ(count, 2)
	bench_pass()
}

// --- ActItems --------------------------------------------------------------------------------

#define BERETTA	2

// A second Beretta makes Akimbo Berettas. Everyone is told the player's active items: 0 while he
// joins (StartObserver; once more on a TS 3.0 teamplay server), then, with the pair out, the akimbo
// tag 0x40 alone (no attachment on), once, from his own update, which sends nothing while they stay
// the same.
public test_actitems_tags_akimbo()
{
	g_P = bench_puppet("twohands")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "twohands_spawned", 20.0, "respawn")
}

public twohands_spawned(id)
{
	ts_giveweapon(id, BERETTA, 30, 0)
	bench_next("twohands_second", 1.0, id)
}

public twohands_second(id)
{
	ts_giveweapon(id, BERETTA, 30, 0)
	bench_next("twohands_told", 2.0, id)
}

public twohands_told(id)
{
	new sent[8], count = 0, tagged = 0
	for (new BenchMsg:m = bench_msg_next(id, BenchMsg:0, "ActItems"); m != BenchMsg:0; m = bench_msg_next(id, m, "ActItems"))
	{
		if (bench_msg_int(m, 0) != id)
			continue
		server_print("ts_messages: ActItems %d %d", id, bench_msg_int(m, 1))
		if (count < sizeof(sent))
			sent[count] = bench_msg_int(m, 1)
		if (bench_msg_int(m, 1) == 0x40)
			tagged++
		count++
	}
	ASSERT(count >= 2 && count <= sizeof(sent))
	ASSERT_EQ(tagged, 1)
	ASSERT_EQ(sent[count - 1], 0x40)
	for (new i = 0; i < count - 1; i++)
		ASSERT_EQ(sent[i], 0)
	bench_pass()
}
