// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the settings the original The Specialists 3.0 keeps in its game rules: realbullet
// makes every bullet fly, a map's ts_mapglobals superjump flag gives everyone superjump until the
// map changes, a player who leaves takes his votes with him, a teamplay player spawns at his
// team's spot, and the custom weapon damages notice shows only where the cheats are on.
// ../ts_gamerules.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1

new g_Map[32]
new g_P[5]
new g_RealBullet
new g_Teamplay
new g_Cheats
new Float:g_FireTime
new Float:g_HitTime
new Float:g_Delay[2]
new g_Shots
new g_FriendlyFire
new Float:g_Spot[2][3]

public plugin_init()
{
	register_plugin("TS Game Rules Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	get_mapname(g_Map, charsmax(g_Map))
	register_forward(FM_PlaybackEvent, "on_event")
	register_forward(FM_StartFrame, "on_frame")
}

public bench_setup()
{
	g_RealBullet = get_cvar_num("realbullet")
	g_FriendlyFire = get_cvar_num("mp_friendlyfire")
	set_cvar_num("mp_friendlyfire", 1)
	g_FireTime = 0.0
	g_HitTime = -1.0
}

public bench_teardown()
{
	set_cvar_num("realbullet", g_RealBullet)
	set_cvar_num("mp_friendlyfire", g_FriendlyFire)
	if (g_Teamplay)
		set_cvar_num("mp_teamplay", 0)
	if (g_Cheats)
	{
		set_cvar_num("sv_cheats", 0)
		set_cvar_float("damagemult", 0.0)
	}
}

// The shooter's first event once armed (g_FireTime 0): the shot.
public on_event(flags, invoker, eventindex)
{
	if (invoker == g_P[0] && g_P[0] && g_FireTime == 0.0)
		g_FireTime = get_gametime()
	return FMRES_IGNORED
}

// Once armed (g_HitTime 0), the first frame the target has lost health.
public on_frame()
{
	if (g_HitTime != 0.0 || !is_user_alive(g_P[1]))
		return FMRES_IGNORED
	new Float:hp
	pev(g_P[1], pev_health, hp)
	if (hp < 500.0)
		g_HitTime = get_gametime()
	return FMRES_IGNORED
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

// Stands a dist units from b's bounds, facing b's middle; the farthest of a few distances there is
// room for.
Float:FaceFar(a, b)
{
	new Float:dists[] = {600.0, 450.0, 300.0}
	for (new i = 0; i < sizeof(dists); i++)
		if (bench_puppet_face(a, b, dists[i]))
		{
			new Float:target[3]
			pev(b, pev_origin, target)
			bench_puppet_look_at(a, target)
			return dists[i]
		}
	return 0.0
}

// ---------------------------------------------------------------------------------------------
// realbullet: with it on, a bullet flies to its target (a few frames at 13200 units a second for
// the Glock's 9 mm) instead of hitting it the frame it is fired.

public test_realbullet_bullets_fly()
{
	g_P[0] = bench_puppet("realshooter")
	g_P[1] = bench_puppet("realtarget")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	set_cvar_num("realbullet", 0)
	g_Shots = 0
	bench_puppet_spawn(g_P[1], "real_victim", 20.0, "respawn")
}

public real_victim(id)
{
	bench_puppet_spawn(g_P[0], "real_spawned", 20.0, "respawn")
}

public real_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	// past the spawn protection, with the gun out
	bench_next("real_fire", 1.5, id)
}

public real_fire(id)
{
	new Float:dist = FaceFar(g_P[0], g_P[1])
	ASSERT(dist > 0.0)
	server_print("ts_gamerules: shooting from %.0f units, realbullet %d", dist, get_cvar_num("realbullet"))
	set_pev(g_P[1], pev_health, 500.0)
	g_FireTime = 0.0
	g_HitTime = 0.0
	Hold(g_P[0], IN_ATTACK, "real_fired")
}

public real_fired(id)
{
	bench_wait_until("real_hit", "real_landed", 2.0, g_P[1])
}

public bool:real_hit(id)
{
	return g_HitTime > 0.0
}

public real_landed(id)
{
	ASSERT(g_FireTime > 0.0)
	g_Delay[g_Shots] = g_HitTime - g_FireTime
	g_HitTime = -1.0
	if (++g_Shots == 1)
	{
		set_cvar_num("realbullet", 1)
		// the rules pick the setting up in their next think; the gun is ready again by then
		bench_next("real_fire", 1.0, g_P[0])
		return
	}
	server_print("ts_gamerules: hit %.3f s after the shot, then %.3f s with realbullet 1", g_Delay[0], g_Delay[1])
	// the frame it is fired, then at least a frame later
	ASSERT(g_Delay[0] < 0.005)
	ASSERT(g_Delay[1] > g_Delay[0] + 0.005)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// ts_mapglobals with the superjump spawnflag (64): everyone spawns with superjump (the "mj"
// physics key), until the map changes.

bool:Superjump(id)
{
	new value[8]
	engfunc(EngFunc_GetPhysicsKeyValue, id, "mj", value, charsmax(value))
	return equal(value, "1") != 0
}

public test_map_superjump_flag()
{
	bench_set_timeout(90.0)
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_mapglobals"))
	ASSERT(ent > 0)
	set_pev(ent, pev_spawnflags, 64)
	dllfunc(DLLFunc_Spawn, ent)
	g_P[0] = bench_puppet("jumpyone")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "jumpy_spawned", 20.0, "respawn")
}

public jumpy_spawned(id)
{
	ASSERT(Superjump(id))
	bench_change_map(g_Map, "jumpy_map")
}

public jumpy_map()
{
	g_P[0] = bench_puppet("jumpytwo")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "jumpy_next_map", 20.0, "respawn")
}

