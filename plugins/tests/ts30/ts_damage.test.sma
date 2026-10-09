// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the original The Specialists 3.0's damage debugging cvars and TSX's thrown-knife hits:
// damagemult scales bullets only, and only on a map started with sv_cheats 1; dmgreport (above 1,
// same cheat gate, and only where something registers the cvar) tells everyone in chat each
// bullet's damage, the flying bullets of slow motion included, and each thrown blade's; a thrown
// knife's hit reaches client_damage as its thrower's. TSHealth carries the health truncated, and
// no Health or Battery message goes out; a death turns the dead player's items off for everyone
// (ActItems) and sends him no CurWeapon. A bash during a reload lands and cuts the reload.
// ../ts_damage.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <xs>
#include <tsx>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1
#define DEAGLE		12
#define KNIFE		25

new g_Map[32]
new g_P[2]
new g_Hp[2]
new Float:g_Report[2]
new g_Reports
new g_Count
new g_FriendlyFire
new g_Knife
new g_HitAttacker
new g_HitWeapon

public plugin_init()
{
	register_plugin("TS Damage Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	get_mapname(g_Map, charsmax(g_Map))
	register_message(get_user_msgid("TSHealth"), "Shim_TSHealth")
	// The Specialists 3.0 reads dmgreport but never registers it (reTS does), so on the original it
	// is always 0 unless something else creates it. Creating it here lets the tests set it on both.
	register_cvar("dmgreport", "0")
}

public bench_setup()
{
	// Teamplay copies keep friendly fire off; the victims here may be the attacker's teammates.
	g_FriendlyFire = get_cvar_num("mp_friendlyfire")
	set_cvar_num("mp_friendlyfire", 1)
	g_Knife = 0
	g_HitAttacker = 0
	g_HitWeapon = 0
}

public bench_teardown()
{
	set_cvar_num("mp_friendlyfire", g_FriendlyFire)
	set_cvar_float("damagemult", 0.0)
	set_cvar_num("dmgreport", 0)
	set_cvar_num("sv_cheats", 0)
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "knife")))
		engfunc(EngFunc_RemoveEntity, ent)
}

FindClass(const classname[])
{
	return engfunc(EngFunc_FindEntityByString, -1, "classname", classname)
}

Health(id)
{
	new Float:hp
	pev(id, pev_health, hp)
	return floatround(hp)
}

new g_After[32]

// Holds buttons for a fifth of a second (one press of a single frame does not always fire), then
// calls step(id).
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

// Stands a dist units from b's bounds, facing b's middle.
bool:Face(a, b, Float:dist)
{
	if (!bench_puppet_face(a, b, dist))
		return false
	new Float:target[3]
	pev(b, pev_origin, target)
	bench_puppet_look_at(a, target)
	return true
}

// ---------------------------------------------------------------------------------------------
// The gun bash (cold cock) does its own damage whatever damagemult says.

public test_coldcock_ignores_damagemult()
{
	g_P[0] = bench_puppet("basher")
	g_P[1] = bench_puppet("bashed")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[1], "bash_victim", 20.0, "respawn")
}

public bash_victim(id)
{
	bench_puppet_spawn(g_P[0], "bash_spawned", 20.0, "respawn")
}

public bash_spawned(id)
{
	// The Desert Eagle is one of the guns with a bash.
	ts_giveweapon(id, DEAGLE, 0, 0)
	bench_next("bash_ready", 1.0, id)
}

Bash(const after[])
{
	ASSERT(Face(g_P[0], g_P[1], 20.0))
	set_pev(g_P[1], pev_health, 100.0)
	Hold(g_P[0], IN_CANCEL, after)
}

public bash_ready(id)
{
	Bash("bash_one")
}

public bash_one(id)
{
	bench_next("bash_one_landed", 0.1, id)
}

public bash_one_landed(id)
{
	g_Hp[0] = 100 - Health(g_P[1])
	ASSERT(g_Hp[0] > 0)
	set_cvar_float("damagemult", 2.0)
	bench_next("bash_again", 1.0, id)
}

public bash_again(id)
{
	Bash("bash_two")
}

public bash_two(id)
{
	bench_next("bash_two_landed", 0.1, id)
}

