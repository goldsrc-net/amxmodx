// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for what the original The Specialists 3.0 does with a player's powerup each frame: a dead
// player's powerup goes back into the world where he lies, so does a spectator's, and a running
// superjump powerup lowers his gravity; whatever lowers it, landing puts it back. A map with
// powerups of its own gets no random ones. PreThink writes the animation rate as the slow factor
// every frame, and eases the slow factor from 0 without lifting it first. A super jump's landing
// plants him with a varying pitch, or with duck held rolls.
// ../ts_powerup_state.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <amxxbench>

new bool:g_Had[2048]
new Float:g_Corpse[3]
// The superjump test's player, and his gravity after his last PreThink (-1 until one has run).
new g_Floater
new Float:g_PreGravity
// The animation rate test's player, and his rate after his last PreThink.
new g_Rated
new Float:g_PreRate
// The slow factor test's player, and his fuser1 after his first PreThink (-1 until then).
new g_Eased
new Float:g_PreSlow

public plugin_init()
{
	register_plugin("TS Powerup State Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_forward(FM_PlayerPreThink, "on_prethink", 1)
	register_forward(FM_EmitSound, "on_land_sound")
	register_forward(FM_CreateEntity, "on_create", 1)
}

// The random powerups test notes every entity made while it watches.
new bool:g_Watch
new g_Made[256]
new g_MadeCount

public on_create()
{
	if (g_Watch && g_MadeCount < sizeof(g_Made))
		g_Made[g_MadeCount++] = get_orig_retval()
	return FMRES_IGNORED
}

public on_prethink(id)
{
	if (id == g_Floater && g_Floater)
		pev(id, pev_gravity, g_PreGravity)
	if (id == g_Rated && g_Rated)
		pev(id, pev_framerate, g_PreRate)
	if (id == g_Eased && g_Eased && g_PreSlow < 0.0)
		pev(id, pev_fuser1, g_PreSlow)
	return FMRES_IGNORED
}

public bench_teardown()
{
	g_Floater = 0
	// The powerups the dead left behind.
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_powerup")))
		if (ent < sizeof(g_Had) && !g_Had[ent])
			engfunc(EngFunc_RemoveEntity, ent)
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

// Notes the powerups already in the world (the map's).
MarkPowerups()
{
	arrayset(g_Had, false, sizeof(g_Had))
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_powerup")))
		if (ent < sizeof(g_Had))
			g_Had[ent] = true
}

// A powerup that was not in the world before, within reach of where the player died.
NewPowerupAtCorpse()
{
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_powerup")))
	{
		if (ent >= sizeof(g_Had) || g_Had[ent])
			continue
		new Float:origin[3]
		pev(ent, pev_origin, origin)
		if (get_distance_f(origin, g_Corpse) < 96.0)
			return ent
	}
	return 0
}

public bool:is_dead(id)
{
	return !is_user_alive(id)
}

public died(id)
{
	pev(id, pev_origin, g_Corpse)
	bench_next("after_death", 0.5, id)
}

public after_death(id)
{
	ASSERT(NewPowerupAtCorpse() != 0)
	bench_pass()
}

// A player who dies with a slow motion running leaves it where he lies.
public test_running_powerup_drops_where_he_dies()
{
	new id = bench_puppet("runner")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "runner_spawned", 20.0, "respawn")
}

public runner_spawned(id)
{
	ts_set_fakeslowmo(id, 10.0)
	bench_next("runner_running", 0.5, id)
}

public runner_running(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), TSPWUP_SLOWMO)
	MarkPowerups()
	user_kill(id)
	bench_wait_until("is_dead", "died", 3.0, id)
}

// So does one who dies holding a powerup he has not used.
public test_held_powerup_drops_where_he_dies()
{
	new id = bench_puppet("holder")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "holder_spawned", 20.0, "respawn")
}

public holder_spawned(id)
{
	bench_next("holder_settled", 0.5, id)
}

public holder_settled(id)
{
	// Just over his head: it lands on him.
	new Float:origin[3]
	pev(id, pev_origin, origin)
	origin[2] += 48.0
	ASSERT(ts_createpwup(TSPWUP_DFIRERATE, origin) > 0)
	bench_wait_message(id, "PwUp", "", "holder_holds", 4.0)
}

