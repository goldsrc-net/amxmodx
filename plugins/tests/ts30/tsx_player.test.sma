// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for TSX's player natives on the original The Specialists 3.0 game library, where they work
// through the CBasePlayer gamedata: cash, slots, the status message, the powerups, slow motion and
// the bullet-time flag. Each checks what the game itself does with the field: the message it sends
// the player, or how he moves.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <amxxbench>

new g_Other
new Float:g_Start[3]
new Float:g_SpeedEnd
new g_Turns
new Float:g_Distance

public plugin_init()
{
	register_plugin("TSX Player Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

Float:SlowFactor(id)
{
	new Float:value
	pev(id, pev_fuser1, value)
	return value
}

bool:Near(Float:a, Float:b)
{
	return floatabs(a - b) < 0.01
}

#define ASSERT_NEAR(%0,%1) if (!__near(%0, %1)) return

stock bool:__near(Float:received, Float:expected)
{
	new what[64]
	formatex(what, charsmax(what), "expected %.3f, received %.3f", expected, received)
	return bench_check(Near(received, expected), what)
}

// The last value of a one-argument message the game sent the player, or -1.
LastInt(id, const name[], arg = 0)
{
	new BenchMsg:msg = bench_msg_last(id, name)
	if (msg == BenchMsg:0)
		return -1
	return bench_msg_int(msg, arg)
}

Float:LastFloat(id, const name[])
{
	new BenchMsg:msg = bench_msg_last(id, name)
	if (msg == BenchMsg:0)
		return -1.0
	return bench_msg_float(msg, 0)
}

// What ts_createpwup does (its include leaves out the origin the native reads).
CreatePowerup(const type[])
{
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_powerup"))
	if (!ent)
		return 0
	set_kvd(0, KV_ClassName, "ts_powerup")
	set_kvd(0, KV_KeyName, "pwuptype")
	set_kvd(0, KV_Value, type)
	set_kvd(0, KV_fHandled, 0)
	dllfunc(DLLFunc_KeyValue, ent, 0)
	set_kvd(0, KV_ClassName, "ts_powerup")
	set_kvd(0, KV_KeyName, "pwupduration")
	set_kvd(0, KV_Value, "60")
	set_kvd(0, KV_fHandled, 0)
	dllfunc(DLLFunc_KeyValue, ent, 0)
	dllfunc(DLLFunc_Spawn, ent)
	return ent
}

// --- cash, slots, status message -------------------------------------------------------------

public test_cash_reaches_the_hud()
{
	new id = bench_puppet("rich")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "cash_spawned", 20.0, "respawn")
}

public cash_spawned(id)
{
	ts_setusercash(id, 1234)
	ASSERT_EQ(ts_getusercash(id), 1234)
	bench_wait_until("cash_sent", "cash_shown", 2.0, id)
}

public bool:cash_sent(id)
{
	return LastInt(id, "TSCash") == 1234
}

public cash_shown(id)
{
	bench_pass()
}

public test_slots_are_the_free_slots()
{
	new id = bench_puppet("packer")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "slots_spawned", 20.0, "respawn")
}

public slots_spawned(id)
{
	bench_next("slots_settled", 0.5, id)
}

public slots_settled(id)
{
	// The free slots the game last sent the player (TSSpace).
	ASSERT(ts_getuserspace(id) > 0)
	ASSERT_EQ(ts_getuserslots(id), ts_getuserspace(id))
	ts_setuserslots(id, 50)
	ASSERT_EQ(ts_getuserslots(id), 50)
	bench_wait_until("slots_sent", "slots_shown", 2.0, id)
}

public bool:slots_sent(id)
{
	return LastInt(id, "TSSpace") == 50
}

public slots_shown(id)
{
	ASSERT_EQ(ts_getuserspace(id), 50)
	bench_pass()
}

public test_message_is_the_award_everyone_sees()
{
	new id = bench_puppet("specialist")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "message_spawned", 20.0, "respawn")
}

public message_spawned(id)
{
	ts_set_message(id, TSMSG_SPECIALIST)
	ASSERT_EQ(ts_get_message(id), TSMSG_SPECIALIST)
	ASSERT(ts_is_specialist(id))
	bench_wait_until("message_sent", "message_shown", 2.0, id)
}

public bool:message_sent(id)
{
	new BenchMsg:msg = bench_msg_last(id, "TSPAward")
	return msg != BenchMsg:0 && bench_msg_int(msg, 0) == id && bench_msg_int(msg, 1) == TSMSG_SPECIALIST
}

public message_shown(id)
{
	bench_pass()
}

// --- powerups --------------------------------------------------------------------------------

public test_fake_slowmo_runs_and_ends()
{
	new id = bench_puppet("slowmo")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "slowmo_spawned", 20.0, "respawn")
}

public slowmo_spawned(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	ASSERT_EQ(ts_is_in_slowmo(id), 0)
	ts_set_fakeslowmo(id, 2.0)
	ASSERT_EQ(ts_is_running_powerup(id), TSPWUP_SLOWMO)
	new Float:until = Float:ts_is_in_slowmo(id)
	ASSERT_NEAR(until, get_gametime() + 2.0)
	bench_next("slowmo_running", 1.0, id)
}

