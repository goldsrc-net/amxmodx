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
// silently.
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
new g_Developer
new g_Pressed

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
		set_pev(g_Spots[i] & 0xffff, pev_classname, engfunc(EngFunc_AllocString, "tsgr_hidden_spot"))
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
		set_pev(g_Spots[i] & 0xffff, pev_classname,
			engfunc(EngFunc_AllocString, g_SpotClasses[g_Spots[i] >> 16]))
	g_SpotCount = 0
	ASSERT_EQ(said, 0)
	bench_pass()
}