public bash_two_landed(id)
{
	g_Hp[1] = 100 - Health(g_P[1])
	ASSERT_EQ(g_Hp[1], g_Hp[0])
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// dmgreport, on a map started with sv_cheats 1: chat messages (TextMsg, print talk) to everyone.

// The last dmgreport line puppet id was sent with the given prefix, as its number; false if none.
bool:LastReport(id, const prefix[], &Float:value, &dest)
{
	new BenchMsg:msg = bench_msg_last(id, "TextMsg", prefix)
	if (msg == BenchMsg:0)
		return false
	new text[64]
	bench_msg_string(msg, 1, text, charsmax(text))
	new at = containi(text, prefix)
	if (at < 0)
		return false
	value = str_to_float(text[at + strlen(prefix)])
	dest = bench_msg_int(msg, 0)
	return true
}

public test_dmgreport_tells_bullets_and_blades()
{
	bench_set_timeout(120.0)
	set_cvar_num("sv_cheats", 1)
	set_cvar_num("dmgreport", 2)
	bench_change_map(g_Map, "report_map")
}

public report_map()
{
	g_P[0] = bench_puppet("reporter")
	g_P[1] = bench_puppet("reported")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[1], "report_victim", 20.0, "respawn")
}

public report_victim(id)
{
	bench_puppet_spawn(g_P[0], "report_spawned", 20.0, "respawn")
}

public report_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	bench_next("report_ready", 1.0, id)
}

// An instant bullet.
public report_ready(id)
{
	ASSERT(Face(g_P[0], g_P[1], 100.0))
	set_pev(g_P[1], pev_health, 500.0)
	Hold(g_P[0], IN_ATTACK, "report_fired")
}

public report_fired(id)
{
	bench_wait_message(g_P[1], "TextMsg", "damage:", "report_bullet", 2.0)
}

public report_bullet(id)
{
	new Float:value, dest
	ASSERT(LastReport(g_P[1], "damage:", value, dest))
	ASSERT_EQ(dest, print_chat)
	ASSERT(value > 0.0)
	// A thrown knife (from the other one, who holds nothing else): every touch reports the blade's
	// damage.
	ts_giveweapon(g_P[1], KNIFE, 1, 0)
	bench_next("report_knife_ready", 1.0, g_P[1])
}

public report_knife_ready(id)
{
	new Float:angles[3]
	angles[0] = -20.0
	bench_puppet_angles(id, angles)
	Hold(id, IN_ATTACK2, "report_thrown")
}

public report_thrown(id)
{
	bench_wait_message(g_P[0], "TextMsg", "(debug)", "report_blade", 4.0)
}

public report_blade(id)
{
	new Float:value, dest
	ASSERT(LastReport(g_P[0], "(debug)", value, dest))
	ASSERT_EQ(dest, print_chat)
	server_print("ts_damage: the knife reported %.1f", value)
	set_cvar_num("sv_cheats", 0)
	set_cvar_num("dmgreport", 0)
	bench_change_map(g_Map, "report_restored")
}

public report_restored()
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	bench_pass()
}

// A shooter in slow motion fires flying bullets; each one that hits is reported, and damagemult
// multiplies it.
public test_slow_motion_bullets_report_and_multiply()
{
	bench_set_timeout(120.0)
	set_cvar_num("sv_cheats", 1)
	set_cvar_num("dmgreport", 2)
	bench_change_map(g_Map, "slow_map")
}

public slow_map()
{
	g_P[0] = bench_puppet("slowshooter")
	g_P[1] = bench_puppet("slowtarget")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	g_Reports = 0
	bench_puppet_spawn(g_P[1], "slow_victim", 20.0, "respawn")
}

public slow_victim(id)
{
	bench_puppet_spawn(g_P[0], "slow_spawned", 20.0, "respawn")
}

public slow_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	ts_set_fakeslowmo(id, 20.0)
	// The gun comes out slower in slow motion; give it time.
	bench_next("slow_drawn", 1.5, id)
}

public slow_drawn(id)
{
	bench_wait_until("slowed", "slow_fire", 5.0, id)
}

public bool:slowed(id)
{
	new Float:slow
	pev(id, pev_fuser1, slow)
	return slow < 0.9
}

public slow_fire(id)
{
	ASSERT(Face(g_P[0], g_P[1], 100.0))
	set_pev(g_P[1], pev_health, 500.0)
	g_Count = bench_msg_count(g_P[1], "TextMsg", "damage:")
	Hold(g_P[0], IN_ATTACK, "slow_fired")
}

public slow_fired(id)
{
	bench_wait_until("slow_reported", "slow_report", 4.0, id)
}

public bool:slow_reported(id)
{
	return bench_msg_count(g_P[1], "TextMsg", "damage:") > g_Count
}

