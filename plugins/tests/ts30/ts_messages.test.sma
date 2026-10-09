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
// CTSGun::GetActiveItems adds. InitHUD sends a joiner the four server settings once, and the team
// roster only in his InitHUD frame; after it his HUD values go out only on a change (no slow motion,
// award, health, armor or cash again after his second ResetHUD), with no WeaponList and no room type.
// A spawn sends health, armor and cash once each.
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
	RecordHooks()
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

// The strips leave a spectator no weapon bits at all, the suit's included: PlayerDeathThink and
// StartObserver both call RemoveAllItems(1) (0x7ec15, 0x89986), and RemoveAllItems keeps none then.
public test_death_leaves_no_weapon_bits()
{
	bench_set_timeout(30.0)
	Armed("bitless", "bitless_ready")
}

public bitless_ready(id)
{
	ASSERT(pev(id, pev_weapons) != 0)
	user_kill(id, 1)
	bench_wait_until("observing", "bitless_observing", 15.0, id)
}

public bitless_observing(id)
{
	server_print("ts_messages: weapons spectating after a death %x", pev(id, pev_weapons))
	ASSERT_EQ(pev(id, pev_weapons), 0)
	bench_pass()
}

// A spawn strips nothing (PlayerSpawn 0x790ac): spawning a player who holds his guns sends no
// CurWeapon 0 0 0, and he keeps the Glock-18.
public test_spawn_while_armed_strips_nothing()
{
	bench_set_timeout(30.0)
	Armed("respawned", "respawned_ready")
}

public respawned_ready(id)
{
	g_Mark = bench_msg_last(id)
	dllfunc(DLLFunc_Spawn, id)
	bench_next("respawned_after", 1.0, id)
}

public respawned_after(id)
{
	new count = 0
	for (new BenchMsg:m = bench_msg_next(id, g_Mark, "CurWeapon"); m != BenchMsg:0; m = bench_msg_next(id, m, "CurWeapon"))
	{
		server_print("ts_messages: CurWeapon after the spawn %d %d %d", bench_msg_int(m, 0), bench_msg_int(m, 1), bench_msg_int(m, 2))
		if (!bench_msg_int(m, 0) && !bench_msg_int(m, 1) && !bench_msg_int(m, 2))
			count++
	}
	ASSERT(is_user_alive(id))
	ASSERT_EQ(count, 0)
	new clip, ammo, mode, extra
	new weapon = ts_getuserwpn(id, clip, ammo, mode, extra)
	server_print("ts_messages: after the spawn he holds %d", weapon)
	ASSERT_EQ(weapon, GLOCK18)
	bench_pass()
}

// No SetFOV goes out from a spawn: the original sends SetFOV only from Killed and StartObserver
// (CBasePlayer::UpdateClientData has none), so after his last ResetHUD the new player gets none.
public test_spawn_sends_no_setfov()
{
	g_P = bench_puppet("fovless")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "fovless_spawned", 20.0, "respawn")
}

public fovless_spawned(id)
{
	bench_next("fovless_later", 1.0, id)
}

public fovless_later(id)
{
	new BenchMsg:reset = bench_msg_last(id, "ResetHUD")
	ASSERT(reset != BenchMsg:0)
	new count = 0
	for (new BenchMsg:m = bench_msg_next(id, reset, "SetFOV"); m != BenchMsg:0; m = bench_msg_next(id, m, "SetFOV"))
		count++
	ASSERT_EQ(count, 0)
	bench_pass()
}

// StartObserver tells everyone the player has no active items (ActItems 0, 0x897b4), before its
// SetFOV: a joiner gets one from InitHUD's StartObserver and, on a teamplay server, one more from
// the team change that puts him on a team (StartObserver alone).
public test_joiner_told_no_active_items_at_each_start_observer()
{
	g_P = bench_puppet("watched")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "watched_spawned", 20.0, "respawn")
}