public holder_holds(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	MarkPowerups()
	user_kill(id)
	bench_wait_until("is_dead", "died", 3.0, id)
}

// A spectator's powerup is handled like a dead player's: slow motion running on a player who has not
// joined yet goes back into the world where he is.
public test_spectators_powerup_drops_where_he_is()
{
	new id = bench_puppet("watcher")
	ASSERT(id > 0)
	bench_next("watcher_spectating", 0.5, id)
}

public watcher_spectating(id)
{
	ASSERT(!is_user_alive(id))
	ASSERT(pev(id, pev_iuser1) != 0)
	MarkPowerups()
	pev(id, pev_origin, g_Corpse)
	ts_set_fakeslowmo(id, 10.0)
	bench_next("watcher_after", 0.5, id)
}

public watcher_after(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	ASSERT(NewPowerupAtCorpse() != 0)
	bench_pass()
}

// A running superjump powerup, which only a plugin can start, gives low gravity until it ends. The
// powerup sets it in each PreThink (UpdatePowerUpState), so it is read there: on TS 3.0 PostThink
// puts a player on the ground back to 1.0 every frame (@0x8186f), so a read between frames gave
// 0.15 only while he was still falling from his spawn spot.
public test_superjump_powerup_lowers_gravity()
{
	new id = bench_puppet("floater")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "floater_spawned", 20.0, "respawn")
}

public floater_spawned(id)
{
	ts_set_fakeslowmo(id, 3.0)
	ts_force_run_powerup(id, TSPWUP_SUPERJUMP)
	g_PreGravity = -1.0
	g_Floater = id
	bench_next("floater_running", 0.5, id)
}

public floater_running(id)
{
	ASSERT_NEAR(g_PreGravity, 0.15)
	bench_next("floater_over", 3.0, id)
}

public floater_over(id)
{
	ASSERT_EQ(ts_is_running_powerup(id), 0)
	ASSERT_NEAR(g_PreGravity, 1.0)
	new Float:gravity
	pev(id, pev_gravity, gravity)
	ASSERT_NEAR(gravity, 1.0)
	bench_pass()
}

// Whatever lowers a player's gravity (a plugin here), the game puts it back to 1.0 once he is on the
// ground: PostThink sets it for a player on the ground every frame (@0x8186f). In the air it stays.
public test_landing_gives_normal_gravity_back()
{
	new id = bench_puppet("lander")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "lander_spawned", 20.0, "respawn")
}

public bool:on_ground(id)
{
	return (pev(id, pev_flags) & FL_ONGROUND) != 0
}

public lander_spawned(id)
{
	bench_wait_until("on_ground", "lander_standing", 3.0, id)
}

public lander_standing(id)
{
	// 48 units up with half gravity: he falls for about half a second.
	new Float:origin[3]
	pev(id, pev_origin, origin)
	origin[2] += 48.0
	engfunc(EngFunc_SetOrigin, id, origin)
	set_pev(id, pev_flags, pev(id, pev_flags) & ~FL_ONGROUND)
	set_pev(id, pev_gravity, 0.5)
	bench_next("lander_falling", 0.1, id)
}

public lander_falling(id)
{
	ASSERT_FALSE(on_ground(id))
	new Float:gravity
	pev(id, pev_gravity, gravity)
	ASSERT_NEAR(gravity, 0.5)
	bench_wait_until("on_ground", "lander_landed", 3.0, id)
}

public lander_landed(id)
{
	new Float:gravity
	pev(id, pev_gravity, gravity)
	ASSERT_NEAR(gravity, 1.0)
	bench_pass()
}

// A map with powerups of its own (ts_lobby) gets no random ones: the first ts_powerup to spawn on
// a map turns them off (CTSPowerUp::Spawn, rules+1), so in 22 s, more than the 20 s between two
// random ones, the game makes none.
public test_map_powerups_leave_out_random_ones()
{
	bench_set_timeout(40.0)
	ASSERT(engfunc(EngFunc_FindEntityByString, -1, "classname", "ts_powerup") > 0)
	g_MadeCount = 0
	g_Watch = true
	bench_next("random_watched", 22.0, 0)
}

