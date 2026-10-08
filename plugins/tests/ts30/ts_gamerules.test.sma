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
// makes every bullet fly, a map's ts_mapglobals superjump flag gives everyone superjump (and shows
// it, and keeps it out of the random powerups) and its other spawnflags restrict weapons, until
// the map changes, a player who leaves takes his votes with him and a passed vote ends the map,
// player 32 has no vote, a teamplay player spawns at his team's spot and wears one of his team's
// models, the custom weapon damages notice shows only where the cheats are on, the custom weapons
// notice ends with the map, the bot commands answer, and a player with no spawn spot is spawned
// silently. Kevlar takes 21.25% off a bullet to the body; a flying bullet makes no sound or mark
// where it hits and goes on through a player; a team list's repeated name keeps its place; a
// spectator votes, for the first word after "map", and "vote stats" lists the last count; a
// ts_mapglobals thinks once.
// ../ts_gamerules.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
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
new g_Developer
new g_Pressed

public plugin_init()
{
	register_plugin("TS Game Rules Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	get_mapname(g_Map, charsmax(g_Map))
	RestoreGameCfg()
	register_forward(FM_PlaybackEvent, "on_event")
	register_forward(FM_StartFrame, "on_frame")
	register_forward(FM_StartFrame, "on_frame_hits")
	register_forward(FM_EmitSound, "on_sound")
	register_forward(FM_MessageBegin, "on_message_begin")
	register_forward(FM_WriteByte, "on_write_byte")
	register_forward(FM_TraceLine, "on_trace", 1)
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
	// the team settings the repeated team name test saved, if it ended before it put them back
	RestoreTeamCvars()
	set_cvar_num("realbullet", g_RealBullet)
	set_cvar_num("mp_friendlyfire", g_FriendlyFire)
	if (g_Teamplay)
		set_cvar_num("mp_teamplay", 0)
	if (g_Cheats)
	{
		set_cvar_num("sv_cheats", 0)
		set_cvar_float("damagemult", 0.0)
	}
	if (g_Developer)
	{
		set_cvar_num("developer", 0)
		g_Developer = 0
	}
}

// The last value of setting kind (SrvSett: kind byte, value short) sent to id this test, -1 if none.
LastSetting(id, kind)
{
	new value = -1
	new BenchMsg:msg = BenchMsg:0
	while ((msg = bench_msg_next(id, msg, "SrvSett")) != BenchMsg:0)
		if (bench_msg_int(msg, 0) == kind)
			value = bench_msg_int(msg, 1)
	return value
}

// How many PwUp (type short, seconds byte) messages showing type were sent to id this test.
PowerupShown(id, type)
{
	new count = 0
	new BenchMsg:msg = BenchMsg:0
	while ((msg = bench_msg_next(id, msg, "PwUp")) != BenchMsg:0)
		if (bench_msg_int(msg, 0) == type)
			count++
	return count
}

CreateMapGlobals(flags)
{
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_mapglobals"))
	if (ent > 0)
	{
		set_pev(ent, pev_spawnflags, flags)
		dllfunc(DLLFunc_Spawn, ent)
	}
	return ent
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
// room for. He looks level, along the line from his eyes that bench_puppet_face found reaches b:
// aimed down at b's origin instead, a shot can meet a low wall or railing that line passes over.
Float:FaceFar(a, b)
{
	new Float:dists[] = {600.0, 450.0, 300.0}
	for (new i = 0; i < sizeof(dists); i++)
		if (bench_puppet_face(a, b, dists[i]))
			return dists[i]
	return 0.0
}

// ---------------------------------------------------------------------------------------------
// realbullet: with it on, a bullet flies to its target instead of hitting it the frame it is
// fired. With realbullet 1 a bullet moves every 0.05 s by that much flight (13200 units a second for
// the Glock's 9 mm, 660 units a step), starting at the rules' next think, so it hits within 0.03 s
// (flying a frame at a time, it would take 0.045 s from 600 units, the distance used when there is
// room).

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
	// the frame it is fired, then at least a frame later, within the first step
	ASSERT(g_Delay[0] < 0.005)
	ASSERT(g_Delay[1] > g_Delay[0] + 0.005)
	ASSERT(g_Delay[1] < 0.03)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// ts_mapglobals with the superjump spawnflag (64): everyone spawns with superjump (the "mj"
// physics key) and is shown the superjump powerup (PwUp 256) on his HUD reset, until the map
// changes.

bool:Superjump(id)
{
	new value[8]
	engfunc(EngFunc_GetPhysicsKeyValue, id, "mj", value, charsmax(value))
	return equal(value, "1") != 0
}

public test_map_superjump_flag()
{
	bench_set_timeout(90.0)
	ASSERT(CreateMapGlobals(64) > 0)
	g_P[0] = bench_puppet("jumpyone")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "jumpy_spawned", 20.0, "respawn")
}

public jumpy_spawned(id)
{
	ASSERT(Superjump(id))
	// the HUD reset of his spawn comes with the next client update
	bench_next("jumpy_shown", 0.5, id)
}

public jumpy_shown(id)
{
	ASSERT(PowerupShown(id, 256) > 0)
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
	bench_next("jumpy_next_shown", 0.5, id)
}

public jumpy_next_shown(id)
{
	ASSERT_EQ(PowerupShown(id, 256), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// A ts_powerup left to pick its type from its spawnflags (no pwuptype) takes superjump (256) when
// that is all its flags allow; on a map whose ts_mapglobals gives everyone superjump, superjump is
// left out and it picks another. Its type shows in its body. The map is changed back afterwards.

CreateRandomPowerup(flags)
{
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_powerup"))
	if (ent > 0)
	{
		set_pev(ent, pev_spawnflags, flags)
		dllfunc(DLLFunc_Spawn, ent)
	}
	return ent
}

public test_superjump_map_leaves_superjump_out()
{
	bench_set_timeout(90.0)
	new ent = CreateRandomPowerup(256)
	ASSERT(ent > 0)
	new superjump = pev(ent, pev_body)
	engfunc(EngFunc_RemoveEntity, ent)
	ASSERT(CreateMapGlobals(64) > 0)
	new same = 0
	for (new i = 0; i < 10; i++)
	{
		ent = CreateRandomPowerup(256)
		ASSERT(ent > 0)
		if (pev(ent, pev_body) == superjump)
			same++
		engfunc(EngFunc_RemoveEntity, ent)
	}
	server_print("ts_gamerules: superjump powerup body %d, %d of 10 the same on a superjump map",
		superjump, same)
	bench_change_map(g_Map, "superjump_out_restored", same)
}

public superjump_out_restored(same)
{
	ASSERT_EQ(same, 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The other spawnflags of a ts_mapglobals restrict weapons: the restriction becomes
// InitWeaponRestriction() (31, every category) XOR the spawnflags, which a joiner is sent as
// SrvSett 3, until the map changes. Flag 2 takes the second category away (31 -> 29).

public test_mapglobals_restricts_weapons()
{
	bench_set_timeout(90.0)
	ASSERT(CreateMapGlobals(2) > 0)
	g_P[0] = bench_puppet("restrictone")
	ASSERT(g_P[0] > 0)
	bench_next("restrict_joined", 1.0, g_P[0])
}

public restrict_joined(id)
{
	new first = LastSetting(id, 3)
	server_print("ts_gamerules: restriction %d with the ts_mapglobals", first)
	bench_change_map(g_Map, "restrict_map", first)
}

public restrict_map(first)
{
	g_Shots = first
	g_P[0] = bench_puppet("restricttwo")
	ASSERT(g_P[0] > 0)
	bench_next("restrict_next", 1.0, g_P[0])
}

public restrict_next(id)
{
	new second = LastSetting(id, 3)
	server_print("ts_gamerules: restriction %d on the next map", second)
	ASSERT_EQ(g_Shots, 29)
	ASSERT_EQ(second, 31)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Votes ("vote map <name>" in chat) count for the players in the game; a player who leaves takes
// his vote with him, so whoever gets his slot next starts with none. Four voters need two votes
// for a map; with the leaver's vote kept, the next one would change the map. A second vote then
// does change it (after the intermission, which the voters end by pressing a key, to the next map
// in the cycle on both games), and the test changes back. The count runs every ten seconds from
// ten seconds into the map; before reTS reset that clock on a map change, a test right after a
// long map waited for the old map's time and the passed vote never changed the map.

public test_leaver_takes_his_vote()
{
	bench_set_timeout(150.0)
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
	// now a majority: the map ends at the next count
	bench_puppet_say(g_P[2], "vote map crossfire")
	// plugin variables start over on the new map, so the way home goes through localinfo
	set_localinfo("tsgr_home", g_Map)
	bench_expect_map_change("voter_changed")
	g_Pressed = 0
	bench_wait_until("voter_press", "voter_never", 60.0)
}

// Presses and releases jump on every voter, so the intermission ends at once.
public bool:voter_press()
{
	g_Pressed = !g_Pressed
	for (new i = 1; i < 4; i++)
		if (is_user_connected(g_P[i]))
			bench_puppet_input(g_P[i], g_Pressed ? IN_JUMP : 0)
	return false
}

public voter_never()
{
	bench_fail("the vote never changed the map")
}

public voter_changed()
{
	new home[32]
	get_localinfo("tsgr_home", home, charsmax(home))
	server_print("ts_gamerules: the vote changed the map to %s, back to %s", g_Map, home)
	bench_change_map(home, "voter_home")
}

public voter_home()
{
	new home[32]
	get_localinfo("tsgr_home", home, charsmax(home))
	ASSERT_STR_EQ(g_Map, home)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Votes are kept per player for players 1 to 31: player 32's "vote map" is not a vote, nobody is
// told about it (it is said in chat instead). Player 31's is, as a control. (Only a player in
// play votes.)

public test_player_32_has_no_vote()
{
	bench_set_timeout(90.0)
	if (get_maxplayers() < 32)
	{
		server_print("ts_gamerules: maxplayers %d, no player 32", get_maxplayers())
		bench_pass()
		return
	}
	g_P[0] = g_P[1] = g_P[2] = 0
	for (new i = 0; i < 32 && !g_P[1]; i++)
	{
		new name[16]
		formatex(name, charsmax(name), "slot%d", i)
		new id = bench_puppet(name)
		ASSERT(id > 0)
		if (!g_P[2])
			g_P[2] = id
		if (id == 31)
			g_P[0] = id
		if (id == 32)
			g_P[1] = id
	}
	ASSERT(g_P[0] == 31 && g_P[1] == 32 && g_P[2] < 31)
	bench_puppet_spawn(g_P[0], "slot31_alive", 20.0, "respawn")
}

public slot31_alive(id)
{
	bench_puppet_spawn(g_P[1], "slot32_alive", 20.0, "respawn")
}

public slot32_alive(id)
{
	bench_puppet_say(g_P[0], "vote map crossfire")
	bench_puppet_say(g_P[1], "vote map crossfire")
	bench_next("slot_voted", 0.5)
}

public slot_voted()
{
	new name[32], text[64]
	get_user_name(g_P[0], name, charsmax(name))
	formatex(text, charsmax(text), "%s vote for map", name)
	new seen31 = bench_msg_count(g_P[2], "", text)
	get_user_name(g_P[1], name, charsmax(name))
	formatex(text, charsmax(text), "%s vote for map", name)
	new seen32 = bench_msg_count(g_P[2], "", text)
	server_print("ts_gamerules: player 31's vote told %d times, player 32's %d", seen31, seen32)
	ASSERT_EQ(seen31, 1)
	ASSERT_EQ(seen32, 0)
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
	// one of his team's models, not the team's whole list
	new model[64]
	get_user_info(id, "model", model, charsmax(model))
	server_print("ts_gamerules: team %s model %s", team, model)
	if (!OneModel(model))
		spot = -100
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
	ASSERT(spot != -99)
	ASSERT(spot > 0)
	bench_pass()
}

// A single model: not empty, no ";", and one of the models the teammodels setting names or the
// game's defaults (seal;merc|gordon;laurence|agent|hitman;castor) do.
bool:OneModel(const model[])
{
	if (!model[0] || contain(model, ";") != -1)
		return false
	new list[256]
	get_cvar_string("mp_teammodels", list, charsmax(list))
	add(list, charsmax(list), "|seal;merc|gordon;laurence|agent|hitman;castor")
	replace_all(list, charsmax(list), "|", ";")
	new piece[64], rest[256]
	copy(rest, charsmax(rest), list)
	while (rest[0])
	{
		strtok(rest, piece, charsmax(piece), rest, charsmax(rest), ';')
		if (equali(piece, model))
			return true
	}
	return false
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

// ---------------------------------------------------------------------------------------------
// "loadweapons" marks the server as having custom weapons, and a joiner is told so ("This server
// is using custom weapons."), until the map changes. The file loaded holds a comment only, so no
// weapon changes.

#define CUSTOM_FILE "tsgr_weapons.txt"

public test_custom_weapons_notice_ends_with_the_map()
{
	bench_set_timeout(90.0)
	if (file_exists(CUSTOM_FILE))
		delete_file(CUSTOM_FILE)
	ASSERT(write_file(CUSTOM_FILE, "// ts_gamerules.test.sma: nothing changes", -1))
	server_cmd("loadweapons %s", CUSTOM_FILE)
	server_exec()
	delete_file(CUSTOM_FILE)
	g_P[0] = bench_puppet("customone")
	ASSERT(g_P[0] > 0)
	bench_next("custom_joined", 1.0, g_P[0])
}

public custom_joined(id)
{
	new count = bench_msg_count(id, "TSMessage", "using custom weapons")
	bench_change_map(g_Map, "custom_map", count)
}

public custom_map(first)
{
	g_Shots = first
	g_P[0] = bench_puppet("customtwo")
	ASSERT(g_P[0] > 0)
	bench_next("custom_next", 1.0, g_P[0])
}

public custom_next(id)
{
	new count = bench_msg_count(id, "TSMessage", "using custom weapons")
	server_print("ts_gamerules: custom weapons notice %d times, %d on the next map", g_Shots, count)
	ASSERT(g_Shots > 0)
	ASSERT_EQ(count, 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The game has "addbot" and "addcustombot" server commands: on a dedicated server both only say
// "Bots only in listen servers." on the developer console (developer is on for the test). The
// bench records the engine's own console lines on ReHLDS but not on HLDS 4002 (an echo shows
// which), so the answers are checked where they can be seen.

public test_bot_commands_answer()
{
	g_Developer = 1
	set_cvar_num("developer", 1)
	server_cmd("echo tsgr_echo_probe")
	server_cmd("addbot")
	server_cmd("addcustombot")
	server_exec()
	bench_next("bots_answered", 0.1)
}

public bots_answered()
{
	new answers = bench_msg_count(0, "server", "Bots only in listen servers")
	new unknown = bench_msg_count(0, "server", "nknown command")
	new seen = bench_msg_count(0, "server", "tsgr_echo_probe")
	server_print("ts_gamerules: %d bot answers, %d unknown commands, echo seen %d", answers, unknown, seen)
	set_cvar_num("developer", 0)
	g_Developer = 0
	ASSERT_EQ(unknown, 0)
	if (seen)
		ASSERT_EQ(answers, 2)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// With no spawn spot of any kind a player is put at the world's origin, and the game says nothing
// about it (developer is on, to see any message the game would print; the bench sees such lines
// on ReHLDS only, and a line without a newline once the next line ends it). The spots are renamed
// for the test and named back afterwards.

new g_Spots[64]
new g_SpotCount
// every class a player can spawn at (the team spots are there if the team spot test made them)
new const g_SpotClasses[][] = {"info_player_deathmatch", "info_player_start", "info_player_team1",
	"info_player_team2", "info_player_team3", "info_player_team4"}

public test_spawn_without_spots_is_silent()
{
	bench_set_timeout(60.0)
	g_SpotCount = 0
	for (new c = 0; c < sizeof(g_SpotClasses); c++)
	{
		new ent = -1
		while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", g_SpotClasses[c])) > 0
			&& g_SpotCount < sizeof(g_Spots))
			g_Spots[g_SpotCount++] = ent | (c << 16)
	}
	server_print("ts_gamerules: %d spawn spots renamed", g_SpotCount)
	for (new i = 0; i < g_SpotCount; i++)
		set_pev(g_Spots[i] & 0xffff, pev_classname, "tsgr_hidden_spot")
	g_Developer = 1
	set_cvar_num("developer", 1)
	g_P[0] = bench_puppet("nowhere")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "nowhere_spawned", 20.0, "respawn")
}

public nowhere_spawned(id)
{
	// ends a message the game may have left without a newline
	server_print("ts_gamerules: nowhere spawned")
	bench_next("nowhere_counted", 0.0, id)
}

public nowhere_counted(id)
{
	new said = bench_msg_count(0, "server", "no info_player_start")
	new Float:origin[3]
	pev(id, pev_origin, origin)
	server_print("ts_gamerules: spawned at %.0f %.0f %.0f, %d lines about info_player_start", origin[0],
		origin[1], origin[2], said)
	set_cvar_num("developer", 0)
	g_Developer = 0
	for (new i = 0; i < g_SpotCount; i++)
		set_pev(g_Spots[i] & 0xffff, pev_classname, g_SpotClasses[g_Spots[i] >> 16])
	g_SpotCount = 0
	ASSERT_EQ(said, 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Kevlar takes armor_absorb off a hit to the body, and every map starts with 0.2125: 40 points to
// the chest take 31 with kevlar (armorvalue set), 40 without. A real shot (realbullet 0) at the
// wearer's chest sets the hit group the game remembers for his next damage; TakeDamage then deals
// the 40 twice, without and with kevlar. (TraceAttack is not called by hand: outside a shot the
// game's pending multi-damage can name an entity long gone.)

new g_ShotGroup
new const g_LineSpots[][] = {"info_player_deathmatch", "info_player_team1", "info_player_team2",
	"info_player_start"}
new g_Watch
new g_Pressing

public test_kevlar_takes_a_fifth_off()
{
	bench_set_timeout(60.0)
	g_P[0] = bench_puppet("kevlarshooter")
	g_P[1] = bench_puppet("kevlarwearer")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	set_cvar_num("realbullet", 0)
	bench_puppet_spawn(g_P[1], "kevlar_wearer", 20.0, "respawn")
}

public kevlar_wearer(id)
{
	bench_puppet_spawn(g_P[0], "kevlar_shooter", 20.0, "respawn")
}

public kevlar_shooter(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	// past the spawn protection, with the gun out
	bench_next("kevlar_aim", 1.5)
}

// The health the wearer loses to 40 points of bullet damage, with armor armorvalue.
DamageLoss(armor)
{
	new id = g_P[1]
	set_pev(id, pev_health, 100.0)
	set_pev(id, pev_armorvalue, float(armor))
	ExecuteHamB(Ham_TakeDamage, id, g_P[0], g_P[0], 40.0, DMG_BULLET)
	new Float:health
	pev(id, pev_health, health)
	set_pev(id, pev_armorvalue, 0.0)
	set_pev(id, pev_health, 100.0)
	return 100 - floatround(health, floatround_floor)
}

public kevlar_aim()
{
	ASSERT(is_user_alive(g_P[0]) && is_user_alive(g_P[1]))
	ASSERT(PlaceForChestShot())
	set_pev(g_P[1], pev_health, 500.0)
	g_ShotGroup = -1
	g_FireTime = 0.0
	g_Pressing = 0
	g_Watch = 2
	bench_wait_until("pierce_one_shot", "kevlar_shot", 5.0, g_P[0])
}

public kevlar_shot(id)
{
	bench_next("kevlar_hits", 0.2)
}

public kevlar_hits()
{
	g_Watch = 0
	ASSERT(g_FireTime > 0.0)
	server_print("ts_gamerules: the shot hit group %d", g_ShotGroup)
	ASSERT(g_ShotGroup >= 2 && g_ShotGroup <= 5)
	new plain = DamageLoss(0)
	new kevlar = DamageLoss(100)
	server_print("ts_gamerules: 40 points after a chest hit take %d, %d with kevlar", plain, kevlar)
	ASSERT_EQ(plain, 40)
	ASSERT_EQ(kevlar, 31)
	bench_pass()
}

// The shooter's first trace while armed for the kevlar shot: the hit group it found on the wearer.
public on_trace(const Float:v1[3], const Float:v2[3], noMonsters, skip, tr)
{
	if (g_Watch == 2 && skip == g_P[0] && g_ShotGroup == -1 && get_tr2(tr, TR_pHit) == g_P[1])
		g_ShotGroup = get_tr2(tr, TR_iHitgroup)
	return FMRES_IGNORED
}

// Stands the wearer at a spawn spot (where he is first, then each deathmatch and team spot) and the
// shooter 200 units away on the first of eight compass lines with room and a floor for him, facing
// a point 8 units above the wearer's origin, when a line from his eyes to there meets the wearer in
// the chest, stomach or arms (hit group 2 to 5). Returns false if there is none.
bool:PlaceForChestShot()
{
	new Float:center[3]
	pev(g_P[1], pev_origin, center)
	if (ChestShotAt(center))
		return true
	for (new c = 0; c < sizeof(g_LineSpots); c++)
	{
		new spot = -1
		while ((spot = engfunc(EngFunc_FindEntityByString, spot, "classname", g_LineSpots[c])) > 0)
		{
			pev(spot, pev_origin, center)
			center[2] += 1.0
			if (ChestShotAt(center))
				return true
		}
	}
	return false
}

bool:ChestShotAt(const Float:center[3])
{
	new a = g_P[0], b = g_P[1]
	new Float:shooter[3], Float:end[3], Float:eye[3], Float:ofs[3], Float:aim[3], Float:frac
	pev(a, pev_view_ofs, ofs)
	new tr = create_tr2(), bool:found = false
	engfunc(EngFunc_TraceHull, center, center, DONT_IGNORE_MONSTERS, HULL_HUMAN, b, tr)
	if (get_tr2(tr, TR_StartSolid) || get_tr2(tr, TR_AllSolid))
	{
		free_tr2(tr)
		return false
	}
	engfunc(EngFunc_SetOrigin, b, center)
	set_pev(b, pev_velocity, Float:{0.0, 0.0, 0.0})
	aim = center
	aim[2] += 8.0
	for (new i = 0; i < 8 && !found; i++)
	{
		shooter[0] = center[0] - floatcos(float(i) * 45.0, degrees) * 200.0
		shooter[1] = center[1] - floatsin(float(i) * 45.0, degrees) * 200.0
		shooter[2] = center[2]
		engfunc(EngFunc_TraceHull, shooter, shooter, DONT_IGNORE_MONSTERS, HULL_HUMAN, a, tr)
		if (get_tr2(tr, TR_StartSolid) || get_tr2(tr, TR_AllSolid))
			continue
		end = shooter
		end[2] -= 4.0
		engfunc(EngFunc_TraceHull, shooter, end, IGNORE_MONSTERS, HULL_HUMAN, a, tr)
		get_tr2(tr, TR_flFraction, frac)
		if (frac >= 1.0)
			continue
		for (new k = 0; k < 3; k++)
			eye[k] = shooter[k] + ofs[k]
		engfunc(EngFunc_TraceLine, eye, aim, DONT_IGNORE_MONSTERS, a, tr)
		new group = get_tr2(tr, TR_iHitgroup)
		if (get_tr2(tr, TR_pHit) != b || group < 2 || group > 5)
			continue
		engfunc(EngFunc_SetOrigin, a, shooter)
		set_pev(a, pev_velocity, Float:{0.0, 0.0, 0.0})
		bench_puppet_look_at(a, aim)
		found = true
	}
	free_tr2(tr)
	return found
}

// ---------------------------------------------------------------------------------------------
// A flying bullet (realbullet 1) that hits a wall makes no sound there and leaves no mark from the
// server (the shooter's client plays both from the shot's event): no ricochet sound, and no gunshot
// or decal temporary entity.

new g_Ricochets
new g_Marks
new g_TempEnt

public on_sound(ent, channel, const sample[])
{
	if (g_Watch && containi(sample, "ric") != -1)
		g_Ricochets++
	return FMRES_IGNORED
}

public on_message_begin(dest, type)
{
	g_TempEnt = g_Watch && type == SVC_TEMPENTITY
	return FMRES_IGNORED
}

// The first byte of a temporary entity is its kind: TE_GUNSHOT 2, TE_DECAL 104, TE_GUNSHOTDECAL
// 109, TE_WORLDDECAL 116, TE_DECALHIGH 105, TE_WORLDDECALHIGH 117.
public on_write_byte(value)
{
	if (g_TempEnt)
	{
		g_TempEnt = 0
		if (value == 2 || value == 104 || value == 105 || value == 109 || value == 116 || value == 117)
			g_Marks++
	}
	return FMRES_IGNORED
}

public test_flying_bullet_hits_a_wall_silently()
{
	g_P[0] = bench_puppet("wallshooter")
	ASSERT(g_P[0] > 0)
	set_cvar_num("realbullet", 1)
	bench_puppet_spawn(g_P[0], "wall_spawned", 20.0, "respawn")
}

public wall_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	// past the spawn protection, with the gun out, and the rules have read realbullet
	bench_next("wall_fire", 1.5, id)
}

public wall_fire(id)
{
	// level, at the first wall within 4000 units of the eight compass points
	new Float:origin[3], Float:ofs[3], Float:eye[3], Float:end[3], Float:frac
	pev(id, pev_origin, origin)
	pev(id, pev_view_ofs, ofs)
	new tr = create_tr2(), Float:yaw = -1.0
	for (new i = 0; i < 8 && yaw < 0.0; i++)
	{
		for (new k = 0; k < 3; k++)
			eye[k] = origin[k] + ofs[k]
		end[0] = eye[0] + floatcos(float(i) * 45.0, degrees) * 4000.0
		end[1] = eye[1] + floatsin(float(i) * 45.0, degrees) * 4000.0
		end[2] = eye[2]
		engfunc(EngFunc_TraceLine, eye, end, IGNORE_MONSTERS, id, tr)
		get_tr2(tr, TR_flFraction, frac)
		new hit = get_tr2(tr, TR_pHit)
		if (frac < 1.0 && (hit <= 0 || hit > get_maxplayers()))
			yaw = float(i) * 45.0
	}
	free_tr2(tr)
	ASSERT(yaw >= 0.0)
	new Float:angles[3]
	angles[1] = yaw
	bench_puppet_angles(id, angles)
	g_Ricochets = 0
	g_Marks = 0
	g_FireTime = 0.0
	g_Watch = 1
	Hold(id, IN_ATTACK, "wall_fired")
}

public wall_fired(id)
{
	bench_next("wall_counted", 1.0, id)
}

public wall_counted(id)
{
	g_Watch = 0
	server_print("ts_gamerules: a flying bullet into a wall: fired %d, %d ricochet sounds, %d marks",
		g_FireTime > 0.0, g_Ricochets, g_Marks)
	ASSERT(g_FireTime > 0.0)
	ASSERT_EQ(g_Ricochets, 0)
	ASSERT_EQ(g_Marks, 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// A flying bullet (realbullet 1) goes on through a player it hits when enough of it is left (the
// damage times the ammo's pierce factor, halved through a body, over 5): one Five-seveN shot (5.7 mm
// pierces fully) from 300 units at a player with another 96 units behind him hits twice, the front
// player first. It goes on from just past the hit (10.5 units here), so the second hit is the back
// player, or the front player again when that point is still inside him; the original does both.
// (What each hit is for, and when, is printed.)

#define FIVESEVEN	14

new Float:g_Health[2]
new g_Hits[2]
new Float:g_FirstHit[2]

public on_frame_hits()
{
	if (g_Watch != 1)
		return FMRES_IGNORED
	for (new i = 0; i < 2; i++)
	{
		new id = g_P[1 + i]
		if (!is_user_alive(id))
			continue
		new Float:hp
		pev(id, pev_health, hp)
		if (hp < g_Health[i])
		{
			server_print("ts_gamerules: %.3f target %d hit for %.0f", get_gametime(), i + 1, g_Health[i] - hp)
			if (!g_Hits[i]++)
				g_FirstHit[i] = get_gametime()
			g_Health[i] = hp
		}
	}
	return FMRES_IGNORED
}

public test_flying_bullet_goes_through_a_player()
{
	bench_set_timeout(60.0)
	g_P[0] = bench_puppet("pierceshooter")
	g_P[1] = bench_puppet("piercefront")
	g_P[2] = bench_puppet("pierceback")
	ASSERT(g_P[0] > 0 && g_P[1] > 0 && g_P[2] > 0)
	set_cvar_num("realbullet", 1)
	g_Shots = 0
	bench_puppet_spawn(g_P[0], "pierce_spawned", 20.0, "respawn")
}

public pierce_spawned(id)
{
	if (++g_Shots <= 2)
	{
		bench_puppet_spawn(g_P[g_Shots], "pierce_spawned", 20.0, "respawn")
		return
	}
	ts_giveweapon(g_P[0], FIVESEVEN, 0, 0)
	bench_next("pierce_place", 1.5)
}

// Puts the front player at a spawn spot (where he stands first, then each deathmatch and team spot
// in turn), the shooter 300 units away and the back player 96 units behind the front one, on the
// first of eight compass lines with room for all three, a floor under them and a clear line from
// the shooter's eyes to the back player's middle, along which the shooter aims: it meets the front
// player in the chest, well inside his body, so the spread cannot take the shot past him.

bool:PlaceInLine()
{
	new Float:center[3]
	pev(g_P[1], pev_origin, center)
	if (PlaceInLineAt(center))
		return true
	for (new c = 0; c < sizeof(g_LineSpots); c++)
	{
		new spot = -1
		while ((spot = engfunc(EngFunc_FindEntityByString, spot, "classname", g_LineSpots[c])) > 0)
		{
			pev(spot, pev_origin, center)
			center[2] += 1.0
			if (PlaceInLineAt(center))
				return true
		}
	}
	return false
}

bool:PlaceInLineAt(const Float:center[3])
{
	new a = g_P[0], b = g_P[1], c = g_P[2]
	new Float:shooter[3], Float:back[3], Float:eye[3], Float:end[3], Float:ofs[3]
	pev(a, pev_view_ofs, ofs)
	new tr = create_tr2(), bool:found = false
	engfunc(EngFunc_TraceHull, center, center, DONT_IGNORE_MONSTERS, HULL_HUMAN, b, tr)
	if (get_tr2(tr, TR_StartSolid) || get_tr2(tr, TR_AllSolid))
	{
		free_tr2(tr)
		return false
	}
	for (new i = 0; i < 8 && !found; i++)
	{
		new Float:dx = floatcos(float(i) * 45.0, degrees), Float:dy = floatsin(float(i) * 45.0, degrees)
		shooter[0] = center[0] - dx * 300.0
		shooter[1] = center[1] - dy * 300.0
		shooter[2] = center[2]
		back[0] = center[0] + dx * 96.0
		back[1] = center[1] + dy * 96.0
		back[2] = center[2]
		engfunc(EngFunc_TraceHull, shooter, shooter, DONT_IGNORE_MONSTERS, HULL_HUMAN, a, tr)
		if (get_tr2(tr, TR_StartSolid) || get_tr2(tr, TR_AllSolid))
			continue
		engfunc(EngFunc_TraceHull, back, back, DONT_IGNORE_MONSTERS, HULL_HUMAN, c, tr)
		if (get_tr2(tr, TR_StartSolid) || get_tr2(tr, TR_AllSolid))
			continue
		// the floor under both, not more than 4 units down
		end = shooter
		end[2] -= 4.0
		engfunc(EngFunc_TraceHull, shooter, end, IGNORE_MONSTERS, HULL_HUMAN, a, tr)
		new Float:frac
		get_tr2(tr, TR_flFraction, frac)
		if (frac >= 1.0)
			continue
		end = back
		end[2] -= 4.0
		engfunc(EngFunc_TraceHull, back, end, IGNORE_MONSTERS, HULL_HUMAN, c, tr)
		get_tr2(tr, TR_flFraction, frac)
		if (frac >= 1.0)
			continue
		// a clear line from the shooter's eyes to the back player's middle, which passes the front
		// player's chest
		for (new k = 0; k < 3; k++)
			eye[k] = shooter[k] + ofs[k]
		engfunc(EngFunc_TraceLine, eye, back, IGNORE_MONSTERS, a, tr)
		get_tr2(tr, TR_flFraction, frac)
		if (frac < 1.0)
			continue
		engfunc(EngFunc_SetOrigin, a, shooter)
		engfunc(EngFunc_SetOrigin, b, center)
		engfunc(EngFunc_SetOrigin, c, back)
		set_pev(a, pev_velocity, Float:{0.0, 0.0, 0.0})
		set_pev(b, pev_velocity, Float:{0.0, 0.0, 0.0})
		set_pev(c, pev_velocity, Float:{0.0, 0.0, 0.0})
		bench_puppet_look_at(a, back)
		found = true
	}
	free_tr2(tr)
	return found
}

public pierce_place()
{
	ASSERT(is_user_alive(g_P[0]) && is_user_alive(g_P[1]) && is_user_alive(g_P[2]))
	ASSERT(PlaceInLine())
	bench_next("pierce_fire", 0.5)
}

public pierce_fire()
{
	for (new i = 0; i < 2; i++)
	{
		set_pev(g_P[1 + i], pev_health, 500.0)
		g_Health[i] = 500.0
		g_Hits[i] = 0
		g_FirstHit[i] = 0.0
	}
	g_FireTime = 0.0
	g_Pressing = 0
	g_Watch = 1
	bench_wait_until("pierce_one_shot", "pierce_shot", 5.0, g_P[0])
}

// Holds fire until the shot's event comes, then lets go the next frame: one shot.
public bool:pierce_one_shot(id)
{
	if (g_FireTime > 0.0)
	{
		bench_puppet_input(id, 0)
		return true
	}
	if (!g_Pressing)
	{
		g_Pressing = 1
		bench_puppet_input(id, IN_ATTACK)
	}
	return false
}

public pierce_shot(id)
{
	bench_next("pierce_counted", 1.0)
}

public pierce_counted()
{
	g_Watch = 0
	server_print("ts_gamerules: one flying Five-seveN shot: front player hit %d times (first %.3f s after), back player %d times (first %.3f s after)",
		g_Hits[0], g_FirstHit[0] - g_FireTime, g_Hits[1], g_FirstHit[1] - g_FireTime)
	ASSERT(g_FireTime > 0.0)
	ASSERT(g_Hits[0] >= 1)
	ASSERT(g_Hits[1] == 0 || g_FirstHit[1] > g_FirstHit[0])
	ASSERT_EQ(g_Hits[0] + g_Hits[1], 2)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// A team list's name that comes twice keeps both places: with the teams "dup;dup;third" and the
// models "seal|merc|gordon", a player of "third" (the second of the game's own two teams, joined
// with "jointeam 2") wears the third team's model, gordon. The server is put in teamplay for the
// test, with that list. The game runs game.cfg as it makes the rules, after the test has set the
// list, so a game.cfg that sets the team list or models is put aside for the map change (as
// tsgr_game.cfg) and back once the new map is up, or when this file loads next if the server
// went down in between.

#define GAMECFG "game.cfg"
#define GAMECFG_SAVED "tsgr_game.cfg"

RestoreGameCfg()
{
	if (file_exists(GAMECFG_SAVED))
	{
		delete_file(GAMECFG)
		rename_file(GAMECFG_SAVED, GAMECFG, 1)
	}
}

// Copies game.cfg aside and writes it back without its team list and team models lines; does
// nothing when it has neither.
new g_CfgLines[32][128]

SetGameCfgAside()
{
	new f = fopen(GAMECFG, "rt")
	if (!f)
		return
	new count = 0, found = 0
	while (count < sizeof(g_CfgLines) && fgets(f, g_CfgLines[count], charsmax(g_CfgLines[])))
	{
		if (containi(g_CfgLines[count], "mp_teamlist") != -1 || containi(g_CfgLines[count], "mp_teammodels") != -1)
			found = 1
		count++
	}
	fclose(f)
	if (!found)
		return
	rename_file(GAMECFG, GAMECFG_SAVED, 1)
	f = fopen(GAMECFG, "wt")
	for (new i = 0; i < count; i++)
		if (containi(g_CfgLines[i], "mp_teamlist") == -1 && containi(g_CfgLines[i], "mp_teammodels") == -1)
			fputs(f, g_CfgLines[i])
	fclose(f)
}

public test_repeated_team_name_keeps_its_place()
{
	bench_set_timeout(120.0)
	// the server's own settings, put back before the map goes back (plugin variables start over)
	new v[256]
	get_cvar_string("mp_teamlist", v, charsmax(v))
	set_localinfo("tsgr_teamlist", v)
	get_cvar_string("mp_teammodels", v, charsmax(v))
	set_localinfo("tsgr_teammodels", v)
	set_localinfo("tsgr_teamplay", get_cvar_num("mp_teamplay") ? "1" : "0")
	g_Teamplay = 1
	set_cvar_num("mp_teamplay", 1)
	set_cvar_string("mp_teamlist", "dup;dup;third")
	set_cvar_string("mp_teammodels", "seal|merc|gordon")
	SetGameCfgAside()
	bench_change_map(g_Map, "dup_map")
}

public dup_map()
{
	g_Teamplay = 1
	RestoreGameCfg()
	g_P[0] = bench_puppet("thirdteam")
	ASSERT(g_P[0] > 0)
	bench_puppet_spawn(g_P[0], "dup_spawned", 20.0, "respawn")
}

public dup_spawned(id)
{
	bench_puppet_cmd(id, "jointeam 2")
	bench_next("dup_joined", 0.5, id)
}

public dup_joined(id)
{
	bench_puppet_spawn(id, "dup_respawned", 20.0, "respawn")
}

public dup_respawned(id)
{
	new team[32], model[32]
	get_user_team(id, team, charsmax(team))
	get_user_info(id, "model", model, charsmax(model))
	server_print("ts_gamerules: team %s, model %s", team, model)
	// 1: in "third"; 2: wearing gordon
	new result = (equal(team, "third") ? 1 : 0) | (equal(model, "gordon") ? 2 : 0)
	RestoreTeamCvars()
	bench_change_map(g_Map, "dup_restored", result)
}

RestoreTeamCvars()
{
	new v[256]
	get_localinfo("tsgr_teamplay", v, charsmax(v))
	if (!v[0])
		return
	set_localinfo("tsgr_teamplay", "")
	set_cvar_num("mp_teamplay", str_to_num(v))
	get_localinfo("tsgr_teamlist", v, charsmax(v))
	set_cvar_string("mp_teamlist", v)
	get_localinfo("tsgr_teammodels", v, charsmax(v))
	set_cvar_string("mp_teammodels", v)
	g_Teamplay = 0
}

public dup_restored(result)
{
	ASSERT(result & 1)
	ASSERT(result & 2)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Any player votes, a spectator too, and "vote map" takes the first word after "map": a spectator's
// "vote map crossfire now" is a vote for crossfire. "vote stats" then lists the last count, each map
// with its votes and the votes needed: four players need two, so after the next count (every ten
// seconds) the voter is told "(1/2) votes for crossfire".

public test_spectator_votes_and_stats_list_the_count()
{
	bench_set_timeout(60.0)
	for (new i = 0; i < 4; i++)
	{
		new name[16]
		formatex(name, charsmax(name), "watcher%d", i)
		g_P[i] = bench_puppet(name)
		ASSERT(g_P[i] > 0)
	}
	bench_next("watchers_in", 1.0)
}

public watchers_in()
{
	ASSERT_FALSE(is_user_alive(g_P[0]))
	bench_puppet_say(g_P[0], "vote map crossfire now")
	bench_next("watcher_voted", 0.5)
}

public watcher_voted()
{
	ASSERT_MSG(g_P[1], "", "vote for map crossfire")
	// a count comes within ten seconds
	bench_next("watcher_counted", 11.0)
}

public watcher_counted()
{
	bench_puppet_say(g_P[0], "vote stats")
	bench_next("watcher_stats", 0.5)
}

public watcher_stats()
{
	new BenchMsg:msg = bench_msg_last(g_P[0], "TextMsg", "votes for")
	new text[96]
	if (msg != BenchMsg:0)
		bench_msg_text(msg, text, charsmax(text))
	server_print("ts_gamerules: vote stats: %s", text)
	ASSERT(contain(text, "(1/2) votes for crossfire") != -1)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// A ts_mapglobals has no think: it is due to think ten seconds after it spawns, and then never
// again (its next think time stays 0).

public test_mapglobals_thinks_once()
{
	bench_set_timeout(60.0)
	new ent = CreateMapGlobals(0)
	ASSERT(ent > 0)
	new Float:next
	pev(ent, pev_nextthink, next)
	server_print("ts_gamerules: ts_mapglobals due to think %.1f s after it spawned", next - get_gametime())
	ASSERT(next > get_gametime() + 9.0)
	bench_next("mapglobals_later", 11.0, ent)
}

public mapglobals_later(ent)
{
	new Float:next
	pev(ent, pev_nextthink, next)
	server_print("ts_gamerules: ts_mapglobals next think %.1f", next)
	engfunc(EngFunc_RemoveEntity, ent)
	ASSERT(next == 0.0)
	bench_pass()
}