public watched_spawned(id)
{
	new zeros = 0, fovs = 0, bool:first = true
	for (new BenchMsg:m = bench_msg_next(id); m != BenchMsg:0; m = bench_msg_next(id, m))
	{
		new name[32]
		bench_msg_name(m, name, charsmax(name))
		if (equal(name, "SetFOV"))
		{
			fovs++
			continue
		}
		if (!equal(name, "ActItems") || bench_msg_int(m, 0) != id)
			continue
		// each one comes before the SetFOV of its StartObserver
		if (first)
			ASSERT_EQ(fovs, 0)
		first = false
		ASSERT_EQ(bench_msg_int(m, 1), 0)
		zeros++
	}
	server_print("ts_messages: joiner ActItems 0: %d, SetFOV %d, teamplay %d", zeros, fovs, get_cvar_num("mp_teamplay"))
	ASSERT_EQ(zeros, get_cvar_num("mp_teamplay") ? 2 : 1)
	bench_pass()
}

// --- ActItems --------------------------------------------------------------------------------

#define BERETTA	2

// A second Beretta makes Akimbo Berettas. Everyone is told the player's active items: 0 while he
// joins (StartObserver; once more on a teamplay server), then, with the pair out, the akimbo
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

// --- spectating ------------------------------------------------------------------------------

// StartObserver strips with RemoveAllItems(1) (0x89983), so a joiner who has not yet pressed fire
// spectates with no weapon bits, the suit's included.
public test_joiner_spectates_without_weapon_bits()
{
	g_P = bench_puppet("suitless")
	ASSERT(g_P > 0)
	bench_wait_until("observing", "suitless_observing", 10.0, g_P)
}

public suitless_observing(id)
{
	server_print("ts_messages: weapons of a spectating joiner %x", pev(id, pev_weapons))
	ASSERT_EQ(pev(id, pev_weapons), 0)
	bench_pass()
}

// StartObserver ends by telling everyone the player spectates (Spectator {idx, 1}, 0x899c2), right
// after its strip (RemoveAllItems' CurWeapon 0 0 0): each of a joiner's StartObservers (InitHUD's,
// and on a teamplay server the team change's) is closed so.
public test_joiner_told_he_spectates_at_each_start_observer()
{
	g_P = bench_puppet("spectating")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "spectating_spawned", 20.0, "respawn")
}

public spectating_spawned(id)
{
	new starts = 0, closed = 0, bool:open = false, bool:stripped = false
	for (new BenchMsg:m = bench_msg_next(id); m != BenchMsg:0; m = bench_msg_next(id, m))
	{
		new name[32]
		bench_msg_name(m, name, charsmax(name))
		new args = bench_msg_args(m)
		if (stripped)
		{
			// the message right after the strip
			if (equal(name, "Spectator") && bench_msg_int(m, 0) == id && bench_msg_int(m, 1) == 1)
				closed++
			stripped = false
			open = false
		}
		if (equal(name, "ActItems") && bench_msg_int(m, 0) == id && bench_msg_int(m, 1) == 0)
		{
			starts++
			open = true
		}
		else if (open && equal(name, "CurWeapon") && args == 3 && !bench_msg_int(m, 0)
			&& !bench_msg_int(m, 1) && !bench_msg_int(m, 2))
			stripped = true
		else if (equal(name, "ResetHUD") && starts > 0)
			break // his spawn
	}
	server_print("ts_messages: joiner StartObservers %d, closed by Spectator %d, teamplay %d", starts, closed,
		get_cvar_num("mp_teamplay"))
	ASSERT_EQ(starts, get_cvar_num("mp_teamplay") ? 2 : 1)
	ASSERT_EQ(closed, starts)
	bench_pass()
}

// --- server settings -------------------------------------------------------------------------

// Think's SrvSett (0x675b3): realbullet and usecash go out when the cached whole number, as a float,
// differs from the cvar, and the number cached and sent is the value chopped toward zero, so a
// fractional value goes out every frame as its whole part (usecash as a bool). ammocount is chopped
// first and compared as a whole number, so it goes out once.
new Float:g_Bullet, Float:g_Cash, Float:g_Ammo

