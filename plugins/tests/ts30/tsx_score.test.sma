// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the kill flags and points TSX reports (ts_getuserkillflags, ts_getuserlastfrag,
// ts_getkillingstreak) against how The Specialists 3.0 scores a kill in PlayerKilled (0x795e4):
// a kill within 2 seconds of the killer's last is a double kill (points twice), and the game then
// forgets that last kill; a victim whose streak is 9 or more is the specialist (5 points more);
// from his 10th kill on, the killer's points are doubled again, after the 5 are added.
//
// Every kill is a puppet with 1 health killed by one with a Glock-18 in hand, which is 1 point
// before the bonuses.
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

// The game's own streak and last kill time, in CBasePlayer (TS 3.0 Linux): TSInit (0x82c24)
// clears both, PlayerKilled counts the streak (0x797f3) and sets the time (0x7aa97, 0x7aab2).
#define PDATA_STREAK	0x744	// a byte
#define PDATA_LASTKILL	(0x748 / 4)

#define MAX_KILLS	24
#define MAX_PUPPETS	12

// The kills a test makes, in order: who kills whom, and how long after the last kill's DeathMsg.
new g_PlanKiller[MAX_KILLS]
new g_PlanVictim[MAX_KILLS]
new Float:g_PlanGap[MAX_KILLS]
new g_PlanLen
new g_PlanAt
new g_PlanDone[32]

// What came of each: the game's DeathMsg time and killer, the killer's frags before and after,
// and what TSX said in client_death (the weapon, the flags, the points and the killer's streak).
new Float:g_KillTime[MAX_KILLS]
new g_KillBy[MAX_KILLS]
new g_FragsBefore[MAX_KILLS]
new g_FragsAfter[MAX_KILLS]
new g_Weapon[MAX_KILLS]
new g_Flags[MAX_KILLS]
new g_LastFrag[MAX_KILLS]
new g_Streak[MAX_KILLS]
new bool:g_Counted[MAX_KILLS]
new Float:g_LastDeathMsg

new g_Puppets[MAX_PUPPETS]
new g_PuppetCount
new g_Wanted
new g_Ready[32]

public plugin_init()
{
	register_plugin("TSX Score Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_event("DeathMsg", "on_death_msg", "a")
}

public bench_setup()
{
	g_PlanLen = 0
	g_PlanAt = 0
	g_PuppetCount = 0
	g_Wanted = 0
	g_LastDeathMsg = 0.0
	for (new i = 0; i < MAX_KILLS; i++)
	{
		g_KillTime[i] = 0.0
		g_KillBy[i] = 0
		g_Counted[i] = false
	}
}

public on_death_msg()
{
	if (g_PlanAt >= g_PlanLen)
		return
	new killer = read_data(1), victim = read_data(2)
	if (victim != g_PlanVictim[g_PlanAt])
		return
	g_KillTime[g_PlanAt] = get_gametime()
	g_KillBy[g_PlanAt] = killer
	g_LastDeathMsg = get_gametime()
}

public client_death(killer, victim, wpnindex, hitplace, TK)
{
	if (g_PlanAt >= g_PlanLen || victim != g_PlanVictim[g_PlanAt] || killer != g_PlanKiller[g_PlanAt])
		return
	g_Weapon[g_PlanAt] = wpnindex
	g_Flags[g_PlanAt] = ts_getuserkillflags(killer)
	g_LastFrag[g_PlanAt] = ts_getuserlastfrag(killer)
	g_Streak[g_PlanAt] = ts_getkillingstreak(killer)
	g_FragsAfter[g_PlanAt] = get_user_frags(killer)
	g_Counted[g_PlanAt] = true
}

// --- puppets -------------------------------------------------------------------------------

// Makes count puppets, one after another, each alive and holding a Glock-18, then calls step.
Puppets(count, const step[])
{
	copy(g_Ready, charsmax(g_Ready), step)
	g_Wanted = count
	puppet_next(0)
}

public puppet_next(dummy)
{
	if (g_PuppetCount == g_Wanted)
	{
		bench_next(g_Ready, 0.0)
		return
	}
	new name[16]
	formatex(name, charsmax(name), "score%d", g_PuppetCount)
	new id = bench_puppet(name)
	ASSERT(id > 0)
	g_Puppets[g_PuppetCount++] = id
	bench_puppet_spawn(id, "puppet_spawned", 20.0, "respawn")
}

public puppet_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 100, 0)
	bench_wait_until("holds_glock", "puppet_next", 3.0, id)
}

public bool:holds_glock(id)
{
	new BenchMsg:msg = bench_msg_last(id, "WeaponInfo")
	return msg != BenchMsg:0 && bench_msg_int(msg, 0) == GLOCK18
}

// --- the plan ------------------------------------------------------------------------------

Plan(killer, victim, Float:gap = 0.0)
{
	g_PlanKiller[g_PlanLen] = killer
	g_PlanVictim[g_PlanLen] = victim
	g_PlanGap[g_PlanLen] = gap
	g_PlanLen++
}

