// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for TSX in The Specialists 3.0's The One mode, against how the game runs it. The game
// reads mp_theonemode when the map starts (DecideGamePlay, 0x667ac) and then plays it as teamplay:
// the One is alone on team "The ONE", everyone else is on the other team. A kill scores only for
// the One (TSGetPointsForFrag, 0x79140): a kill of the One is worth nothing, and its killer becomes
// the One (TheOneIsDead, 0x6b258); a kill between two others is a team kill, -1. The game picks a
// One from the living every 10 seconds while there is none (SelectRandomTheOne, 0x6af28).
//
// The first test switches the mode on with a map change and the last switches it off again
// (server.cfg sets mp_theonemode back to 0 on every map, so any later map is deathmatch too).
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <tsx>
#include <tsfun>
#include <tsstats>
#include <amxxbench>

#define GLOCK18		1

// CBasePlayer (TS 3.0 Linux): the game's streak, a byte that TSInit (0x82c24) clears, and whether
// this player is the One, a byte SetPlayerTheOne (0x6b078) sets.
#define PDATA_STREAK	0x744
#define PDATA_THEONE	0x7b9

#define MAX_KILLS	8
#define MAX_PUPPETS	6

new g_GameDesc[64]
new bool:g_OneMode

// The kills a test makes, in order: who kills whom, and how long after the last kill's DeathMsg.
new g_PlanKiller[MAX_KILLS]
new g_PlanVictim[MAX_KILLS]
new Float:g_PlanGap[MAX_KILLS]
new g_PlanLen
new g_PlanAt
new g_PlanDone[32]

// What came of each: the DeathMsg's time, killer and weapon name, the killer's frags before and
// after, and what TSX said in client_death.
new Float:g_KillTime[MAX_KILLS]
new g_KillBy[MAX_KILLS]
new g_KillName[MAX_KILLS][16]
new g_FragsBefore[MAX_KILLS]
new g_FragsAfter[MAX_KILLS]
new g_Weapon[MAX_KILLS]
new g_TK[MAX_KILLS]
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
	register_plugin("TSX The One Tests", AMXX_VERSION_STR, "AMXX Dev Team")
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

public bench_teardown()
{
	set_cvar_num("mp_friendlyfire", 0)
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
	read_data(3, g_KillName[g_PlanAt], charsmax(g_KillName[]))
	g_LastDeathMsg = get_gametime()
}

public client_death(killer, victim, wpnindex, hitplace, TK)
{
	if (g_PlanAt >= g_PlanLen || victim != g_PlanVictim[g_PlanAt] || killer != g_PlanKiller[g_PlanAt])
		return
	g_Weapon[g_PlanAt] = wpnindex
	g_TK[g_PlanAt] = TK
	g_Flags[g_PlanAt] = ts_getuserkillflags(killer)
	g_LastFrag[g_PlanAt] = ts_getuserlastfrag(killer)
	g_Streak[g_PlanAt] = ts_getkillingstreak(killer)
	g_FragsAfter[g_PlanAt] = get_user_frags(killer)
	g_Counted[g_PlanAt] = true
}

// --- the mode ------------------------------------------------------------------------------

// Goes on with step on a map in The One mode, changing the map for it if this one is not.
OneMode(const step[])
{
	if (g_OneMode)
	{
		bench_next(step, 0.0)
		return
	}
	set_cvar_num("mp_theonemode", 1)
	bench_change_map("ts_lobby", step)
}

bool:IsTheOne(id)
{
	return get_pdata_byte(id, PDATA_THEONE, 0, 0) != 0
}

// --- puppets -------------------------------------------------------------------------------

// Makes count puppets, each alive and holding a Glock-18: the first alone until the game makes him
// the One, then the rest, who are the others. Then calls step.
Puppets(count, const step[])
{
	g_OneMode = true
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
	formatex(name, charsmax(name), "one%d", g_PuppetCount)
	new id = bench_puppet(name)
	ASSERT(id > 0)
	g_Puppets[g_PuppetCount++] = id
	bench_puppet_spawn(id, "puppet_spawned", 20.0, "respawn")
}

