// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for server behaviour of The Specialists 3.0 that reTS has to match, second round: how a
// player dies (the death sequence and how long the body is dying, the throw of a heavy hit, the
// body staying solid, the slow-motion bit, the killer watched, no death sound), the red flash a
// hit makes, a spawn ending a spectate wait, the loadout cleared by a death, grenades and dropped
// guns slowed by a slow-motion powerup and by globalslow, the ground ammo pack taken once, the
// channel of a ground weapon's drop sound, and the points a briefcase capture announces.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//
// They pass in deathmatch and in teamplay.
//

#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <tsx>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1

new g_P[3]
new g_FriendlyFire
new g_Victim
new g_PainSounds
new g_DropChannel
new g_Ents[4]
new g_EntCount
new BenchMsg:g_Mark

public plugin_init()
{
	register_plugin("TS 3.0 Server Gap Tests 2", AMXX_VERSION_STR, "AMXX Dev Team")
	register_forward(FM_EmitSound, "on_emit_sound")
}

public bench_setup()
{
	g_FriendlyFire = get_cvar_num("mp_friendlyfire")
	g_Victim = 0
	g_PainSounds = 0
	g_DropChannel = -1
	g_EntCount = 0
}

public bench_teardown()
{
	set_cvar_num("mp_friendlyfire", g_FriendlyFire)
	for (new i = 0; i < g_EntCount; i++)
		if (pev_valid(g_Ents[i]))
			engfunc(EngFunc_RemoveEntity, g_Ents[i])
	g_EntCount = 0
	// the loose flags the briefcases left
	new flag
	while ((flag = engfunc(EngFunc_FindEntityByString, -1, "classname", "ts_flag")) > 0)
		engfunc(EngFunc_RemoveEntity, flag)
}

public on_emit_sound(ent, channel, const sample[])
{
	if (g_Victim && ent == g_Victim && contain(sample, "player/pl_pain") != -1)
		g_PainSounds++
	if (g_EntCount && ent == g_Ents[0] && equal(sample, "items/weapondrop1.wav"))
		g_DropChannel = channel
	return FMRES_IGNORED
}

// Kills puppet id as the world does, at once (a suicide right after spawning is refused).
Die(id)
{
	set_pev(id, pev_health, 1.0)
	ExecuteHamB(Ham_TakeDamage, id, 0, 0, 10.0, DMG_GENERIC)
}

// Whether puppet id was sent a WeaponInfo for weapon after the message mark.
bool:GivenAfter(id, BenchMsg:mark, weapon)
{
	new BenchMsg:msg = mark
	while ((msg = bench_msg_next(id, msg, "WeaponInfo")) != BenchMsg:0)
		if (bench_msg_int(msg, 0) == weapon)
			return true
	return false
}

// A new entity of classname, kept for the teardown to remove.
Make(const classname[])
{
	new ent = create_entity(classname)
	if (ent > 0)
		g_Ents[g_EntCount++] = ent
	return ent
}

// An info_target renamed "grenade" in front of puppet id's eyes, at normal speed (fuser1 1): the
// slow-motion code finds grenades by classname and slows them through CBaseEntity::GoSlow.
FakeGrenade(id)
{
	new ent = Make("info_target")
	if (ent <= 0)
		return 0
	set_pev(ent, pev_classname, "grenade")
	new Float:origin[3], Float:ofs[3]
	pev(id, pev_origin, origin)
	pev(id, pev_view_ofs, ofs)
	origin[2] += ofs[2]
	engfunc(EngFunc_SetOrigin, ent, origin)
	set_pev(ent, pev_fuser1, 1.0)
	return ent
}

Float:Fuser1(ent)
{
	new Float:f
	pev(ent, pev_fuser1, f)
	return f
}

bool:Near(Float:a, Float:b, Float:within = 0.01)
{
	return floatabs(a - b) < within
}

bool:IsDanceSequence(id, seq)
{
	return seq == lookup_sequence(id, "normal_die1") || seq == lookup_sequence(id, "normal_die2")
		|| seq == lookup_sequence(id, "normal_die3")
}

// --- dying -----------------------------------------------------------------------------------

// A light hit that is not in the legs turns the bullet dance on (TakeDamage @0x7fb11), so the
// death sequence is a normal_die* (1.5 s) and the body is dying until it ends, about 1.5 s.
public test_light_death_plays_the_dance_sequence()
{
	new id = bench_puppet("dancer")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "dance_spawned", 20.0, "respawn")
}

public dance_spawned(id)
{
	bench_next("dance_hit", 0.5, id)
}