RunPlan(const done[])
{
	copy(g_PlanDone, charsmax(g_PlanDone), done)
	g_PlanAt = 0
	plan_next(0)
}

public plan_next(dummy)
{
	if (g_PlanAt == g_PlanLen)
	{
		bench_next(g_PlanDone, 0.0)
		return
	}
	new victim = g_PlanVictim[g_PlanAt]
	if (!is_user_alive(victim))
	{
		bench_puppet_spawn(victim, "plan_victim_up", 20.0, "respawn")
		return
	}
	plan_victim_up(victim)
}

public plan_victim_up(victim)
{
	new killer = g_PlanKiller[g_PlanAt]
	if (!is_user_alive(killer))
	{
		bench_fail("kill %d: the killer %d is dead", g_PlanAt, killer)
		return
	}
	bench_wait_until("plan_time", "plan_fire", 10.0, killer)
}

public bool:plan_time(killer)
{
	return get_gametime() >= g_LastDeathMsg + g_PlanGap[g_PlanAt]
}

// The killer, Glock-18 in hand, does the victim's last point of damage himself, as a shot that hits
// does (CBasePlayer::TakeDamage, then PlayerKilled at once), so the kill comes in this very frame.
public plan_fire(killer)
{
	new victim = g_PlanVictim[g_PlanAt]
	g_FragsBefore[g_PlanAt] = get_user_frags(killer)
	set_pev(victim, pev_health, 1.0)
	ExecuteHamB(Ham_TakeDamage, victim, killer, killer, 10.0, DMG_BULLET)
	bench_wait_until("plan_counted", "plan_killed", 1.0, killer)
}

public bool:plan_counted(killer)
{
	return g_Counted[g_PlanAt]
}

public plan_killed(killer)
{
	ASSERT_EQ(g_KillBy[g_PlanAt], killer)
	g_PlanAt++
	bench_next("plan_next", 0.0)
}

// The kill's points and flags, as the game counted them and as TSX reports them.
bool:CheckKill(n, points, flags)
{
	if (!g_Counted[n])
	{
		bench_fail("kill %d: TSX did not count it", n)
		return false
	}
	if (g_Weapon[n] != GLOCK18)
	{
		bench_fail("kill %d: TSX named weapon %d, expected the Glock-18", n, g_Weapon[n])
		return false
	}
	if (g_FragsAfter[n] - g_FragsBefore[n] != points)
	{
		bench_fail("kill %d: the game gave %d points, expected %d", n, g_FragsAfter[n] - g_FragsBefore[n], points)
		return false
	}
	if (g_LastFrag[n] != points || g_Flags[n] != flags)
	{
		bench_fail("kill %d: TSX lastfrag %d flags %d, expected %d and %d", n, g_LastFrag[n], g_Flags[n], points, flags)
		return false
	}
	return true
}

Float:Gap(n)
{
	return g_KillTime[n] - g_KillTime[n - 1]
}

// --- double kills --------------------------------------------------------------------------

// A second kill 1.9 s after the first is a double kill: 2 points. TSX allowed only 1 second.
public test_double_kill_within_2_seconds()
{
	Puppets(3, "double_ready")
}

public double_ready()
{
	new killer = g_Puppets[0]
	Plan(killer, g_Puppets[1])
	Plan(killer, g_Puppets[2], 1.9)
	RunPlan("double_done")
}

public double_done()
{
	new killer = g_Puppets[0]
	ASSERT(Gap(1) > 1.8 && Gap(1) < 2.0)
	if (!CheckKill(0, 1, 0)) return
	if (!CheckKill(1, 2, TSKF_DOUBLEKILL)) return
	ASSERT_MSG(killer, "TSMessage", "#TS_Doublefrag")
	// The game forgot the last kill after the double kill.
	ASSERT(get_pdata_float(killer, PDATA_LASTKILL, 0, 0) == 0.0)
	bench_pass()
}

// A second kill 2.1 s after the first is not.
public test_kill_after_2_seconds_is_not_a_double_kill()
{
	Puppets(3, "single_ready")
}

public single_ready()
{
	new killer = g_Puppets[0]
	Plan(killer, g_Puppets[1])
	Plan(killer, g_Puppets[2], 2.1)
	RunPlan("single_done")
}

public single_done()
{
	new killer = g_Puppets[0]
	ASSERT(Gap(1) > 2.0 && Gap(1) < 2.2)
	if (!CheckKill(0, 1, 0)) return
	if (!CheckKill(1, 1, 0)) return
	ASSERT_EQ(bench_msg_count(killer, "TSMessage", "#TS_Doublefrag"), 0)
	ASSERT(get_pdata_float(killer, PDATA_LASTKILL, 0, 0) == g_KillTime[1])
	bench_pass()
}