public jumpy_next_map(id)
{
	ASSERT_FALSE(Superjump(id))
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Votes ("vote map <name>" in chat) count for the players in the game; a player who leaves takes
// his vote with him, so whoever gets his slot next starts with none. Four voters need two votes
// for a map; with the leaver's vote kept, the next one would change the map (after the
// intermission, to the next map in the cycle on both games). In the full fork run a passed vote
// did not change the map (cause not found), so the test proves nothing there; run it on its own.

public test_leaver_takes_his_vote()
{
	bench_set_timeout(90.0)
	for (new i = 0; i < 4; i++)
	{
		new name[16]
		formatex(name, charsmax(name), "voter%d", i)
		g_P[i] = bench_puppet(name)
		ASSERT(g_P[i] > 0)
	}
	g_Shots = 0
	bench_puppet_spawn(g_P[0], "voter_alive", 20.0, "respawn")
}

public voter_alive(id)
{
	if (++g_Shots < 4)
	{
		bench_puppet_spawn(g_P[g_Shots], "voter_alive", 20.0, "respawn")
		return
	}
	bench_puppet_say(g_P[0], "vote map crossfire")
	bench_next("voter_voted", 0.5)
}

public voter_voted()
{
	ASSERT_MSG(g_P[1], "", "vote for map crossfire")
	server_cmd("kick #%d", get_user_userid(g_P[0]))
	bench_next("voter_left", 1.0)
}

public voter_left()
{
	ASSERT_FALSE(is_user_connected(g_P[0]))
	g_P[4] = bench_puppet("voter4")
	// he gets the leaver's slot
	ASSERT_EQ(g_P[4], g_P[0])
	bench_puppet_spawn(g_P[4], "voter_back", 20.0, "respawn")
}

public voter_back(id)
{
	bench_puppet_say(g_P[1], "vote map crossfire")
	// the votes are counted every ten seconds, and a majority ends the map after the intermission;
	// a change in this time fails the test
	bench_next("voter_counted", 30.0)
}

public voter_counted()
{
	new map[32]
	get_mapname(map, charsmax(map))
	ASSERT_STR_EQ(map, g_Map)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// In teamplay a player spawns at an info_player_team<N> of his team (N = the team's place in the
// list) when the map has one. Two such spots are put 64 units over two deathmatch spots; a player
// starts at one of them (the server is put in teamplay for the test if it is not).

public test_team_player_spawns_at_his_team_spot()
{
	bench_set_timeout(120.0)
	if (get_cvar_num("mp_teamplay"))
	{
		spot_map(0)
		return
	}
	g_Teamplay = 1
	set_cvar_num("mp_teamplay", 1)
	bench_change_map(g_Map, "spot_map", 1)
}

// changed: the test put the server in teamplay (plugin variables start over on the map change)
public spot_map(changed)
{
	g_Teamplay = changed
	new dm = -1
	for (new i = 0; i < 2; i++)
	{
		dm = engfunc(EngFunc_FindEntityByString, dm, "classname", "info_player_deathmatch")
		ASSERT(dm > 0)
		new classname[32]
		formatex(classname, charsmax(classname), "info_player_team%d", i + 1)
		new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, classname))
		ASSERT(ent > 0)
		pev(dm, pev_origin, g_Spot[i])
		g_Spot[i][2] += 64.0
		engfunc(EngFunc_SetOrigin, ent, g_Spot[i])
		dllfunc(DLLFunc_Spawn, ent)
	}
	g_P[0] = bench_puppet("spotter")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "spotter_spawned", 20.0, "respawn")
}