public dance_hit(id)
{
	Die(id)
	ASSERT(IsDanceSequence(id, pev(id, pev_sequence)))
	ASSERT_EQ(pev(id, pev_deadflag), DEAD_DYING)
	bench_next("dance_still_dying", 1.2, id)
}

public dance_still_dying(id)
{
	ASSERT_EQ(pev(id, pev_deadflag), DEAD_DYING)
	bench_next("dance_done", 0.6, id)
}

public dance_done(id)
{
	ASSERT_EQ(pev(id, pev_deadflag), DEAD_RESPAWNABLE)
	bench_pass()
}

// A hit over 80 turns the dance off, and a body killed by a hit over 50 that does not dance is
// thrown up at 180 with half gravity (Killed @0x7f3b9); no normal_die* then.
public test_heavy_death_throws_the_body()
{
	new id = bench_puppet("thrown")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "thrown_spawned", 20.0, "respawn")
}

public thrown_spawned(id)
{
	bench_next("thrown_hit", 0.5, id)
}

public thrown_hit(id)
{
	set_pev(id, pev_health, 100.0)
	ExecuteHamB(Ham_TakeDamage, id, 0, 0, 100.0, DMG_GENERIC)
	new Float:v[3], Float:gravity
	pev(id, pev_velocity, v)
	pev(id, pev_gravity, gravity)
	ASSERT_FALSE(is_user_alive(id))
	ASSERT(Near(v[2], 180.0))
	ASSERT(Near(gravity, 0.5))
	ASSERT_FALSE(IsDanceSequence(id, pev(id, pev_sequence)))
	bench_pass()
}

// The dying body stays solid (no SOLID_NOT in Killed), its stunt bits are cleared but the
// slow-motion physics bit (iuser4 2) is set (@0x7f038), and no death sound plays (DeathSound has
// no caller).
public test_dying_body_is_solid_and_silent()
{
	new id = bench_puppet("solidbody")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "solid_spawned", 20.0, "respawn")
}

public solid_spawned(id)
{
	bench_next("solid_hit", 0.5, id)
}

public solid_hit(id)
{
	g_Victim = id
	Die(id)
	ASSERT_EQ(pev(id, pev_solid), SOLID_SLIDEBOX)
	ASSERT_EQ(pev(id, pev_iuser4), 2)
	ASSERT_EQ(g_PainSounds, 0)
	bench_pass()
}

// Killed by a player's own shot, iuser2 is the killer at once and the killer is his observer target
// (@0x7eeeb); the spectate that follows starts roaming (iuser1 3, iuser2 0) either way.
public test_killer_is_watched()
{
	set_cvar_num("mp_friendlyfire", 1)
	g_P[0] = bench_puppet("watcher")
	g_P[1] = bench_puppet("bystander")
	g_P[2] = bench_puppet("shooter")
	ASSERT(g_P[0] > 0 && g_P[1] > 0 && g_P[2] > 0)
	bench_puppet_spawn(g_P[0], "watch_one", 20.0, "respawn")
}

public watch_one(id)
{
	bench_puppet_spawn(g_P[1], "watch_two", 20.0, "respawn")
}

public watch_two(id)
{
	bench_puppet_spawn(g_P[2], "watch_three", 20.0, "respawn")
}

public watch_three(id)
{
	bench_next("watch_shot", 1.5, id)
}

public watch_shot(id)
{
	new v = g_P[0]
	set_pev(v, pev_health, 100.0)
	ExecuteHamB(Ham_TakeDamage, v, g_P[2], g_P[2], 200.0, DMG_BULLET)
	ASSERT_FALSE(is_user_alive(v))
	ASSERT_EQ(pev(v, pev_iuser2), g_P[2])
	bench_wait_until("watch_spectating", "watch_after", 8.0, v)
}


public bool:watch_spectating(id)
{
	return pev(id, pev_iuser1) != 0
}

public watch_after(id)
{
	ASSERT_EQ(pev(id, pev_iuser1), 3)
	ASSERT_EQ(pev(id, pev_iuser2), 0)
	bench_pass()
}

// --- the damage flash ------------------------------------------------------------------------

// A hit of a point or more flashes the screen red (UTIL_ScreenFade (150, 10, 10), 75, 0.3 s and
// 0.15 s held, @0x7fff8; TS sends it as TSFade) and does not kick the view.
public test_hit_flashes_red_without_a_kick()
{
	new id = bench_puppet("flashed")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "flash_spawned", 20.0, "respawn")
}

