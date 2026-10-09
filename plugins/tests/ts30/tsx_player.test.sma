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
#include <xs>
#include <tsx>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids and the superjump powerup.
#define GLOCK18		1
#define M61			24
#define KNIFE		25
#define TS_SUPERJUMP	256

new g_Other
new Float:g_Start[3]
new Float:g_SpeedEnd
new Float:g_Yaw
new Float:g_Room
new Float:g_Distance
new g_Thrown[4]
new Float:g_Normal[4]

// ts_createpwup as a plugin built with the include before the origin was declared calls it.
native ts_createpwup_typeonly(pwup) = ts_createpwup;

public plugin_init()
{
	register_plugin("TSX Player Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_teardown()
{
	// Thrown knives and dropped guns stay a while after the test.
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "knife")))
		engfunc(EngFunc_RemoveEntity, ent)
	ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "WorldGun")))
		engfunc(EngFunc_RemoveEntity, ent)
}

Float:SlowFactor(id)
{
	new Float:value
	pev(id, pev_fuser1, value)
	return value
}

// The rate the game eases his fuser1 to (CBasePlayer::GoSlow); fuser1 gets there over a few frames.
Float:SlowTarget(id)
{
	return get_ent_data_float(id, "CBasePlayer", "m_flSlowMotionGo")
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

Float:MaxSpeed(id)
{
	new Float:speed
	pev(id, pev_maxspeed, speed)
	return speed
}

// GetSpeedBySlots in the game: 210 with no free slots, 330 from 81 up, truncated.
SpeedBySlots(slots)
{
	if (slots > 80)
		return 330
	return floatround(float(slots) * 120.0 / 81.0 + 210.0, floatround_tozero)
}

// A powerup made the way ts_createpwup makes one, through fakemeta.
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

public test_setting_slots_moves_the_speed()
{
	new id = bench_puppet("loader")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "loader_spawned", 20.0, "respawn")
}

public loader_spawned(id)
{
	bench_next("loader_settled", 0.5, id)
}

public loader_settled(id)
{
	// The speed the game gave him for his free slots.
	new slots = ts_getuserslots(id)
	new speed = floatround(MaxSpeed(id))
	ASSERT_EQ(speed, SpeedBySlots(slots))

	// Fewer free slots slow him as the game's own pickups would (239 for 20).
	ts_setuserslots(id, 20)
	ASSERT_EQ(floatround(MaxSpeed(id)), SpeedBySlots(20))

	// And back.
	ts_setuserslots(id, slots)
	ASSERT_EQ(floatround(MaxSpeed(id)), speed)
	bench_pass()
}

// A pickup sets the speed for what he then carries, truncated to a whole number: a Desert Eagle
// leaves 66 free slots, 307.8 by the formula, so 307 (GetSpeedBySlots, the fistp chopping).
#define DESERT_EAGLE	12

public test_pickup_speed_is_truncated()
{
	new id = bench_puppet("deagle")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "deagle_spawned", 20.0, "respawn")
}

public deagle_spawned(id)
{
	ts_giveweapon(id, DESERT_EAGLE, 0, 0)
	bench_next("deagle_carried", 0.5, id)
}

public deagle_carried(id)
{
	new slots = ts_getuserslots(id)
	server_print("tsx_player: %d free slots, maxspeed %.3f", slots, MaxSpeed(id))
	// a load whose speed has a fraction of a half or more, so rounding would show
	ASSERT(slots <= 80)
	ASSERT(float(slots) * 120.0 / 81.0 - float(floatround(float(slots) * 120.0 / 81.0, floatround_floor)) >= 0.5)
	ASSERT(MaxSpeed(id) == float(SpeedBySlots(slots)))
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

// A powerup dropped on the player; he picks it up once it lands. It starts 48 units over his
// origin: one put at his origin starts inside his hitboxes and never lands. Dropped there while he
// still falls from the spawn point, it lands on him only from a spot high enough over the floor
// (ts_lobby's 784 0 112 is not), so he settles first.
DropPowerup(id, const type[])
{
	new ent = CreatePowerup(type)
	if (ent)
	{
		new Float:origin[3]
		pev(id, pev_origin, origin)
		origin[2] += 48.0
		engfunc(EngFunc_SetOrigin, ent, origin)
	}
	return ent
}

public jumper_spawned(id)
{
	bench_wait_until("on_ground", "jumper_settled", 2.0, id)
}

public bool:on_ground(id)
{
	return (pev(id, pev_flags) & FL_ONGROUND) != 0
}

public jumper_settled(id)
{
	ASSERT_EQ(ts_has_superjump(id), 0)
	ASSERT_EQ(ts_has_fupowerup(id), 0)
	ASSERT(DropPowerup(id, "256") > 0)
	ASSERT(DropPowerup(id, "4") > 0)
	bench_wait_until("jumper_has_both", "jumper_took", 4.0, id)
}

public bool:jumper_has_both(id)
{
	// The game sets them as he touches each and tells him (PwUp).
	return ts_has_superjump(id) == 1 && ts_has_fupowerup(id) == 1 && bench_msg_count(id, "PwUp") >= 2
}

public jumper_took(id)
{
	bench_pass()
}

public test_createpwup_puts_a_powerup_a_player_picks_up()
{
	new id = bench_puppet("collector")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "collector_spawned", 20.0, "respawn")
}