// After a double kill the game forgets the last kill, so a third kill 0.5 s later is no double
// kill. TSX remembered the second and called the third one.
public test_double_kill_forgets_the_last_kill()
{
	Puppets(4, "triple_ready")
}

public triple_ready()
{
	new killer = g_Puppets[0]
	Plan(killer, g_Puppets[1])
	Plan(killer, g_Puppets[2], 1.9)
	Plan(killer, g_Puppets[3], 0.5)
	RunPlan("triple_done")
}

public triple_done()
{
	ASSERT(Gap(1) > 1.8 && Gap(1) < 2.0)
	ASSERT(Gap(2) < 1.0)
	if (!CheckKill(0, 1, 0)) return
	if (!CheckKill(1, 2, TSKF_DOUBLEKILL)) return
	if (!CheckKill(2, 1, 0)) return
	bench_pass()
}

// --- the specialist ------------------------------------------------------------------------

// Plans count kills by killer of the puppets from first on (in turn; the dead respawn), each gap
// seconds after the last.
PlanStreak(killer, count, first, Float:gap)
{
	new n = first
	for (new i = 0; i < count; i++)
	{
		Plan(killer, g_Puppets[n], gap)
		if (++n == g_PuppetCount)
			n = first
	}
}

// The victim has 9 kills: he is the specialist, and killing him is 5 points more (1 + 5). TSX
// waited for 10.
public test_killing_the_specialist()
{
	bench_set_timeout(120.0)
	Puppets(8, "spec_ready")
}

public spec_ready()
{
	new killer = g_Puppets[0], victim = g_Puppets[1]
	PlanStreak(victim, 9, 2, 0.0)
	Plan(killer, victim, 2.1)
	RunPlan("spec_done")
}

public spec_done()
{
	new killer = g_Puppets[0], victim = g_Puppets[1]
	// TSX counted his streak as the game did, before he died.
	ASSERT_EQ(g_Streak[8], 9)
	for (new i = 0; i < 9; i++)
		ASSERT_EQ(g_KillBy[i], victim)
	if (!CheckKill(9, 6, TSKF_KILLEDSPEC)) return
	ASSERT_EQ(g_Streak[9], 1)
	ASSERT_MSG(killer, "TSMessage", "#TS_KilledTheSpecialist")
	ASSERT_EQ(get_pdata_byte(killer, PDATA_STREAK, 0, 0), 1)
	bench_pass()
}

// The killer's 9th kill is plain (he becomes the specialist); his 10th is doubled. Made a double
// kill of the victim with 9 kills, it is ((1 x 2) + 5) x 2 = 14: the game adds the 5 before the
// streak doubles the points, where TSX added it after (9).
public test_unstoppable_double_kill_of_the_specialist()
{
	bench_set_timeout(150.0)
	Puppets(8, "order_ready")
}

public order_ready()
{
	new killer = g_Puppets[0], victim = g_Puppets[1]
	PlanStreak(victim, 9, 2, 0.0)
	PlanStreak(killer, 9, 2, 2.1)
	Plan(killer, victim, 1.9)
	RunPlan("order_done")
}

public order_done()
{
	new killer = g_Puppets[0]
	// The 9th: no double kill, no doubling.
	if (!CheckKill(17, 1, 0)) return
	ASSERT_EQ(g_Streak[17], 9)
	ASSERT_MSG(killer, "TSMessage", "#TS_Specialist")
	ASSERT(Gap(18) > 1.8 && Gap(18) < 2.0)
	if (!CheckKill(18, 14, TSKF_DOUBLEKILL | TSKF_KILLEDSPEC | TSKF_ISSPEC)) return
	ASSERT_EQ(g_Streak[18], 10)
	ASSERT_EQ(get_pdata_byte(killer, PDATA_STREAK, 0, 0), 10)
	ASSERT_MSG(killer, "TSMessage", "#TS_Unstoppable")
	bench_pass()
}

// A streak lasts until the player spawns again: the victim's 9 are gone when he is back.
public test_streak_ends_at_respawn()
{
	bench_set_timeout(120.0)
	Puppets(4, "respawn_ready")
}

public respawn_ready()
{
	new killer = g_Puppets[0], victim = g_Puppets[1]
	PlanStreak(victim, 3, 2, 0.0)
	Plan(killer, victim, 2.1)
	RunPlan("respawn_killed")
}

public respawn_killed()
{
	new victim = g_Puppets[1]
	ASSERT_EQ(g_Streak[2], 3)
	// Dead, he keeps it until he spawns.
	ASSERT_EQ(ts_getkillingstreak(victim), 3)
	bench_puppet_spawn(victim, "respawn_back", 20.0, "respawn")
}

public respawn_back(victim)
{
	bench_next("respawn_settled", 0.3, victim)
}

public respawn_settled(victim)
{
	ASSERT_EQ(get_pdata_byte(victim, PDATA_STREAK, 0, 0), 0)
	ASSERT_EQ(ts_getkillingstreak(victim), 0)
	bench_pass()
}