public spotter_spawned(id)
{
	new Float:origin[3], team[32]
	pev(id, pev_origin, origin)
	get_user_team(id, team, charsmax(team))
	new spot = -1
	for (new i = 0; i < 2; i++)
		if (floatabs(origin[0] - g_Spot[i][0]) < 1.0 && floatabs(origin[1] - g_Spot[i][1]) < 1.0
			&& floatabs(origin[2] - g_Spot[i][2]) < 16.0)
			spot = i
	server_print("ts_gamerules: team %s spawned at %.0f %.0f %.0f, team spot %d", team, origin[0],
		origin[1], origin[2], spot + 1)
	if (!g_Teamplay)
	{
		spot_restored(spot + 1)
		return
	}
	set_cvar_num("mp_teamplay", 0)
	g_Teamplay = 0
	bench_change_map(g_Map, "spot_restored", spot + 1)
}

public spot_restored(spot)
{
	ASSERT(spot > 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// A joiner is told "This server has custom weapon damages" (damagemult above 0) only on a map
// started with sv_cheats on, after the cheats notice; with the cheats off, damagemult does
// nothing and he is told nothing.

public test_damage_notice_needs_cheats()
{
	bench_set_timeout(120.0)
	g_Cheats = 1
	set_cvar_float("damagemult", 2.0)
	g_P[0] = bench_puppet("noticeone")
	ASSERT(g_P[0] > 0)
	bench_next("notice_off", 1.0, g_P[0])
}

public notice_off(id)
{
	ASSERT_EQ(bench_msg_count(id, "TSMessage", "custom weapon damages"), 0)
	set_cvar_num("sv_cheats", 1)
	bench_change_map(g_Map, "notice_map")
}

public notice_map()
{
	g_Cheats = 1
	g_P[0] = bench_puppet("noticetwo")
	ASSERT(g_P[0] > 0)
	bench_next("notice_on", 1.0, g_P[0])
}

public notice_on(id)
{
	new count = bench_msg_count(id, "TSMessage", "custom weapon damages")
	new cheats = bench_msg_count(id, "TSMessage", "has cheats enabled")
	set_cvar_num("sv_cheats", 0)
	set_cvar_float("damagemult", 0.0)
	g_Cheats = 0
	bench_change_map(g_Map, "notice_restored", (count << 8) | cheats)
}

public notice_restored(counts)
{
	ASSERT_EQ(get_cvar_num("sv_cheats"), 0)
	server_print("ts_gamerules: with cheats, %d damage notices and %d cheats notices", counts >> 8,
		counts & 255)
	ASSERT_EQ(counts >> 8, 1)
	ASSERT_EQ(counts & 255, 1)
	bench_pass()
}