public test_server_settings_truncate()
{
	g_P = bench_puppet("settings")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "settings_spawned", 20.0, "respawn")
}

public settings_spawned(id)
{
	g_Bullet = get_cvar_float("realbullet")
	g_Cash = get_cvar_float("usecash")
	g_Ammo = get_cvar_float("ammocount")
	g_Mark = bench_msg_last(id)
	set_cvar_float("realbullet", 0.5)
	set_cvar_float("usecash", 0.5)
	set_cvar_float("ammocount", g_Ammo + 2.7)
	bench_next("settings_sent", 0.5, id)
}

public settings_sent(id)
{
	set_cvar_float("realbullet", g_Bullet)
	set_cvar_float("usecash", g_Cash)
	set_cvar_float("ammocount", g_Ammo)
	new count[3], last[3]
	for (new BenchMsg:m = bench_msg_next(id, g_Mark, "SrvSett"); m != BenchMsg:0; m = bench_msg_next(id, m, "SrvSett"))
	{
		new which = bench_msg_int(m, 0)
		if (which < 0 || which > 2)
			continue
		count[which]++
		last[which] = bench_msg_int(m, 1)
	}
	server_print("ts_messages: SrvSett realbullet %d x %d, usecash %d x %d, ammocount %d x %d",
		count[0], last[0], count[1], last[1], count[2], last[2])
	ASSERT(count[0] >= 3)
	ASSERT_EQ(last[0], 0)
	ASSERT(count[1] >= 3)
	ASSERT_EQ(last[1], 0)
	ASSERT_EQ(count[2], 1)
	ASSERT_EQ(last[2], floatround(g_Ammo, floatround_tozero) + 2)
	bench_next("settings_restored", 0.5, id)
}

public settings_restored(id)
{
	bench_pass()
}

// InitHUD sends a joiner the four server settings once (0x691fe to 0x69316), and nothing sends them
// again while he waits to play.
public test_joiner_told_the_server_settings_once()
{
	g_P = bench_puppet("settled")
	ASSERT(g_P > 0)
	bench_wait_until("observing", "settled_observing", 10.0, g_P)
}

public settled_observing(id)
{
	// Well past the 0.75 s a resend would wait.
	bench_next("settled_waited", 1.5, id)
}

public settled_waited(id)
{
	new count[4]
	for (new BenchMsg:m = bench_msg_next(id, BenchMsg:0, "SrvSett"); m != BenchMsg:0; m = bench_msg_next(id, m, "SrvSett"))
	{
		new which = bench_msg_int(m, 0)
		if (which >= 0 && which <= 3)
			count[which]++
	}
	server_print("ts_messages: joiner SrvSett realbullet %d, usecash %d, ammocount %d, weaponrestriction %d",
		count[0], count[1], count[2], count[3])
	for (new i = 0; i < 4; i++)
		ASSERT_EQ(count[i], 1)
	bench_pass()
}

// --- The join stream ------------------------------------------------------------------------

// Every message begun while g_Rec is set: its type, destination, target, game time and first
// integer argument (-1 for none), from fakemeta's MessageBegin and Write* hooks, so the engine's
// own svc messages (the room type, 37) are seen too.
#define MAX_REC	1024
#define SVC_ROOMTYPE	37

new bool:g_Rec
new g_RecCount
new g_RType[MAX_REC]
new g_RDest[MAX_REC]
new g_REnt[MAX_REC]
new Float:g_RTime[MAX_REC]
new g_RArg0[MAX_REC]
new g_RArg1[MAX_REC]
new g_RArgs[MAX_REC]
new g_RStr[MAX_REC][24]
new bool:g_RInMsg
new Float:g_Spawned
new Float:g_RespawnTime

RecordHooks()
{
	register_forward(FM_MessageBegin, "rec_begin")
	register_forward(FM_WriteByte, "rec_int")
	register_forward(FM_WriteChar, "rec_int")
	register_forward(FM_WriteShort, "rec_int")
	register_forward(FM_WriteLong, "rec_int")
	register_forward(FM_WriteString, "rec_string")
	register_forward(FM_MessageEnd, "rec_end")
}