public random_watched(id)
{
	g_Watch = false
	new classname[32]
	for (new i = 0; i < g_MadeCount; i++)
	{
		if (!pev_valid(g_Made[i]))
			continue
		pev(g_Made[i], pev_classname, classname, charsmax(classname))
		if (equal(classname, "ts_powerup"))
		{
			bench_fail("the game made powerup %d", g_Made[i])
			return
		}
	}
	server_print("ts_powerup_state: %d entities made in 22 s, no powerup", g_MadeCount)
	bench_pass()
}

// The slowmatch cvar slows nobody by itself: the original's CTSGameRules::Think (0x67204) has no
// per-frame slow motion for it (it only weighs the random powerup draw and the kill reward), so
// with slowmatch at 0.5 a player keeps his normal rate (fuser1 1.0) for two seconds.
new Float:g_Slowmatch

public test_slowmatch_slows_nobody()
{
	g_Slowmatch = get_cvar_float("slowmatch")
	new id = bench_puppet("unslowed")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "unslowed_spawned", 20.0, "respawn")
}

public unslowed_spawned(id)
{
	set_cvar_float("slowmatch", 0.5)
	bench_next("unslowed_later", 2.0, id)
}

public unslowed_later(id)
{
	set_cvar_float("slowmatch", g_Slowmatch)
	new Float:rate
	pev(id, pev_fuser1, rate)
	server_print("ts_powerup_state: fuser1 with slowmatch 0.5: %f", rate)
	ASSERT_NEAR(rate, 1.0)
	bench_pass()
}

// PreThink writes the animation rate as the slow factor every frame, for every player (0x80999):
// a living player's rate set to 0.3 is 1.0 again after his next PreThink.
public test_prethink_writes_the_animation_rate()
{
	g_Rated = 0
	new id = bench_puppet("rated")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "rated_alive", 20.0, "respawn")
}

public rated_alive(id)
{
	bench_next("rated_settled", 0.5, id)
}

public rated_settled(id)
{
	g_PreRate = -1.0
	g_Rated = id
	set_pev(id, pev_framerate, 0.3)
	bench_next("rated_after", 0.1, id)
}

public rated_after(id)
{
	g_Rated = 0
	new Float:slow
	pev(id, pev_fuser1, slow)
	server_print("ts_powerup_state: frame rate after PreThink %.3f (slow factor %.3f)", g_PreRate, slow)
	ASSERT_NEAR(g_PreRate, 1.0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// A super jump's landing (PostThink's landing block, 0x818ec: on the ground with the wheel-done bit,
// 0x100000, in iuser4) without duck held plants him with player/superjump-land.wav at pitch 95 plus
// 0 to 31 (0x81997). The bit is set by the test on a player standing still, four times.
#define IUSER4_WHEEL_DONE	0x100000
#define IUSER4_ROLL	0x40000
new g_Landed
new g_LandSounds
new g_LandPitch[8]
new g_Landings

public on_land_sound(ent, channel, const sample[], Float:volume, Float:attn, flags, pitch)
{
	if (ent == g_Landed && g_Landed && equal(sample, "player/superjump-land.wav") && g_LandSounds < sizeof(g_LandPitch))
		g_LandPitch[g_LandSounds++] = pitch
	return FMRES_IGNORED
}

public test_superjump_landing_pitch_varies()
{
	g_Landed = 0
	g_LandSounds = 0
	g_Landings = 0
	new id = bench_puppet("planter")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "planter_alive", 20.0, "respawn")
}

public planter_alive(id)
{
	bench_wait_until("on_ground", "planter_land", 3.0, id)
}

public planter_land(id)
{
	g_Landed = id
	set_pev(id, pev_iuser4, pev(id, pev_iuser4) | IUSER4_WHEEL_DONE)
	g_Landings++
	// the plant holds him 0.75 s
	bench_next(g_Landings < 4 ? "planter_land" : "planter_done", 1.2, id)
}

public planter_done(id)
{
	g_Landed = 0
	new not100 = 0, inRange = 0
	for (new i = 0; i < g_LandSounds; i++)
	{
		server_print("ts_powerup_state: landing %d pitch %d", i + 1, g_LandPitch[i])
		if (g_LandPitch[i] != 100)
			not100++
		if (g_LandPitch[i] >= 95 && g_LandPitch[i] <= 126)
			inRange++
	}
	ASSERT_EQ(g_LandSounds, 4)
	ASSERT_EQ(inRange, 4)
	ASSERT(not100 > 0)
	bench_pass()
}

// Landing from a super jump with duck held, running, rolls: the landing arms the roll's double-tap
// window (0x81940) before it tries the roll, so the ground roll goes on the first try and there is
// no plant and no landing sound.
public test_superjump_landing_with_duck_rolls()
{
	g_Landed = 0
	g_LandSounds = 0
	new id = bench_puppet("roller")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "roller_alive", 20.0, "respawn")
}