public flash_spawned(id)
{
	bench_next("flash_hit", 1.5, id)
}

public flash_hit(id)
{
	set_pev(id, pev_health, 100.0)
	new Float:zero[3]
	set_pev(id, pev_punchangle, zero)
	ExecuteHamB(Ham_TakeDamage, id, 0, 0, 5.0, DMG_GENERIC)
	new Float:punch[3]
	pev(id, pev_punchangle, punch)
	ASSERT(Near(punch[0], 0.0))
	new BenchMsg:msg = bench_msg_last(id, "TSFade")
	ASSERT(msg != BenchMsg:0)
	ASSERT_EQ(bench_msg_int(msg, 0), 1228)
	ASSERT_EQ(bench_msg_int(msg, 1), 614)
	ASSERT_EQ(bench_msg_int(msg, 3), 150)
	ASSERT_EQ(bench_msg_int(msg, 4), 10)
	ASSERT_EQ(bench_msg_int(msg, 5), 10)
	ASSERT_EQ(bench_msg_int(msg, 6), 75)
	bench_pass()
}

// --- spectating and the loadout --------------------------------------------------------------

// A spawn puts a spectating player in play: the original keeps no spectate flag across Spawn
// (TSInit clears iuser1 and PlayerSpawn equips, @0x790ac).
public test_spawn_ends_the_spectate_wait()
{
	new id = bench_puppet("spawnspec")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "spawnspec_spawned", 20.0, "respawn")
}

public spawnspec_spawned(id)
{
	bench_next("spawnspec_hit", 0.5, id)
}

public spawnspec_hit(id)
{
	Die(id)
	bench_wait_until("watch_spectating", "spawnspec_watching", 8.0, id)
}

public spawnspec_watching(id)
{
	ExecuteHamB(Ham_Spawn, id)
	bench_next("spawnspec_after", 0.5, id)
}

public spawnspec_after(id)
{
	ASSERT(is_user_alive(id))
	ASSERT_EQ(pev(id, pev_iuser1), 0)
	bench_pass()
}

// A death clears the loadout (Killed calls ResetArmament, @0x7eebb): the next spawn has only what
// the client sends again.
public test_death_clears_the_loadout()
{
	new id = bench_puppet("loadout")
	ASSERT(id > 0)
	bench_next("loadout_joined", 0.5, id)
}

public loadout_joined(id)
{
	bench_puppet_cmd(id, "tkw %d_0", GLOCK18)
	bench_puppet_spawn(id, "loadout_spawned", 20.0, "respawn")
}

public loadout_spawned(id)
{
	bench_next("loadout_armed", 1.5, id)
}

public loadout_armed(id)
{
	ASSERT(GivenAfter(id, BenchMsg:0, GLOCK18))
	g_Mark = bench_msg_last(id)
	Die(id)
	bench_wait_until("watch_spectating", "loadout_spectating", 8.0, id)
}

public loadout_spectating(id)
{
	bench_puppet_spawn(id, "loadout_respawned", 20.0, "respawn")
}

public loadout_respawned(id)
{
	bench_next("loadout_settled", 1.5, id)
}

public loadout_settled(id)
{
	ASSERT_FALSE(GivenAfter(id, g_Mark, GLOCK18))
	bench_pass()
}

// --- slow motion -----------------------------------------------------------------------------

// A slow-motion powerup slows the grenades its user sees to the rate he slows others to (0.35),
// with the players (SlowMotionFlow @0x86ea4).
public test_slow_motion_slows_a_grenade_in_sight()
{
	new id = bench_puppet("slowgren")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "slowgren_spawned", 20.0, "respawn")
}

public slowgren_spawned(id)
{
	new ent = FakeGrenade(id)
	ASSERT(ent > 0)
	ts_set_fakeslowmo(id, 10.0)
	bench_next("slowgren_after", 1.2, id)
}

public slowgren_after(id)
{
	ASSERT(Near(Fuser1(g_Ents[0]), 0.35, 0.02))
	bench_pass()
}

// globalslow slows every grenade with the players and turning it off puts it back to 1
// (GlobalSlowMotion2 @0x69720).
public test_globalslow_slows_grenades()
{
	new id = bench_puppet("globgren")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "globgren_spawned", 20.0, "respawn")
}

public globgren_spawned(id)
{
	ASSERT(FakeGrenade(id) > 0)
	server_cmd("globalslow 50")
	server_exec()
	bench_next("globgren_slowed", 1.2, id)
}