public bench_teardown()
{
	g_Rec = false
	if (g_RespawnTime > 0.0)
	{
		set_cvar_float("respawntime", g_RespawnTime)
		g_RespawnTime = 0.0
	}
}

Record()
{
	g_RecCount = 0
	g_RInMsg = false
	g_Rec = true
}

public rec_begin(dest, type, const Float:origin[3], ed)
{
	if (!g_Rec || g_RecCount >= MAX_REC)
		return FMRES_IGNORED
	g_RType[g_RecCount] = type
	g_RDest[g_RecCount] = dest
	g_REnt[g_RecCount] = ed
	g_RTime[g_RecCount] = get_gametime()
	g_RArg0[g_RecCount] = -1
	g_RArg1[g_RecCount] = -1
	g_RArgs[g_RecCount] = 0
	g_RStr[g_RecCount][0] = 0
	g_RInMsg = true
	return FMRES_IGNORED
}

public rec_int(value)
{
	if (g_Rec && g_RInMsg)
	{
		if (g_RArgs[g_RecCount] == 0)
			g_RArg0[g_RecCount] = value
		else if (g_RArgs[g_RecCount] == 1)
			g_RArg1[g_RecCount] = value
		g_RArgs[g_RecCount]++
	}
	return FMRES_IGNORED
}

public rec_string(const value[])
{
	if (g_Rec && g_RInMsg && !g_RStr[g_RecCount][0])
		copy(g_RStr[g_RecCount], charsmax(g_RStr[]), value)
	return FMRES_IGNORED
}

public rec_end()
{
	if (g_Rec && g_RInMsg)
		g_RecCount++
	g_RInMsg = false
	return FMRES_IGNORED
}

// Whether recorded message i reaches player id: sent to him alone or to everyone.
bool:Reaches(i, id)
{
	if (g_RDest[i] == MSG_ONE || g_RDest[i] == MSG_ONE_UNRELIABLE)
		return g_REnt[i] == id
	return g_RDest[i] == MSG_ALL || g_RDest[i] == MSG_BROADCAST
}

// The game time of the joiner's InitHUD, or -1.0 if none was recorded.
Float:InitHUDTime(id)
{
	new initHUD = get_user_msgid("InitHUD")
	for (new i = 0; i < g_RecCount; i++)
		if (g_RType[i] == initHUD && Reaches(i, id))
			return g_RTime[i]
	return -1.0
}

// How many recorded messages of type reach id after the time "after" (pass -1 as player to count
// those whose first argument is any player, else only his).
CountAfter(id, type, Float:after, player = -1)
{
	new count = 0
	for (new i = 0; i < g_RecCount; i++)
	{
		if (g_RType[i] != type || !Reaches(i, id) || g_RTime[i] <= after)
			continue
		if (player != -1 && g_RArg0[i] != player)
			continue
		count++
	}
	return count
}

// A joiner gets the team roster (GameMode, TeamNames, TeamInfo) only from his InitHUD frame:
// CHalfLifeTeamplay::InitHUD, ChangePlayerTeam and StartObserver (0xd45d8, 0xd488c), and nothing
// sends it again while he waits to play, on a teamplay server or not.
public test_joiner_told_the_team_roster_only_at_his_inithud()
{
	bench_set_timeout(20.0)
	Record()
	g_P = bench_puppet("rostered")
	ASSERT(g_P > 0)
	bench_wait_until("observing", "rostered_observing", 10.0, g_P)
}

public rostered_observing(id)
{
	// Past the 0.75 s a joiner's resend would wait, and a 3 s rebroadcast to everyone.
	bench_next("rostered_waited", 3.5, id)
}