public collector_spawned(id)
{
	bench_wait_until("on_ground", "collector_settled", 2.0, id)
}

public collector_settled(id)
{
	ASSERT_EQ(ts_has_superjump(id), 0)
	// Just over his head: it lands on him.
	new Float:origin[3]
	pev(id, pev_origin, origin)
	origin[2] += 48.0
	new ent = ts_createpwup(TS_SUPERJUMP, origin)
	ASSERT(ent > 0)
	new classname[32]
	pev(ent, pev_classname, classname, charsmax(classname))
	ASSERT_STR_EQ(classname, "ts_powerup")

	// Where he stands, and linked there for the world to touch.
	new Float:where[3], Float:absmin[3], Float:absmax[3]
	pev(ent, pev_origin, where)
	pev(ent, pev_absmin, absmin)
	pev(ent, pev_absmax, absmax)
	ASSERT(get_distance_f(where, origin) < 0.01)
	ASSERT(absmin[0] <= origin[0] && origin[0] <= absmax[0] && absmin[1] <= origin[1] && origin[1] <= absmax[1])
	bench_wait_until("collector_has_it", "collector_took", 4.0, id)
}

public bool:collector_has_it(id)
{
	// He has it, and the game told him he picked it up (PwUp).
	return ts_has_superjump(id) == 1 && bench_msg_count(id, "PwUp") >= 1
}

public collector_took(id)
{
	bench_pass()
}

// The call a plugin built with the old include makes: the type alone.
CreateTypeOnly(type)
{
	return ts_createpwup_typeonly(type)
}

public test_createpwup_with_the_type_alone()
{
	new id = bench_puppet("giftee")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "giftee_landed", 20.0, "respawn")
}

public giftee_landed(id)
{
	bench_wait_until("on_ground", "giftee_spawned", 2.0, id)
}

public giftee_spawned(id)
{
	ASSERT_EQ(ts_has_fupowerup(id), 0)
	new ent = CreateTypeOnly(TSPWUP_KUNGFU)
	ASSERT(ent > 0)

	// It stays where Spawn put it, for the plugin to move.
	new Float:origin[3]
	pev(ent, pev_origin, origin)
	new what[96]
	formatex(what, charsmax(what), "expected 0 0 0, received the bits %x %x %x", origin[0], origin[1], origin[2])
	ASSERT(bench_check(origin[0] == 0.0 && origin[1] == 0.0 && origin[2] == 0.0, what))

	// A working powerup: moved over his head, it lands on him.
	pev(id, pev_origin, origin)
	origin[2] += 48.0
	engfunc(EngFunc_SetOrigin, ent, origin)
	bench_wait_until("giftee_has_it", "giftee_took", 4.0, id)
}

public bool:giftee_has_it(id)
{
	return ts_has_fupowerup(id) == 1
}

