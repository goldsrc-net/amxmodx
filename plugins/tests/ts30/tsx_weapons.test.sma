// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the weapon ids TSX reports on the original The Specialists 3.0 game library: the
// game's own (kung fu 0, the Contender 36, the Akimbo Skorpions 37) in ts_getuserwpn, the kill
// and damage forwards and the stats, and 38 for a thrown knife, which the game has no id for.
// Kung fu's own stats sit in a slot of their own, as slot 0 of the stats holds every weapon's.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <tsstats>
#include <amxxbench>

#define GLOCK18		1
#define SKORPION	17
#define KNIFE		25

new g_Victim
new g_Weapon
new g_Buttons
new Float:g_Distance
new g_DeathWeapon
new g_DeathKiller
new g_DamageWeapon

public plugin_init()
{
	register_plugin("TSX Weapon Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_setup()
{
	g_Victim = 0
	g_DeathWeapon = -1
	g_DeathKiller = 0
	g_DamageWeapon = -1
}

public bench_teardown()
{
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "knife")))
		engfunc(EngFunc_RemoveEntity, ent)
}

public client_death(killer, victim, wpnindex, hitplace, TK)
{
	if (victim == g_Victim && g_Victim)
	{
		g_DeathKiller = killer
		g_DeathWeapon = wpnindex
	}
}

public client_damage(attacker, victim, damage, wpnindex, hitplace, TA)
{
	if (victim == g_Victim && g_Victim)
		g_DamageWeapon = wpnindex
}

// The weapon in the last WeaponInfo the game sent the player, or -1.
LastWeaponInfo(id)
{
	new BenchMsg:msg = bench_msg_last(id, "WeaponInfo")
	if (msg == BenchMsg:0)
		return -1
	return bench_msg_int(msg, 0)
}

public bool:holds_weapon(id)
{
	return LastWeaponInfo(id) == g_Weapon
}

// The stats slot named name, from 1 up (slot 0 holds every weapon's stats).
StatsSlot(const name[])
{
	new wname[32]
	for (new i = 1; i < xmod_get_maxweapons(); i++)
	{
		xmod_get_wpnname(i, wname, charsmax(wname))
		if (equal(wname, name))
			return i
	}
	return -1
}

WeaponName(weapon)
{
	new name[32]
	xmod_get_wpnname(weapon, name, charsmax(name))
	return name
}

// --- ts_getuserwpn ---------------------------------------------------------------------------

public test_kung_fu_is_weapon_0()
{
	new id = bench_puppet("fists")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "fists_spawned", 20.0, "respawn")
}

public fists_spawned(id)
{
	// A gun first, so the game has a change to tell when he puts it away.
	ts_giveweapon(id, GLOCK18, 0, 0)
	g_Weapon = GLOCK18
	bench_wait_until("holds_weapon", "fists_glock_out", 3.0, id)
}

public fists_glock_out(id)
{
	ASSERT_EQ(ts_getuserwpn(id), GLOCK18)
	bench_puppet_cmd(id, "weapon_0")
	g_Weapon = 0
	bench_wait_until("holds_weapon", "fists_out", 3.0, id)
}

public fists_out(id)
{
	ASSERT_EQ(TSW_KUNG_FU, 0)
	ASSERT_EQ(ts_getuserwpn(id), TSW_KUNG_FU)
	ASSERT_STR_EQ(WeaponName(TSW_KUNG_FU), "Kung Fu")
	ASSERT_EQ(xmod_is_melee_wpn(TSW_KUNG_FU), 1)
	ASSERT_EQ(ts_wpnlogtoid("kung_fu"), TSW_KUNG_FU)
	bench_pass()
}

public test_contender_is_weapon_36()
{
	g_Weapon = TSW_CONTENDER
	new id = bench_puppet("contender")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "gun_spawned", 20.0, "respawn")
}

public test_akimbo_skorpions_are_weapon_37()
{
	g_Weapon = TSW_ASKORPION
	new id = bench_puppet("skorpions")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "gun_spawned", 20.0, "respawn")
}

public gun_spawned(id)
{
	// The Akimbo Skorpions come from picking up a second Skorpion.
	if (g_Weapon == TSW_ASKORPION)
	{
		ts_giveweapon(id, SKORPION, 0, 0)
		bench_next("gun_second", 0.5, id)
		return
	}
	ts_giveweapon(id, g_Weapon, 0, 0)
	bench_wait_until("holds_weapon", "gun_out", 3.0, id)
}

public gun_second(id)
{
	ASSERT_EQ(LastWeaponInfo(id), SKORPION)
	ts_giveweapon(id, SKORPION, 0, 0)
	bench_wait_until("holds_weapon", "gun_out", 3.0, id)
}

public gun_out(id)
{
	new logname[32]
	ASSERT_EQ(ts_getuserwpn(id), g_Weapon)
	ASSERT_EQ(xmod_is_melee_wpn(g_Weapon), 0)
	xmod_get_wpnlogname(g_Weapon, logname, charsmax(logname))
	ASSERT_EQ(ts_wpnlogtoid(logname), g_Weapon)
	if (g_Weapon == TSW_CONTENDER)
	{
		ASSERT_EQ(TSW_CONTENDER, 36)
		ASSERT_STR_EQ(WeaponName(g_Weapon), "Contender G2")
		ASSERT_STR_EQ(logname, "contender_g2")
	}
	else
	{
		ASSERT_EQ(TSW_ASKORPION, 37)
		ASSERT_STR_EQ(WeaponName(g_Weapon), "Akimbo Skorpions")
		ASSERT_STR_EQ(logname, "akimbo_skorpions")
	}
	bench_pass()
}