public rostered_waited(id)
{
	g_Rec = false
	new Float:at = InitHUDTime(id)
	ASSERT(at > 0.0)
	new mode = get_user_msgid("GameMode"), names = get_user_msgid("TeamNames"), info = get_user_msgid("TeamInfo")
	new modes = CountAfter(id, mode, -1.0), later = CountAfter(id, mode, at)
	new nameCount = CountAfter(id, names, -1.0), namesLater = CountAfter(id, names, at)
	new infoLater = CountAfter(id, info, at, id)
	server_print("ts_messages: joiner roster, teamplay %d: GameMode %d (%d later), TeamNames %d (%d later), his TeamInfo later %d",
		get_cvar_num("mp_teamplay"), modes, later, nameCount, namesLater, infoLater)
	ASSERT_EQ(modes, 1)
	ASSERT_EQ(later, 0)
	ASSERT_EQ(namesLater, 0)
	ASSERT_EQ(infoLater, 0)
	bench_pass()
}

// After his InitHUD frame a waiting joiner's HUD values go out only when they change: no slow
// motion or award re-send (UpdateClientData 0x822f9, 0x8245d send on a change), no health, armor or
// cash after his second ResetHUD (that block of UpdateClientData, 0x81d57, clears no cache). The
// original never sends WeaponList (only LinkUserMessages uses it), and the room type goes out only
// from an env_sound (0xd0003), none of which reaches him here.
public test_joiner_hud_not_sent_again()
{
	bench_set_timeout(20.0)
	Record()
	g_P = bench_puppet("hudjoiner")
	ASSERT(g_P > 0)
	bench_wait_until("observing", "hudjoiner_observing", 10.0, g_P)
}

public hudjoiner_observing(id)
{
	bench_next("hudjoiner_waited", 1.5, id)
}

public hudjoiner_waited(id)
{
	g_Rec = false
	new Float:at = InitHUDTime(id)
	ASSERT(at > 0.0)
	new health = CountAfter(id, get_user_msgid("TSHealth"), at)
	new armor = CountAfter(id, get_user_msgid("TSArmor"), at)
	new cash = CountAfter(id, get_user_msgid("TSCash"), at)
	new slow = CountAfter(id, get_user_msgid("TSSlowMo"), at)
	new award = CountAfter(id, get_user_msgid("TSPAward"), at, id)
	new list = CountAfter(id, get_user_msgid("WeaponList"), -1.0)
	new room = CountAfter(id, SVC_ROOMTYPE, -1.0)
	new resets = CountAfter(id, get_user_msgid("ResetHUD"), at)
	server_print("ts_messages: after the joiner's InitHUD (%d more ResetHUD): TSHealth %d, TSArmor %d, TSCash %d, TSSlowMo %d, TSPAward %d; WeaponList %d, room type %d",
		resets, health, armor, cash, slow, award, list, room)
	ASSERT(resets >= 1)
	ASSERT_EQ(health, 0)
	ASSERT_EQ(armor, 0)
	ASSERT_EQ(cash, 0)
	ASSERT_EQ(slow, 0)
	ASSERT_EQ(award, 0)
	ASSERT_EQ(list, 0)
	ASSERT_EQ(room, 0)
	bench_pass()
}

// Spawning sends health, armor and cash once each after the spawn's ResetHUD: TSInit clears the
// health and cash caches (0x82ac9, 0x82b02) and Spawn the armor's (0x7f9a0). No room type.
public test_spawn_sends_health_armor_and_cash_once()
{
	bench_set_timeout(30.0)
	Record()
	g_P = bench_puppet("hudspawner")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "hudspawner_spawned", 20.0, "respawn")
}

public hudspawner_spawned(id)
{
	g_Spawned = get_gametime()
	bench_next("hudspawner_settled", 0.5, id)
}