public giftee_took(id)
{
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

// How far a player could walk from start along yaw before something stops him, up to 1000 units.
Float:Room(const Float:start[3], Float:yaw, ignore)
{
	new Float:angles[3], Float:dir[3], Float:end[3], Float:fraction
	angles[1] = yaw
	angle_vector(angles, ANGLEVECTOR_FORWARD, dir)
	xs_vec_mul_scalar(dir, 1000.0, dir)
	xs_vec_add(start, dir, end)
	engfunc(EngFunc_TraceHull, start, end, IGNORE_MONSTERS, HULL_HUMAN, ignore, 0)
	get_tr2(0, TR_flFraction, fraction)
	return fraction * 1000.0
}

// Where the bystander stands out of the aura: at the far end of the runner's open ground, where he
// stays (he would fall back from a spot in the air) and the runner never comes near him.
OutOfTheAura(Float:spot[3])
{
	new Float:angles[3], Float:dir[3]
	angles[1] = g_Yaw
	angle_vector(angles, ANGLEVECTOR_FORWARD, dir)
	xs_vec_mul_scalar(dir, g_Room - 16.0, dir)
	xs_vec_add(g_Start, dir, spot)
}

public speed_settled(id)
{
	pev(id, pev_origin, g_Start)
	// He runs the way with the most open ground, so nothing cuts either run short.
	g_Room = 0.0
	for (new i = 0; i < 8; i++)
	{
		new Float:room = Room(g_Start, 45.0 * i, id)
		if (room > g_Room)
		{
			g_Room = room
			g_Yaw = 45.0 * i
		}
	}
	new what[64]
	formatex(what, charsmax(what), "%.0f units of open ground", g_Room)
	ASSERT(bench_check(g_Room >= 300.0, what))

	new Float:far[3]
	OutOfTheAura(far)
	engfunc(EngFunc_SetOrigin, g_Other, far)

	// How far he runs in half a second at the normal rate.
	new Float:angles[3]
	angles[1] = g_Yaw
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
	ASSERT_NEAR(SlowTarget(id), 0.5)
	ASSERT_NEAR(SlowTarget(g_Other), 0.5)
	ASSERT_NEAR(LastFloat(id, "TSSlowMo"), 50.0)
	ASSERT_NEAR(Float:ts_is_in_slowmo(id), g_SpeedEnd)

	// Out of the aura, the bystander goes back to normal; the runner runs half as far.
	new Float:far[3]
	OutOfTheAura(far)
	engfunc(EngFunc_SetOrigin, g_Other, far)
	new Float:angles[3]
	angles[1] = g_Yaw
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
	ASSERT_NEAR(SlowTarget(g_Other), 1.0)
	bench_wait_until("speed_ended", "speed_worn_off", 3.0, id)
}

public bool:speed_ended(id)
{
	return ts_is_in_slowmo(id) == 0
}

public speed_worn_off(id)
{
	// Once the time runs out both go back to the normal rate, and the game eases them there.
	ASSERT(get_gametime() >= g_SpeedEnd)
	ASSERT_NEAR(SlowTarget(id), 1.0)
	ASSERT_NEAR(SlowTarget(g_Other), 1.0)
	bench_wait_until("speed_eased", "speed_normal", 2.0, id)
}

public bool:speed_eased(id)
{
	return Near(SlowFactor(id), 1.0) && Near(SlowFactor(g_Other), 1.0)
}

public speed_normal(id)
{
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

// --- ts_set_speed and what the player throws -------------------------------------------------
//
// The game's slow motion slows the grenades, thrown knives and dropped guns around its player as well:
// their rate is pev->fuser1, and their physics scale velocity and gravity by it (gravity by its square).

Float:Fuser1(ent)
{
	new Float:value
	pev(ent, pev_fuser1, value)
	return value
}

Float:Gravity(ent)
{
	new Float:value
	pev(ent, pev_gravity, value)
	return value
}

bool:Moving(ent)
{
	new Float:velocity[3]
	pev(ent, pev_velocity, velocity)
	return vector_length(velocity) > 0.0
}

FindClass(const classname[])
{
	return max(engfunc(EngFunc_FindEntityByString, -1, "classname", classname), 0)
}

// Throwing a little up, the way with the most room, keeps it in the air a while.
LookUp(id)
{
	new Float:eye[3], Float:ofs[3]
	pev(id, pev_origin, eye)
	pev(id, pev_view_ofs, ofs)
	xs_vec_add(eye, ofs, eye)

	new Float:angles[3], Float:best[3], Float:most = -1.0
	angles[0] = -20.0
	for (new i = 0; i < 8; i++)
	{
		angles[1] = 45.0 * i
		new Float:dir[3], Float:end[3], Float:fraction
		angle_vector(angles, ANGLEVECTOR_FORWARD, dir)
		xs_vec_mul_scalar(dir, 4000.0, dir)
		xs_vec_add(eye, dir, end)
		engfunc(EngFunc_TraceLine, eye, end, IGNORE_MONSTERS, id, 0)
		get_tr2(0, TR_flFraction, fraction)
		if (fraction > most)
		{
			most = fraction
			best = angles
		}
	}
	bench_puppet_angles(id, best)
}

// In the air at the normal rate: its gravity, then half speed for a second around the thrower.
// Out of the aura it is left alone; in it, it slows at its next think (every 0.1 s).
SlowInFlight(id, ent)
{
	g_Thrown[0] = ent
	ASSERT(bench_check(Moving(ent), "it moves"))
	ASSERT_NEAR(Fuser1(ent), 1.0)
	g_Normal[0] = Gravity(ent)
	ASSERT(g_Normal[0] > 0.0)

	ASSERT_EQ(ts_set_speed(id, 0.5, 1.0, 1.0), 1)
	ASSERT_NEAR(Fuser1(ent), 1.0)
	ASSERT_EQ(ts_set_speed(id, 0.5, 2000.0, 1.0), 1)
	ASSERT_NEAR(Fuser1(ent), 0.5)
	bench_wait_until("thrown_physics_slowed", "thrown_slowed", 0.5, id)
}

public bool:thrown_physics_slowed(id)
{
	new ent = g_Thrown[0]
	return pev_valid(ent) && Near(Gravity(ent), g_Normal[0] * 0.25)
}

public thrown_slowed(id)
{
	ASSERT_NEAR(Fuser1(g_Thrown[0]), 0.5)
	bench_wait_until("thrown_speed_over", "thrown_worn_off", 2.0, id)
}

public bool:thrown_speed_over(id)
{
	return ts_is_in_slowmo(id) == 0
}

public thrown_worn_off(id)
{
	new ent = g_Thrown[0]
	if (pev_valid(ent))
		ASSERT_NEAR(Fuser1(ent), 1.0)
	bench_pass()
}

public test_set_speed_slows_a_dropped_gun()
{
	new id = bench_puppet("dropper")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "dropper_spawned", 20.0, "respawn")
}

public dropper_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	LookUp(id)
	bench_next("dropper_ready", 1.0, id)
}