public globgren_slowed(id)
{
	new Float:slowed = Fuser1(g_Ents[0])
	server_cmd("globalslow 100")
	server_exec()
	ASSERT(Near(slowed, 0.5, 0.02))
	bench_next("globgren_back", 1.2, id)
}

public globgren_back(id)
{
	ASSERT(Near(Fuser1(g_Ents[0]), 1.0))
	bench_pass()
}

// --- ground pickups --------------------------------------------------------------------------

// A ground ammo pack gives its rounds once and is gone until it falls again (WaitTouch @0xa2f40);
// it is not a station that refills on every touch. Dropped above his head, it lands on him.
public test_ground_ammo_is_taken_once()
{
	new id = bench_puppet("ammotaker")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "ammo_spawned", 20.0, "respawn")
}

public ammo_spawned(id)
{
	bench_next("ammo_place", 1.0, id)
}

public ammo_place(id)
{
	new ent = Make("ts_groundammo")
	ASSERT(ent > 0)
	new key[8]
	for (new cal = 1; cal < 16; cal++)
	{
		formatex(key, charsmax(key), "mags%d", cal)
		DispatchKeyValue(ent, key, "1")
	}
	new Float:origin[3]
	pev(id, pev_origin, origin)
	origin[2] += 80.0
	engfunc(EngFunc_SetOrigin, ent, origin)
	DispatchSpawn(ent)
	bench_wait_until("ammo_gone", "ammo_taken", 4.0, ent)
}

public bool:ammo_gone(ent)
{
	return (pev(ent, pev_effects) & EF_NODRAW) != 0
}

public ammo_taken(ent)
{
	bench_pass()
}

// A ground weapon lands with its drop sound on CHAN_STATIC (Fall @0xa2150).
public test_ground_weapon_drop_sound_channel()
{
	new spot = engfunc(EngFunc_FindEntityByString, -1, "classname", "info_player_deathmatch")
	if (!spot)
		spot = engfunc(EngFunc_FindEntityByString, -1, "classname", "info_player_start")
	ASSERT(spot > 0)
	new ent = Make("ts_groundweapon")
	ASSERT(ent > 0)
	DispatchKeyValue(ent, "tsweaponid", "1")
	new Float:origin[3]
	pev(spot, pev_origin, origin)
	origin[2] += 16.0
	engfunc(EngFunc_SetOrigin, ent, origin)
	DispatchSpawn(ent)
	bench_wait_until("drop_heard", "drop_done", 4.0)
}

public bool:drop_heard()
{
	return g_DropChannel != -1
}

public drop_done()
{
	ASSERT_EQ(g_DropChannel, CHAN_STATIC)
	bench_pass()
}

// --- the briefcase ---------------------------------------------------------------------------

// A capture announces the 10 points it gives, whatever the capturer's frags (CaptureTouch
// @0x7ddc0 passes 10 to "%s captured the briefcase! %i #TS_Frg"). Two neutral briefcases: the
// flag taken from one is captured at the other, whose own flag is still out.
public test_capture_announces_ten_points()
{
	g_P[0] = bench_puppet("capturer")
	g_P[1] = bench_puppet("capwitness")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[0], "cap_one", 20.0, "respawn")
}

public cap_one(id)
{
	bench_puppet_spawn(g_P[1], "cap_two", 20.0, "respawn")
}

public cap_two(id)
{
	for (new i = 0; i < 2; i++)
	{
		new ent = Make("ts_briefcase")
		ASSERT(ent > 0)
		DispatchKeyValue(ent, "model", "*1")
		DispatchSpawn(ent)
	}
	bench_next("cap_flags_out", 1.5, id)
}

public cap_flags_out(id)
{
	new flag = engfunc(EngFunc_FindEntityByString, -1, "classname", "ts_flag")
	ASSERT(flag > 0)
	ExecuteHamB(Ham_Use, flag, g_P[0], g_P[0], 1, 1.0)
	bench_next("cap_carrying", 0.5, id)
}

public cap_carrying(id)
{
	new carrier = g_P[0]
	set_pev(carrier, pev_frags, 5.0)
	dllfunc(DLLFunc_Touch, g_Ents[0], carrier)
	dllfunc(DLLFunc_Touch, g_Ents[1], carrier)
	new BenchMsg:msg = bench_msg_last(carrier, "TSMessage")
	ASSERT(msg != BenchMsg:0)
	new text[128]
	bench_msg_string(msg, 5, text, charsmax(text))
	ASSERT(contain(text, "captured the briefcase! 10 #TS_Frg") != -1)
	bench_pass()
}