public hudspawner_settled(id)
{
	g_Rec = false
	// The last ResetHUD before the spawn was seen: the spawn's.
	new reset = get_user_msgid("ResetHUD"), Float:at = -1.0
	for (new i = 0; i < g_RecCount; i++)
		if (g_RType[i] == reset && Reaches(i, id) && g_RTime[i] <= g_Spawned)
			at = g_RTime[i]
	ASSERT(at > 0.0)
	// Messages of the ResetHUD's own frame count: go back a hair.
	at -= 0.0001
	new health = CountAfter(id, get_user_msgid("TSHealth"), at)
	new armor = CountAfter(id, get_user_msgid("TSArmor"), at)
	new cash = CountAfter(id, get_user_msgid("TSCash"), at)
	new room = CountAfter(id, SVC_ROOMTYPE, at)
	server_print("ts_messages: from the spawn's ResetHUD: TSHealth %d, TSArmor %d, TSCash %d, room type %d",
		health, armor, cash, room)
	ASSERT_EQ(health, 1)
	ASSERT_EQ(armor, 1)
	ASSERT_EQ(cash, 1)
	ASSERT_EQ(room, 0)
	bench_pass()
}

// A joiner, alive since ClientPutInServer's Spawn, is holstered by his InitHUD frame's StartObserver:
// with the gun in hand Reset and HolsterWeapon, then the gun's Holster(0), HolsterWeapon again
// (0x8970f-0x89755). Each sends the kung fu draw with skiplocal 0, so two svc_weaponanim (35) reach
// him in that frame even though he predicts his weapons (cl_lw 1).
#define SVC_WEAPONANIM	35

public test_joiner_holstered_twice_at_his_start_observer()
{
	bench_set_timeout(20.0)
	Record()
	g_P = bench_puppet("holstered")
	ASSERT(g_P > 0)
	bench_wait_until("observing", "holstered_observing", 10.0, g_P)
}

public holstered_observing(id)
{
	g_Rec = false
	new Float:at = InitHUDTime(id)
	ASSERT(at > 0.0)
	new anims = 0, first = -1
	for (new i = 0; i < g_RecCount; i++)
	{
		if (g_RType[i] != SVC_WEAPONANIM || !Reaches(i, id) || g_RTime[i] != at)
			continue
		if (first == -1)
			first = g_RArg0[i]
		anims++
	}
	server_print("ts_messages: svc_weaponanim to the joiner in his InitHUD frame: %d (first sequence %d)", anims, first)
	ASSERT_EQ(anims, 2)
	ASSERT_EQ(first, 1)
	bench_pass()
}

// UpdateClientData sends Train after TSArmor and before TSState (0x820f7-0x82146): on a spawn, whose
// update sends all three, in that order.
public test_spawn_sends_train_after_armor()
{
	bench_set_timeout(30.0)
	Record()
	g_P = bench_puppet("trainspawner")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "trainspawner_spawned", 20.0, "respawn")
}

public trainspawner_spawned(id)
{
	g_Spawned = get_gametime()
	bench_next("trainspawner_settled", 0.5, id)
}

public trainspawner_settled(id)
{
	g_Rec = false
	new reset = get_user_msgid("ResetHUD"), Float:at = -1.0
	for (new i = 0; i < g_RecCount; i++)
		if (g_RType[i] == reset && Reaches(i, id) && g_RTime[i] <= g_Spawned)
			at = g_RTime[i]
	ASSERT(at > 0.0)
	new armor = get_user_msgid("TSArmor"), train = get_user_msgid("Train"), posture = get_user_msgid("TSState")
	new iArmor = -1, iTrain = -1, iState = -1
	for (new i = 0; i < g_RecCount; i++)
	{
		if (!Reaches(i, id) || g_RTime[i] != at)
			continue
		if (g_RType[i] == armor && iArmor == -1)
			iArmor = i
		else if (g_RType[i] == train && iTrain == -1)
			iTrain = i
		else if (g_RType[i] == posture && iState == -1)
			iState = i
	}
	server_print("ts_messages: spawn update order: TSArmor %d, Train %d, TSState %d", iArmor, iTrain, iState)
	ASSERT(iArmor >= 0)
	ASSERT(iTrain > iArmor)
	ASSERT(iState > iTrain)
	bench_pass()
}

