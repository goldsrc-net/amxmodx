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
// Kills made in a dive are scored as the game scores them (TSGetPointsForFrag): a point more and
// the stunt flag, the weapon still the one that killed.
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
#define TS_DIVE		0x10	// pev->iuser4 while the game's dive lasts (CTSStunt::GoDive)
// CBasePlayer (TS 3.0 Linux): how long a missed knife or katana slash, or a kung fu blow, stays
// ready to land on whoever the player's stunt runs into (CTSStunt::CheckForBreakables), and which
// it was (0 kung fu, 1 knife, 2 katana). KatanaFire sets them only when the slash hits nothing
// (0x73a6d-0x73a97).
#define PDATA_CLOSECOMBAT	(0x79c / 4)
#define PDATA_CLOSECOMBAT_TYPE	0x7a4
// A katana slash from 105 to 125 units away misses, and the dive is on the victim within 0.25 s.
#define SHOVE_NEAR	105.0
#define SHOVE_FAR	125.0

new g_Victim
new g_Weapon
new g_Buttons
new Float:g_Distance
new g_DeathWeapon
new g_DeathKiller
new g_DamageWeapon
new bool:g_Dive
new g_DiveFrame
new g_DeathStunt
new bool:g_Shove
new g_Slashes
new bool:g_Armed

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
	g_Dive = false
	g_DeathStunt = 0
	g_Shove = false
	g_Slashes = 0
	g_Armed = false
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
		// The killer's stunt bits at the kill.
		g_DeathStunt = pev(killer, pev_iuser4)
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

// A player who joins in the slot of one who left holds kung fu until he draws something: the game
// sends him no WeaponInfo before that, so nothing of the last player's may carry over.
new g_Slot
new g_WeaponInfos

public test_newcomer_does_not_hold_the_last_players_gun()
{
	new id = bench_puppet("leaver")
	ASSERT(id > 0)
	g_Slot = id
	bench_puppet_spawn(id, "leaver_spawned", 20.0, "respawn")
}

public leaver_spawned(id)
{
	ts_giveweapon(id, TSW_GCOLTS, 0, 0)
	g_Weapon = TSW_GCOLTS
	bench_wait_until("holds_weapon", "leaver_armed", 3.0, id)
}

public leaver_armed(id)
{
	ASSERT_EQ(ts_getuserwpn(id), TSW_GCOLTS)
	server_cmd("kick #%d", get_user_userid(id))
	bench_wait_until("leaver_gone", "leaver_left", 2.0, id)
}

public bool:leaver_gone(id)
{
	return !is_user_connected(id)
}

public leaver_left(id)
{
	// The messages to this slot so far, the leaver's.
	g_WeaponInfos = bench_msg_count(id, "WeaponInfo")
	new newcomer = bench_puppet("newcomer")
	ASSERT_EQ(newcomer, g_Slot)
	bench_puppet_spawn(newcomer, "newcomer_spawned", 20.0, "respawn")
}

public newcomer_spawned(id)
{
	bench_next("newcomer_settled", 0.5, id)
}