public slowmo_running(id)
{
	// The game slows the player himself (0.6) and tells his client the slow-motion amount (35).
	ASSERT_NEAR(SlowFactor(id), 0.6)
	ASSERT_NEAR(LastFloat(id, "TSSlowMo"), 35.0)
	bench_next("slowmo_over", 1.5, id)
}

public slowmo_over(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	ASSERT_EQ(ts_is_in_slowmo(id), 0)
	ASSERT_NEAR(SlowFactor(id), 1.0)
	ASSERT_NEAR(LastFloat(id, "TSSlowMo"), 100.0)
	bench_pass()
}

public test_fake_slowpause_slows_the_bullets()
{
	new id = bench_puppet("slowpause")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "slowpause_spawned", 20.0, "respawn")
}

public slowpause_spawned(id)
{
	ts_set_fakeslowpause(id, 2.0)
	ASSERT_EQ(ts_is_running_powerup(id), TSPWUP_SLOWPAUSE)
	bench_next("slowpause_running", 1.0, id)
}

public slowpause_running(id)
{
	ASSERT_NEAR(SlowFactor(id), 0.8)
	ASSERT_NEAR(LastFloat(id, "TSSlowMo"), 22.5)
	ASSERT_EQ(LastInt(id, "TSBTime"), 1)
	bench_next("slowpause_over", 1.5, id)
}

public slowpause_over(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	ASSERT_EQ(LastInt(id, "TSBTime"), 0)
	bench_pass()
}

public test_force_run_powerup_changes_the_running_one()
{
	new id = bench_puppet("switcher")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "switch_spawned", 20.0, "respawn")
}

public switch_spawned(id)
{
	ts_set_fakeslowmo(id, 2.0)
	ts_force_run_powerup(id, TSPWUP_SLOWPAUSE)
	ASSERT_EQ(ts_is_running_powerup(id), TSPWUP_SLOWPAUSE)
	bench_next("switch_running", 0.5, id)
}

public switch_running(id)
{
	ASSERT_NEAR(LastFloat(id, "TSSlowMo"), 22.5)
	bench_next("switch_over", 2.0, id)
}

public switch_over(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	bench_pass()
}

public test_superjump_and_kung_fu_powerups()
{
	new id = bench_puppet("jumper")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "jumper_spawned", 20.0, "respawn")
}

// A powerup dropped where the player stands; he picks it up once it lands.
DropPowerup(id, const type[])
{
	new ent = CreatePowerup(type)
	if (ent)
	{
		new Float:origin[3]
		pev(id, pev_origin, origin)
		engfunc(EngFunc_SetOrigin, ent, origin)
	}
	return ent
}

public jumper_spawned(id)
{
	ASSERT_EQ(ts_has_superjump(id), 0)
	ASSERT_EQ(ts_has_fupowerup(id), 0)
	ASSERT(DropPowerup(id, "256") > 0)
	ASSERT(DropPowerup(id, "4") > 0)
	bench_next("jumper_took", 4.0, id)
}

public jumper_took(id)
{
	// The game told him he picked up both (PwUp).
	ASSERT(bench_msg_count(id, "PwUp") >= 2)
	ASSERT_EQ(ts_has_superjump(id), 1)
	ASSERT_EQ(ts_has_fupowerup(id), 1)
	bench_pass()
}

// --- bullet time and physics speed -----------------------------------------------------------

public test_bullettrail_is_the_bullet_time_flag()
{
	new id = bench_puppet("trails")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "trails_spawned", 20.0, "respawn")
}

public trails_spawned(id)
{
	ts_set_bullettrail(id, 1)
	bench_wait_until("trails_on", "trails_shown", 2.0, id)
}

public bool:trails_on(id)
{
	return LastInt(id, "TSBTime") == 1
}

public trails_shown(id)
{
	// Only the flag: the player's slow motion is untouched.
	ASSERT_NEAR(LastFloat(id, "TSSlowMo"), 100.0)
	ts_set_bullettrail(id, 0)
	bench_wait_until("trails_off", "trails_hidden", 2.0, id)
}

public bool:trails_off(id)
{
	return LastInt(id, "TSBTime") == 0
}

public trails_hidden(id)
{
	bench_pass()
}

public test_physics_speed_reaches_the_client_only()
{
	new id = bench_puppet("physics")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "physics_spawned", 20.0, "respawn")
}

public physics_spawned(id)
{
	ts_set_physics_speed(id, 0.5)
	bench_wait_until("physics_sent", "physics_shown", 2.0, id)
}

public bool:physics_sent(id)
{
	return Near(LastFloat(id, "TSSlowMo"), 50.0)
}

public physics_shown(id)
{
	bench_next("physics_moving", 0.5, id)
}

public physics_moving(id)
{
	// The player's own movement keeps its rate.
	ASSERT_NEAR(SlowFactor(id), 1.0)
	bench_pass()
}