// --- kills -----------------------------------------------------------------------------------
// The victim stands with 1 health; the killer is put in front of him, takes the weapon out and
// attacks until he dies.

public test_kung_fu_kill()
{
	g_Weapon = TSW_KUNG_FU
	g_Buttons = IN_ATTACK
	g_Distance = 24.0
	StartDuel()
}

public test_thrown_knife_kill()
{
	g_Weapon = KNIFE
	g_Buttons = IN_ATTACK2
	g_Distance = 100.0
	StartDuel()
}

public test_contender_kill()
{
	g_Weapon = TSW_CONTENDER
	g_Buttons = IN_ATTACK
	g_Distance = 150.0
	StartDuel()
}

StartDuel()
{
	new victim = bench_puppet("victim")
	ASSERT(victim > 0)
	bench_puppet_spawn(victim, "duel_victim_spawned", 20.0, "respawn")
}

public duel_victim_spawned(victim)
{
	g_Victim = victim
	new killer = bench_puppet("killer")
	ASSERT(killer > 0)
	bench_puppet_spawn(killer, "duel_killer_spawned", 20.0, "respawn")
}

public duel_killer_spawned(killer)
{
	// Kung fu: a gun first, then fists, so the game says so (a fresh player has had no WeaponInfo).
	if (g_Weapon == TSW_KUNG_FU)
		ts_giveweapon(killer, GLOCK18, 0, 0)
	else
		ts_giveweapon(killer, g_Weapon, 1, 0)
	bench_next("duel_armed", 1.0, killer)
}

public duel_armed(killer)
{
	if (g_Weapon == TSW_KUNG_FU)
	{
		ASSERT_EQ(LastWeaponInfo(killer), GLOCK18)
		bench_puppet_cmd(killer, "weapon_0")
		bench_wait_until("holds_weapon", "duel_ready", 3.0, killer)
		return
	}
	ASSERT_EQ(LastWeaponInfo(killer), g_Weapon)
	duel_ready(killer)
}

public duel_ready(killer)
{
	new Float:target[3]
	ASSERT(bench_puppet_face(killer, g_Victim, g_Distance))
	pev(g_Victim, pev_origin, target)
	bench_puppet_look_at(killer, target)
	set_pev(g_Victim, pev_health, 1.0)
	bench_next("duel_attack", 0.5, killer)
}

public duel_attack(killer)
{
	bench_puppet_input(killer, g_Buttons)
	bench_wait_until("victim_dead", "duel_over", 5.0, killer)
}

public bool:victim_dead(killer)
{
	return !is_user_alive(g_Victim)
}

public duel_over(killer)
{
	bench_puppet_input(killer, 0)
	bench_next("duel_counted", 0.3, killer)
}

public duel_counted(killer)
{
	new stats[STATSX_MAX_STATS], body[MAX_BODYHITS], weapon, slot, name[32], deathmsg[32]
	switch (g_Weapon)
	{
		case TSW_KUNG_FU:
		{
			weapon = TSW_KUNG_FU
			slot = StatsSlot("Kung Fu")
			copy(name, charsmax(name), "Kung Fu")
			copy(deathmsg, charsmax(deathmsg), "Kung Fu")
		}
		case KNIFE:
		{
			weapon = TSW_TKNIFE
			slot = TSW_TKNIFE
			copy(name, charsmax(name), "Throwing Knife")
			copy(deathmsg, charsmax(deathmsg), "Throwing Combat Knife")
		}
		default:
		{
			weapon = g_Weapon
			slot = g_Weapon
			copy(name, charsmax(name), "Contender G2")
			copy(deathmsg, charsmax(deathmsg), "Contender G2")
		}
	}
	// What the game itself names the weapon in its DeathMsg (a string, not an id).
	ASSERT_MSG(killer, "DeathMsg", deathmsg)
	ASSERT_EQ(g_DeathKiller, killer)
	ASSERT_EQ(g_DeathWeapon, weapon)
	ASSERT_EQ(g_DamageWeapon, weapon)
	ASSERT_STR_EQ(WeaponName(g_DeathWeapon), name)
	ASSERT(slot > 0)
	ASSERT_STR_EQ(WeaponName(slot), name)
	// The killer's stats against the victim name the weapon of the kill.
	new vname[32]
	ASSERT_EQ(get_user_vstats(killer, g_Victim, stats, body, vname, charsmax(vname)), 1)
	ASSERT_STR_EQ(vname, name)
	ASSERT_EQ(stats[STATSX_DEATHS], 1)
	// Per weapon. A gun's stats only show once he has shots, which TSX counts from ClipInfo, a
	// message TS 3.0 never sends; kung fu and the knife count a shot for each hit.
	if (g_Weapon != TSW_CONTENDER)
	{
		ASSERT_EQ(get_user_wstats(killer, slot, stats, body), 1)
		ASSERT_EQ(stats[STATSX_KILLS], 1)
		ASSERT_EQ(get_user_wstats(killer, 0, stats, body), 1)
		ASSERT_EQ(stats[STATSX_KILLS], 1)
	}
	bench_pass()
}