public puppet_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 100, 0)
	bench_wait_until("holds_glock", "puppet_armed", 3.0, id)
}

public bool:holds_glock(id)
{
	new BenchMsg:msg = bench_msg_last(id, "WeaponInfo")
	return msg != BenchMsg:0 && bench_msg_int(msg, 0) == GLOCK18
}

public puppet_armed(id)
{
	if (id == g_Puppets[0])
		bench_wait_until("is_the_one", "first_is_the_one", 15.0, id)
	else
		puppet_next(0)
}

public bool:is_the_one(id)
{
	return IsTheOne(id)
}

public first_is_the_one(id)
{
	new team[16]
	get_user_team(id, team, charsmax(team))
	ASSERT_STR_EQ(team, "The ONE")
	puppet_next(0)
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
	bench_wait_until("plan_died", "plan_killed", 1.0, killer)
}

public bool:plan_died(killer)
{
	return g_KillBy[g_PlanAt] != 0
}

// TSX reports the kill when the victim's TSHealth comes, a frame or so after the DeathMsg.
public plan_killed(killer)
{
	ASSERT_EQ(g_KillBy[g_PlanAt], killer)
	bench_next("plan_reported", 0.1)
}

public plan_reported(dummy)
{
	g_PlanAt++
	bench_next("plan_next", 0.0)
}