public roller_alive(id)
{
	// ducked and running, past the duck press's own 0.3 s window
	FaceOpenGround(id)
	bench_puppet_input(id, IN_DUCK, 400.0)
	bench_next("roller_running", 1.0, id)
}

// Face the puppet down the clearest of eight directions, so a spawn spot facing a wall does not
// leave him running on the spot (once in 42 runs he stood still and landed without speed).
FaceOpenGround(id)
{
	new Float:origin[3], Float:end[3], Float:angles[3], Float:frac, Float:best = -1.0
	pev(id, pev_origin, origin)
	for (new i = 0; i < 8; i++)
	{
		new Float:yaw = i * 45.0
		end[0] = origin[0] + floatcos(yaw, degrees) * 256.0
		end[1] = origin[1] + floatsin(yaw, degrees) * 256.0
		end[2] = origin[2]
		engfunc(EngFunc_TraceHull, origin, end, IGNORE_MONSTERS, HULL_HEAD, id, 0)
		get_tr2(0, TR_flFraction, frac)
		if (frac > best)
		{
			best = frac
			angles[1] = yaw
		}
	}
	server_print("ts_powerup_state: running toward yaw %.0f, clear for %.0f units", angles[1], best * 256.0)
	bench_puppet_angles(id, angles)
}

public roller_running(id)
{
	new Float:v[3]
	pev(id, pev_velocity, v)
	server_print("ts_powerup_state: ducked run at %.0f, on the ground %d, iuser4 %x", floatsqroot(v[0] * v[0] + v[1] * v[1]),
		on_ground(id), pev(id, pev_iuser4))
	ASSERT(on_ground(id))
	g_Landed = id
	set_pev(id, pev_iuser4, pev(id, pev_iuser4) | IUSER4_WHEEL_DONE)
	bench_next("roller_landed", 0.1, id)
}

public roller_landed(id)
{
	g_Landed = 0
	bench_puppet_input(id, 0)
	new iuser4 = pev(id, pev_iuser4)
	server_print("ts_powerup_state: after the duck landing iuser4 %x, landing sounds %d", iuser4, g_LandSounds)
	ASSERT(iuser4 & IUSER4_ROLL)
	ASSERT_EQ(g_LandSounds, 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// PreThink eases the slow factor (fuser1) from whatever it holds (0x80974): set to 0 on a living
// player at normal speed, it is still well under 1.0 after his next PreThink (it eases by at most
// seven frame times a frame), not lifted to 1.0 first.
public test_prethink_eases_slow_factor_from_zero()
{
	g_Eased = 0
	new id = bench_puppet("eased")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "eased_alive", 20.0, "respawn")
}

public eased_alive(id)
{
	bench_next("eased_settled", 0.5, id)
}

public eased_settled(id)
{
	g_PreSlow = -1.0
	g_Eased = id
	set_pev(id, pev_fuser1, 0.0)
	bench_next("eased_after", 0.0, id)
}

public eased_after(id)
{
	if (g_PreSlow < 0.0)
	{
		bench_next("eased_after", 0.0, id)
		return
	}
	g_Eased = 0
	server_print("ts_powerup_state: slow factor after one PreThink from 0: %.3f", g_PreSlow)
	ASSERT(g_PreSlow < 0.9)
	bench_pass()
}