// A joiner's respawn countdown (PreThink's spectate block, 0x80e83-0x80fab) starts in his InitHUD
// frame: UpdateClientData runs near the top of PreThink, so the StartObserver it calls is followed
// by the frame's first line. Once a second it shows the seconds to the gate truncated, and "Press
// Fire To Play!" when that truncates to 0, in the last second before the gate; nothing once the gate
// has passed. With respawntime 5 that is four numbers (5 3 2 1, or 4 3 2 1 when the gate's float
// rounds down), then the prompt.
public test_joiner_countdown_as_the_original()
{
	bench_set_timeout(30.0)
	g_RespawnTime = get_cvar_float("respawntime")
	set_cvar_float("respawntime", 5.0)
	Record()
	g_P = bench_puppet("counted")
	ASSERT(g_P > 0)
	bench_wait_until("observing", "counted_observing", 10.0, g_P)
}

public counted_observing(id)
{
	// past the 5 s gate by 3 s, never pressing to play
	bench_next("counted_waited", 8.0, id)
}

public counted_waited(id)
{
	g_Rec = false
	set_cvar_float("respawntime", g_RespawnTime)
	new Float:at = InitHUDTime(id)
	ASSERT(at > 0.0)
	new msg = get_user_msgid("TSMessage")
	new lines = 0, numbers = 0, prompts = 0, bool:afterPrompt = false, Float:first = -1.0
	new seq[64], len = 0
	for (new i = 0; i < g_RecCount; i++)
	{
		if (g_RType[i] != msg || !Reaches(i, id))
			continue
		if (first < 0.0)
			first = g_RTime[i]
		lines++
		if (prompts > 0)
			afterPrompt = true
		if (equal(g_RStr[i], "Press Fire To Play!"))
			prompts++
		else if (str_to_num(g_RStr[i]) > 0)
			numbers++
		len += formatex(seq[len], charsmax(seq) - len, "%s%s", len ? "," : "", g_RStr[i])
	}
	server_print("ts_messages: joiner countdown %s (first line %.4f, InitHUD %.4f)", seq, first, at)
	ASSERT(first == at)
	ASSERT_EQ(numbers, 4)
	ASSERT_EQ(prompts, 1)
	ASSERT_FALSE(afterPrompt)
	ASSERT_EQ(lines, 5)
	bench_pass()
}

// TSFade divides the 4.12 duration and hold by the recipient's slow-motion rate and truncates
// (UTIL_ScreenFadeWrite 0xdccbf, 0xdccfb: fidivr, fistp with the rounding set to chop): a 1 s fade to
// a player at rate 0.6 is 4096 / 0.6 = 6826.67, sent as 6826.
public test_tsfade_truncates_the_slowed_time()
{
	bench_set_timeout(20.0)
	g_P = bench_puppet("faded")
	ASSERT(g_P > 0)
	bench_wait_until("observing", "faded_observing", 10.0, g_P)
}

public faded_observing(id)
{
	new fade = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "env_fade"))
	ASSERT(fade > 0)
	set_pev(fade, pev_spawnflags, 4) // SF_FADE_ONLYONE: the activator alone
	dllfunc(DLLFunc_Spawn, fade)
	set_pev(fade, pev_dmg_take, 1.0) // Duration()
	set_pev(fade, pev_dmg_save, 1.0) // HoldTime()
	set_pev(fade, pev_renderamt, 255.0)
	set_pev(id, pev_fuser1, 0.6)
	Record()
	dllfunc(DLLFunc_Use, fade, id)
	g_Rec = false
	engfunc(EngFunc_RemoveEntity, fade)
	new tsfade = get_user_msgid("TSFade"), duration = -1, hold = -1
	for (new i = 0; i < g_RecCount; i++)
		if (g_RType[i] == tsfade && Reaches(i, id))
		{
			duration = g_RArg0[i]
			hold = g_RArg1[i]
		}
	server_print("ts_messages: 1 s fade at slow 0.6: duration %d, hold %d", duration, hold)
	ASSERT_EQ(duration, 6826)
	ASSERT_EQ(hold, 6826)
	bench_pass()
}