// The kill's points, team kill and flags, as the game counted them and as TSX reports them.
bool:CheckKill(n, points, tk, flags)
{
	if (!g_Counted[n])
	{
		bench_fail("kill %d: TSX did not report it as a kill by %d of %d", n, g_PlanKiller[n], g_PlanVictim[n])
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
	if (g_TK[n] != tk || g_LastFrag[n] != points || g_Flags[n] != flags)
	{
		bench_fail("kill %d: TSX TK %d lastfrag %d flags %d, expected %d, %d and %d", n, g_TK[n], g_LastFrag[n],
			g_Flags[n], tk, points, flags)
		return false
	}
	return true
}

Float:Gap(n)
{
	return g_KillTime[n] - g_KillTime[n - 1]
}

// --- tests ---------------------------------------------------------------------------------

// The One kills one of the others, and is then killed by another: that kill is worth nothing (no
// +5 for the One's streak, no team kill), its killer becomes the One, and the One's streak is gone
// as he dies (PlayerKilled, 0x7a2ff). TSX took a kill that scored nothing for no kill at all and
// gave it to the victim as a suicide.
public test_kill_of_the_one_scores_nothing()
{
	bench_set_timeout(90.0)
	OneMode("kill_of_one_map")
}

public kill_of_one_map()
{
	Puppets(3, "kill_of_one_ready")
}

public kill_of_one_ready()
{
	new one = g_Puppets[0], killer = g_Puppets[1], other = g_Puppets[2]
	Plan(one, other)
	Plan(killer, one, 2.1)
	RunPlan("kill_of_one_done")
}

public kill_of_one_done()
{
	new one = g_Puppets[0], killer = g_Puppets[1]
	// A kill by the One scores as in deathmatch.
	if (!CheckKill(0, 1, 0, 0)) return
	ASSERT_STR_EQ(g_KillName[0], "Glock-18")
	if (!CheckKill(1, 0, 0, 0)) return
	ASSERT_STR_EQ(g_KillName[1], "Glock-18")
	ASSERT_EQ(g_Streak[1], 1)
	ASSERT_EQ(get_pdata_byte(killer, PDATA_STREAK, 0, 0), 1)

	// TSX's stats count it as his kill and the One's death.
	new stats[STATSX_MAX_STATS], body[MAX_BODYHITS]
	get_user_rstats(killer, stats, body)
	ASSERT_EQ(stats[STATSX_KILLS], 1)
	ASSERT_EQ(stats[STATSX_TEAMKILLS], 0)
	get_user_rstats(one, stats, body)
	ASSERT_EQ(stats[STATSX_KILLS], 1)
	ASSERT_EQ(stats[STATSX_DEATHS], 1)

	// He is the One now, and the dead One is not; the game took the One's streak with him.
	ASSERT(IsTheOne(killer))
	ASSERT_FALSE(IsTheOne(one))
	new team[16]
	get_user_team(killer, team, charsmax(team))
	ASSERT_STR_EQ(team, "The ONE")
	ASSERT_EQ(get_pdata_byte(one, PDATA_STREAK, 0, 0), 0)
	ASSERT_EQ(ts_getkillingstreak(one), 0)
	// What everyone is told (TheOneIsDead, then SetPlayerTheOne for him).
	ASSERT_MSG(killer, "TSMessage", "The One was killed by one1!")
	ASSERT_MSG(killer, "TSMessage", "one1 is The One!")
	bench_pass()
}

// Two others are on one team: with friendly fire on, a kill between them is a team kill, -1, and the
// game names it "teammate". TSX kept the points of the killer's last kill as this one's, and its
// count of his frags missed the -1, so it got his next kill's points wrong as well.
public test_kill_between_two_others_is_a_team_kill()
{
	bench_set_timeout(90.0)
	OneMode("others_map")
}

public others_map()
{
	Puppets(3, "others_ready")
}

public others_ready()
{
	set_cvar_num("mp_friendlyfire", 1)
	new one = g_Puppets[0], a = g_Puppets[1], b = g_Puppets[2]
	Plan(a, b)
	Plan(a, one, 2.1)
	Plan(a, b, 2.1)
	RunPlan("others_done")
}

public others_done()
{
	ASSERT_STR_EQ(g_KillName[0], "teammate")
	if (!CheckKill(0, -1, 1, 0)) return
	new stats[STATSX_MAX_STATS], body[MAX_BODYHITS]
	get_user_rstats(g_Puppets[1], stats, body)
	ASSERT_EQ(stats[STATSX_TEAMKILLS], 1)
	// Then he kills the One (nothing), and as the One kills b (1).
	if (!CheckKill(1, 0, 0, 0)) return
	if (!CheckKill(2, 1, 0, 0)) return
	bench_pass()
}

// The new One's first kill right after he killed the One is no double kill: the kill of the One
// scored nothing, so the game did not remember it (0x7aa8c, for a kill worth points only). His next
// within 2 seconds is. TSX called the first a double kill.
public test_kill_by_the_new_one()
{
	bench_set_timeout(90.0)
	OneMode("new_one_map")
}

public new_one_map()
{
	Puppets(4, "new_one_ready")
}

public new_one_ready()
{
	new one = g_Puppets[0], killer = g_Puppets[1]
	Plan(killer, one)
	Plan(killer, g_Puppets[2], 1.9)
	Plan(killer, g_Puppets[3], 1.9)
	RunPlan("new_one_done")
}

public new_one_done()
{
	new killer = g_Puppets[1]
	ASSERT(Gap(1) > 1.8 && Gap(1) < 2.0)
	ASSERT(Gap(2) > 1.8 && Gap(2) < 2.0)
	if (!CheckKill(1, 1, 0, 0)) return
	if (!CheckKill(2, 2, 0, TSKF_DOUBLEKILL)) return
	ASSERT_EQ(bench_msg_count(killer, "TSMessage", "#TS_Doublefrag"), 1)
	if (!CheckKill(0, 0, 0, 0)) return
	ASSERT_EQ(g_Streak[2], 3)
	bench_pass()
}

// Back to deathmatch for the tests after these.
public test_back_to_deathmatch()
{
	set_cvar_num("mp_theonemode", 0)
	bench_change_map("ts_lobby", "deathmatch_again")
}

public deathmatch_again()
{
	// The server's own mode: teamplay when its game.cfg says so. The description is asked of the game
	// here: ReHLDS asks it only once, when the server starts.
	dllfunc(DLLFunc_GetGameDescription, g_GameDesc, charsmax(g_GameDesc))
	ASSERT_STR_EQ(g_GameDesc, get_cvar_num("mp_teamplay") ? "The Specialists (Teamplay)" : "The Specialists (DM)")
	bench_pass()
}