// --- ts_set_speed ----------------------------------------------------------------------------

public test_set_speed_scales_the_player_and_his_aura()
{
	g_Other = bench_puppet("bystander")
	ASSERT(g_Other > 0)
	bench_puppet_spawn(g_Other, "speed_other_spawned", 20.0, "respawn")
}

public speed_other_spawned(other)
{
	new id = bench_puppet("runner")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "speed_spawned", 20.0, "respawn")
}

public speed_spawned(id)
{
	bench_next("speed_settled", 1.0, id)
}

public speed_settled(id)
{
	pev(id, pev_origin, g_Start)
	// The bystander waits out of the way, 200 units up.
	new Float:far[3]
	far = g_Start
	far[2] += 200.0
	engfunc(EngFunc_SetOrigin, g_Other, far)
	g_Turns = 0
	speed_run(id)
}

// How far he runs in half a second at the normal rate, turning until he faces open ground.
public speed_run(id)
{
	new Float:angles[3]
	angles[1] = 90.0 * g_Turns
	bench_puppet_angles(id, angles)
	bench_puppet_input(id, 0, 400.0)
	bench_next("speed_ran", 0.5, id)
}

public speed_ran(id)
{
	bench_puppet_input(id, 0)
	new Float:origin[3]
	pev(id, pev_origin, origin)
	g_Distance = get_distance_f(origin, g_Start)
	engfunc(EngFunc_SetOrigin, id, g_Start)
	set_pev(id, pev_velocity, Float:{0.0, 0.0, 0.0})
	if (g_Distance < 50.0 && ++g_Turns < 4)
	{
		bench_next("speed_run", 0.3, id)
		return
	}
	new what[64]
	formatex(what, charsmax(what), "ran %.1f at the normal rate", g_Distance)
	ASSERT(bench_check(g_Distance >= 50.0, what))
	bench_next("speed_back", 0.5, id)
}

public speed_back(id)
{
	// Half speed for him and anyone within 64 units, for three seconds.
	ASSERT_EQ(ts_set_speed(id, 0.5, 64.0, 3.0), 1)
	g_SpeedEnd = get_gametime() + 3.0
	new Float:near[3]
	near = g_Start
	near[0] += 48.0
	engfunc(EngFunc_SetOrigin, g_Other, near)
	bench_next("speed_slowed", 0.5, id)
}

public speed_slowed(id)
{
	ASSERT_NEAR(SlowFactor(id), 0.5)
	ASSERT_NEAR(SlowFactor(g_Other), 0.5)
	ASSERT_NEAR(LastFloat(id, "TSSlowMo"), 50.0)
	ASSERT_NEAR(Float:ts_is_in_slowmo(id), g_SpeedEnd)

	// Out of the aura, the bystander goes back to normal; the runner runs half as far.
	new Float:far[3]
	far = g_Start
	far[2] += 200.0
	engfunc(EngFunc_SetOrigin, g_Other, far)
	new Float:angles[3]
	angles[1] = 90.0 * g_Turns
	bench_puppet_angles(id, angles)
	bench_puppet_input(id, 0, 400.0)
	bench_next("speed_ran_slow", 0.5, id)
}

public speed_ran_slow(id)
{
	bench_puppet_input(id, 0)
	new Float:origin[3]
	pev(id, pev_origin, origin)
	new Float:distance = get_distance_f(origin, g_Start)
	new what[64]
	formatex(what, charsmax(what), "ran %.1f slowed, %.1f at the normal rate", distance, g_Distance)
	ASSERT(bench_check(distance > g_Distance * 0.3 && distance < g_Distance * 0.7, what))
	ASSERT_NEAR(SlowFactor(g_Other), 1.0)
	bench_next("speed_worn_off", 2.5, id)
}

public speed_worn_off(id)
{
	ASSERT_NEAR(SlowFactor(id), 1.0)
	ASSERT_NEAR(SlowFactor(g_Other), 1.0)
	ASSERT_EQ(ts_is_in_slowmo(id), 0)
	bench_pass()
}

public test_set_speed_zero_freezes()
{
	new id = bench_puppet("frozen")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "frozen_spawned", 20.0, "respawn")
}

public frozen_spawned(id)
{
	ts_set_speed(id, 0.0, 10.0, 2.0)
	bench_next("frozen_settled", 0.5, id)
}

public frozen_settled(id)
{
	pev(id, pev_origin, g_Start)
	bench_puppet_input(id, 0, 400.0)
	bench_next("frozen_tried", 0.5, id)
}

public frozen_tried(id)
{
	bench_puppet_input(id, 0)
	new Float:origin[3]
	pev(id, pev_origin, origin)
	ASSERT(get_distance_f(origin, g_Start) < 1.0)
	bench_pass()
}

public test_set_speed_negative()
{
	new id = bench_puppet("backwards")
	ASSERT(id > 0)
	bench_next("refused", 0.0)
	bench_expect_error("Invalid speed")
	ts_set_speed(id, -1.0, 0.0, 1.0)
}

public refused()
{
	bench_pass()
}