public dropper_ready(id)
{
	bench_puppet_cmd(id, "drop")
	bench_wait_until("gun_dropped", "gun_flying", 1.0, id)
}

public bool:gun_dropped(id)
{
	return FindClass("WorldGun") != 0
}

public gun_flying(id)
{
	SlowInFlight(id, FindClass("WorldGun"))
}

public test_set_speed_slows_a_thrown_knife()
{
	new id = bench_puppet("knifer")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "knifer_spawned", 20.0, "respawn")
}

public knifer_spawned(id)
{
	ts_giveweapon(id, KNIFE, 1, 0)
	LookUp(id)
	bench_next("knifer_ready", 1.0, id)
}

public knifer_ready(id)
{
	bench_puppet_input(id, IN_ATTACK2)
	bench_wait_until("knife_thrown", "knife_flying", 2.0, id)
}

public bool:knife_thrown(id)
{
	return FindClass("knife") != 0
}

public knife_flying(id)
{
	bench_puppet_input(id, 0)
	// A thrown knife flies at 1785 units a second and sticks in the first wall it meets, which on
	// some spawn points comes before its next think; it is slowed down to stay in the air a while.
	new ent = FindClass("knife")
	new Float:velocity[3]
	pev(ent, pev_velocity, velocity)
	velocity[2] = 0.0
	xs_vec_normalize(velocity, velocity)
	xs_vec_mul_scalar(velocity, 150.0, velocity)
	velocity[2] = 100.0
	set_pev(ent, pev_velocity, velocity)
	SlowInFlight(id, ent)
}

public test_set_speed_slows_a_grenade()
{
	new id = bench_puppet("bowler")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "bowler_spawned", 20.0, "respawn")
}

public bowler_spawned(id)
{
	ts_giveweapon(id, M61, 1, 0)
	LookUp(id)
	bench_next("bowler_pull", 1.0, id)
}

public bowler_pull(id)
{
	bench_puppet_input(id, IN_ATTACK)
	bench_next("bowler_release", 0.3, id)
}

public bowler_release(id)
{
	bench_puppet_input(id, 0)
	bench_wait_until("grenade_thrown", "grenade_flying", 2.0, id)
}

public bool:grenade_thrown(id)
{
	return FindClass("grenade") != 0
}

public grenade_flying(id)
{
	SlowInFlight(id, FindClass("grenade"))
}