public slow_report(id)
{
	new dest
	ASSERT(LastReport(g_P[1], "damage:", g_Report[g_Reports], dest))
	ASSERT_EQ(dest, print_chat)
	if (++g_Reports == 1)
	{
		set_cvar_float("damagemult", 2.0)
		bench_next("slow_fire", 1.0, id)
		return
	}
	server_print("ts_damage: reported %.2f, then %.2f with damagemult 2", g_Report[0], g_Report[1])
	ASSERT(floatabs(g_Report[1] - 2.0 * g_Report[0]) < 0.01 * g_Report[0] + 0.01)
	set_cvar_num("sv_cheats", 0)
	set_cvar_num("dmgreport", 0)
	set_cvar_float("damagemult", 0.0)
	bench_change_map(g_Map, "slow_restored")
}

public slow_restored()
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// A thrown knife that hits a player: TSX credits its thrower, with the throwing knife's weapon id.

// The touch is forced, so the game's trace is not this hit; reTS then does the target no damage
// (TS 3.0 does), so this puts back the hit TSX reads.
public Shim_TSHealth(msgid, dest, id)
{
	if (!g_Knife || id != g_P[1] || !pev_valid(g_Knife))
		return PLUGIN_CONTINUE
	new Float:take
	pev(id, pev_dmg_take, take)
	if (take <= 0.0)
		set_pev(id, pev_dmg_take, 10.0)
	set_pev(id, pev_dmg_inflictor, g_Knife)
	return PLUGIN_CONTINUE
}

public client_damage(attacker, victim, damage, wpnindex, hitplace, TA)
{
	if (g_Knife && victim == g_P[1])
	{
		g_HitAttacker = attacker
		g_HitWeapon = wpnindex
	}
}

public test_thrown_knife_hit_is_the_throwers()
{
	g_P[0] = bench_puppet("knifethrower")
	g_P[1] = bench_puppet("knifetarget")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[1], "hit_victim", 20.0, "respawn")
}

public hit_victim(id)
{
	bench_puppet_spawn(g_P[0], "hit_spawned", 20.0, "respawn")
}

public hit_spawned(id)
{
	ts_giveweapon(id, KNIFE, 1, 0)
	new Float:angles[3]
	angles[0] = -20.0
	bench_puppet_angles(id, angles)
	bench_next("hit_ready", 1.0, id)
}

public hit_ready(id)
{
	Hold(id, IN_ATTACK2, "hit_thrown")
}

public hit_thrown(id)
{
	bench_wait_until("knife_out", "hit_touch", 2.0, id)
}

public bool:knife_out(id)
{
	return FindClass("knife") != 0
}

public hit_touch(id)
{
	g_Knife = FindClass("knife")
	set_pev(g_P[1], pev_health, 500.0)
	dllfunc(DLLFunc_Touch, g_Knife, g_P[1])
	bench_wait_until("hit_counted", "hit_check", 2.0, id)
}

public bool:hit_counted(id)
{
	return g_HitAttacker != 0
}

public hit_check(id)
{
	ASSERT_EQ(g_HitAttacker, g_P[0])
	ASSERT_EQ(g_HitWeapon, TSW_TKNIFE)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// TSHealth carries the health truncated, not rounded (CBasePlayer::UpdateClientData, 0x81fa2), and
// while the health has a fraction it goes out again at each update, since the game compares the
// health with the whole number it last sent. The game never sends the stock Health or Battery
// messages.

new g_TSHealths

public test_tshealth_is_the_health_truncated()
{
	g_P[0] = bench_puppet("healthy")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "tshealth_spawned", 20.0, "respawn")
}

public tshealth_spawned(id)
{
	bench_next("tshealth_set", 0.5, id)
}

public tshealth_set(id)
{
	set_pev(id, pev_health, 57.75)
	set_pev(id, pev_armorvalue, 20.0)
	g_TSHealths = bench_msg_count(id, "TSHealth")
	bench_next("tshealth_sent", 0.5, id)
}