public newcomer_settled(id)
{
	// The game has told him nothing about a weapon.
	ASSERT_EQ(bench_msg_count(id, "WeaponInfo"), g_WeaponInfos)
	new clip, ammo, mode, extra
	ASSERT_EQ(ts_getuserwpn(id, clip, ammo, mode, extra), TSW_KUNG_FU)
	ASSERT_EQ(clip, 0)
	ASSERT_EQ(ammo, 0)
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

// A knife in hand stabs; the game scores that as a gun kill (1 point), not as kung fu.
public test_combat_knife_kill()
{
	g_Weapon = TSW_CKNIFE
	g_Buttons = IN_ATTACK
	g_Distance = 32.0
	StartDuel()
}

public test_seal_knife_kill()
{
	g_Weapon = TSW_SKNIFE
	g_Buttons = IN_ATTACK
	g_Distance = 32.0
	StartDuel()
}

// The katana slashes; also a gun kill's 1 point.
public test_katana_kill()
{
	g_Weapon = TSW_KATANA
	g_Buttons = IN_ATTACK
	g_Distance = 32.0
	StartDuel()
}

// The Beretta 92F (TSW_UNK1) is an ordinary gun.
public test_beretta_kill()
{
	g_Weapon = TSW_UNK1
	g_Buttons = IN_ATTACK
	g_Distance = 150.0
	StartDuel()
}

public test_contender_kill()
{
	g_Weapon = TSW_CONTENDER
	g_Buttons = IN_ATTACK
	g_Distance = 150.0
	StartDuel()
}

// The killer runs at the victim, dives (+alt1 while running) and shoots him in the air. The game
// scores 2: the gun's point and one for the dive. TSX added 2 for a stunt it recognised by the exact
// value of iuser4, so it either missed the dive or expected 3, and called the kill kung fu.
public test_gun_kill_in_a_dive()
{
	g_Weapon = GLOCK18
	g_Buttons = IN_ATTACK
	g_Distance = 300.0
	g_Dive = true
	StartDuel()
}

// A knife thrown in a dive: the thrown knife's 2 and one for the dive.
public test_thrown_knife_kill_in_a_dive()
{
	g_Weapon = KNIFE
	g_Buttons = IN_ATTACK2
	g_Distance = 300.0
	g_Dive = true
	StartDuel()
}

// Kung fu in a dive is close combat, which the game gives no stunt point (2, as on the ground) but
// still calls a stunt kill.
public test_kung_fu_kill_in_a_dive()
{
	g_Weapon = TSW_KUNG_FU
	g_Buttons = IN_ATTACK
	g_Distance = 150.0
	g_Dive = true
	StartDuel()
}

// Close combat with a weapon in hand during a dive: the killer slashes with the katana while the
// victim is still out of reach, so the slash misses and leaves the blow ready for 0.25 s, and the
// dive carries him into the victim, who takes it (CTSStunt::CheckForBreakables). A slash that hits
// leaves nothing ready, so the victim must die while one is. The game names the katana, not
// kung fu (it marks close combat only for a kung fu blow), and scores it as a katana kill in a dive:
// the katana's point and one for the dive.
public test_katana_kill_by_dive_shove()
{
	g_Weapon = TSW_KATANA
	g_Buttons = IN_ATTACK
	g_Distance = 300.0
	g_Dive = true
	g_Shove = true
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
	if (g_Shove)
	{
		// On ts_lobby's long flat floor (z 100) by the spawn point at -991 383, where a dive meets
		// nothing but the victim.
		engfunc(EngFunc_SetOrigin, killer, Float:{-991.0, 383.0, 137.0})
		engfunc(EngFunc_SetOrigin, g_Victim, Float:{-691.0, 383.0, 137.0})
		set_pev(killer, pev_velocity, Float:{0.0, 0.0, 0.0})
		set_pev(g_Victim, pev_velocity, Float:{0.0, 0.0, 0.0})
	}
	else if (!bench_puppet_face(killer, g_Victim, g_Distance))
	{
		// Where the victim spawned has no room for the killer; he goes to the killer instead.
		ASSERT(bench_check(bench_puppet_face(g_Victim, killer, g_Distance), "no room for the duel"))
	}
	pev(g_Victim, pev_origin, target)
	bench_puppet_look_at(killer, target)
	set_pev(g_Victim, pev_health, 1.0)
	bench_next("duel_attack", 0.5, killer)
}

public duel_attack(killer)
{
	if (g_Dive)
	{
		// A dive needs speed (80 units a second) and +alt1 pressed, not held.
		bench_puppet_input(killer, 0, 400.0)
		bench_next("duel_dive", 0.3, killer)
		return
	}
	bench_puppet_input(killer, g_Buttons)
	bench_wait_until("victim_dead", "duel_over", 5.0, killer)
}

public duel_dive(killer)
{
	bench_puppet_input(killer, IN_ALT1, 400.0)
	bench_wait_until("diving", "duel_dive_attack", 2.0, killer)
}

public bool:diving(killer)
{
	return (pev(killer, pev_iuser4) & TS_DIVE) != 0
}

public duel_dive_attack(killer)
{
	g_DiveFrame = 0
	bench_wait_until("dive_attacking", "duel_over", 2.0, killer)
}

// Aims at the victim each frame of the dive and presses the attack every other frame (a pistol
// fires once a press), until he is dead.
public bool:dive_attacking(killer)
{
	if (!is_user_alive(g_Victim))
		return true
	new Float:target[3]
	pev(g_Victim, pev_origin, target)
	bench_puppet_look_at(killer, target)
	if (g_Shove)
	{
		// Whether a missed slash is ready to land as he reaches the victim (this frame's, read
		// once the victim is dead), and another slash if the last one ran out short of him.
		new Float:ready = get_pdata_float(killer, PDATA_CLOSECOMBAT, 0, 0)
		g_Armed = ready > 0.0 && get_pdata_byte(killer, PDATA_CLOSECOMBAT_TYPE, 0, 0) == 2
		new Float:origin[3]
		pev(killer, pev_origin, origin)
		new Float:dist = get_distance_f(origin, target)
		new bool:press = ready == 0.0 && g_Slashes < 3 && dist > SHOVE_NEAR && dist <= SHOVE_FAR
		if (press)
			g_Slashes++
		bench_puppet_input(killer, press ? g_Buttons : 0, 400.0)
		return false
	}
	bench_puppet_input(killer, (g_DiveFrame++ & 1) ? 0 : g_Buttons, 400.0)
	return false
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
	// The knife thrown (attack 2) is its own weapon.
	switch (g_Weapon == KNIFE && g_Buttons == IN_ATTACK2 ? TSW_TKNIFE : g_Weapon)
	{
		case TSW_KUNG_FU:
		{
			weapon = TSW_KUNG_FU
			slot = StatsSlot("Kung Fu")
			copy(name, charsmax(name), "Kung Fu")
			copy(deathmsg, charsmax(deathmsg), "Kung Fu")
		}
		case TSW_TKNIFE:
		{
			weapon = TSW_TKNIFE
			slot = TSW_TKNIFE
			copy(name, charsmax(name), "Throwing Knife")
			copy(deathmsg, charsmax(deathmsg), "Throwing Combat Knife")
		}
		case TSW_CKNIFE, TSW_SKNIFE, TSW_KATANA:
		{
			weapon = g_Weapon
			slot = g_Weapon
			if (g_Weapon == TSW_CKNIFE)
				copy(name, charsmax(name), "Combat Knife")
			else if (g_Weapon == TSW_SKNIFE)
				copy(name, charsmax(name), "Seal Knife")
			else
				copy(name, charsmax(name), "Katana")
			copy(deathmsg, charsmax(deathmsg), name)
		}
		default:
		{
			weapon = g_Weapon
			slot = g_Weapon
			if (g_Weapon == TSW_CONTENDER)
			{
				copy(name, charsmax(name), "Contender G2")
				copy(deathmsg, charsmax(deathmsg), "Contender G2")
			}
			else if (g_Weapon == GLOCK18)
			{
				copy(name, charsmax(name), "Glock-18")
				copy(deathmsg, charsmax(deathmsg), "Glock-18")
			}
			else
			{
				// TSX still names it after its TS 2 placeholder.
				copy(name, charsmax(name), "Unk1")
				copy(deathmsg, charsmax(deathmsg), "Beretta 92F")
			}
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
	// The points: 2 for kung fu and a thrown knife, 1 for the rest, and a point more for a stunt,
	// except in close combat. The killer started with none.
	new points = (weapon == TSW_KUNG_FU || weapon == TSW_TKNIFE) ? 2 : 1
	if (g_Shove)
	{
		// The slash missed and left the blow ready: the dive did the killing.
		ASSERT(bench_check(g_Slashes > 0, "no slash before the victim died"))
		ASSERT(bench_check(g_Armed, "no missed slash was ready when the victim died"))
	}
	if (g_Dive)
	{
		// The game saw the dive when it scored the kill, and said so to everyone.
		ASSERT(g_DeathStunt & TS_DIVE)
		ASSERT_MSG(killer, "TSMessage", "#TS_StStl")
		if (weapon != TSW_KUNG_FU)
			points++
		ASSERT_EQ(ts_getuserkillflags(killer), TSKF_STUNTKILL)
	}
	else
	{
		ASSERT_EQ(bench_msg_count(killer, "TSMessage", "#TS_StStl"), 0)
		ASSERT_EQ(ts_getuserkillflags(killer), 0)
	}
	ASSERT_EQ(get_user_frags(killer), points)
	ASSERT_EQ(ts_getuserlastfrag(killer), points)
	// The killer's stats against the victim name the weapon of the kill.
	new vname[32]
	ASSERT_EQ(get_user_vstats(killer, g_Victim, stats, body, vname, charsmax(vname)), 1)
	ASSERT_STR_EQ(vname, name)
	ASSERT_EQ(stats[STATSX_DEATHS], 1)
	// Per weapon: kung fu and the knives count a shot for each hit, a gun each round it fires.
	ASSERT_EQ(get_user_wstats(killer, slot, stats, body), 1)
	ASSERT_EQ(stats[STATSX_KILLS], 1)
	ASSERT(stats[STATSX_SHOTS] >= stats[STATSX_HITS])
	ASSERT(stats[STATSX_HITS] >= 1)
	ASSERT_EQ(get_user_wstats(killer, 0, stats, body), 1)
	ASSERT_EQ(stats[STATSX_KILLS], 1)
	bench_pass()
}