public tshealth_sent(id)
{
	new BenchMsg:msg = bench_msg_last(id, "TSHealth")
	ASSERT(msg != BenchMsg:0)
	ASSERT_EQ(bench_msg_int(msg, 0), 57)
	ASSERT(bench_msg_count(id, "TSHealth") - g_TSHealths >= 2)
	ASSERT_EQ(bench_msg_count(id, "Health"), 0)
	ASSERT_EQ(bench_msg_count(id, "Battery"), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// When a player dies everyone is told to stop drawing his laser and flashlight (ActItems with his
// index and 0, CBasePlayer::Killed 0x7f434). The game sends him no CurWeapon marking him dead, as
// the stock SDK does.

public test_death_turns_his_items_off_for_everyone()
{
	g_P[0] = bench_puppet("watcher")
	g_P[1] = bench_puppet("dier")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[0], "death_watcher_up", 20.0, "respawn")
}

public death_watcher_up(id)
{
	bench_puppet_spawn(g_P[1], "death_dier_up", 20.0, "respawn")
}

public death_dier_up(id)
{
	bench_next("death_kill", 0.5, id)
}

public death_kill(id)
{
	set_pev(g_P[1], pev_health, 1.0)
	ExecuteHamB(Ham_TakeDamage, g_P[1], g_P[0], g_P[0], 10.0, DMG_BULLET)
	ASSERT_FALSE(is_user_alive(g_P[1]))
	bench_next("death_told", 0.3, id)
}

public death_told(id)
{
	new watcher = g_P[0], dier = g_P[1]
	// After the DeathMsg, everyone gets ActItems {dier, 0}.
	new BenchMsg:death = bench_msg_last(watcher, "DeathMsg")
	ASSERT(death != BenchMsg:0)
	new bool:off = false
	new BenchMsg:m = bench_msg_next(watcher, death, "ActItems")
	for (; m != BenchMsg:0; m = bench_msg_next(watcher, m, "ActItems"))
		if (bench_msg_int(m, 0) == dier && bench_msg_int(m, 1) == 0)
			off = true
	ASSERT(off)
	// And the dier no CurWeapon with the dead marker (an id of -1).
	death = bench_msg_last(dier, "DeathMsg")
	ASSERT(death != BenchMsg:0)
	m = bench_msg_next(dier, death, "CurWeapon")
	for (; m != BenchMsg:0; m = bench_msg_next(dier, m, "CurWeapon"))
	{
		new weapon = bench_msg_int(m, 1)
		ASSERT(weapon != -1 && weapon != 255)
	}
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The attack delay a reload sets lets a bash (+alt2) through for a weapon that has one
// (ItemPostFrame, 0xcc523): a Desert Eagle's bash 0.3 s into its 2.1 s reload lands, and cuts the
// reload (StopReload puts the attack delay back to now).
// The player's attack delay (+0x12c), as a fakemeta pdata offset (no Linux difference), in ts_i386.so.
#define PDATA_NEXTATTACK	(0x12c / 4)

public test_bash_cuts_a_reload()
{
	g_P[0] = bench_puppet("reloadbasher")
	g_P[1] = bench_puppet("reloadbashed")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[1], "rbash_victim", 20.0, "respawn")
}

public rbash_victim(id)
{
	bench_puppet_spawn(g_P[0], "rbash_spawned", 20.0, "respawn")
}

public rbash_spawned(id)
{
	ts_giveweapon(id, DEAGLE, 1, 0)
	bench_next("rbash_armed", 2.0, id)
}

public rbash_armed(id)
{
	// one shot at the floor, so the clip is not full
	new Float:angles[3] = {89.0, 0.0, 0.0}
	bench_puppet_angles(id, angles)
	Hold(id, IN_ATTACK, "rbash_fired")
}

public rbash_fired(id)
{
	bench_next("rbash_reload", 0.5, id)
}

public rbash_reload(id)
{
	Hold(id, IN_RELOAD, "rbash_reloading")
}

public rbash_reloading(id)
{
	// 0.2 s into the reload
	new Float:delay = get_pdata_float(id, PDATA_NEXTATTACK, 0, 0)
	server_print("ts_damage: attack delay 0.2 s into the reload %.2f", delay)
	ASSERT(delay > 1.0)
	ASSERT(Face(g_P[0], g_P[1], 20.0))
	set_pev(g_P[1], pev_health, 100.0)
	bench_next("rbash_bash", 0.1, id)
}

public rbash_bash(id)
{
	Hold(g_P[0], IN_CANCEL, "rbash_bashed")
}

public rbash_bashed(id)
{
	bench_next("rbash_landed", 0.1, id)
}

public rbash_landed(id)
{
	new Float:delay = get_pdata_float(g_P[0], PDATA_NEXTATTACK, 0, 0)
	g_Hp[0] = 100 - Health(g_P[1])
	server_print("ts_damage: bash 0.3 s into the reload took %d, attack delay after it %.2f", g_Hp[0], delay)
	ASSERT(g_Hp[0] > 0)
	ASSERT(delay < 1.0)
	bench_pass()
}
