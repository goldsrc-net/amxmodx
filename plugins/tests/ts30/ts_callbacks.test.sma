// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the engine callbacks of the original The Specialists 3.0 with what a plugin can hand
// them. A trace with no entity to skip passes the engine a NULL edict to the game's ShouldCollide (a
// hull; a line skips the world instead), which lets the touched entity's own ShouldCollide decide
// (0x9b7b4), so the trace hits a player in its way. A flying dropped gun's own ShouldCollide
// (0x91290) lets everything collide with it but other dropped guns and thrown knives. ServerActivate
// (0x9e928) activates the edicts from clientMax on, never the world.
// ../ts_callbacks.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//
// The original's gun ShouldCollide reads the other entity without a check, so a hull that skips no
// entity and reaches a flying gun would crash TS 3.0: no test here makes one while a gun flies, and
// every dropped gun and knife is removed after each test.
//

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <xs>
#include <tsx>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1
#define KNIFE		25

new g_P
new g_Target
new g_WorldActivated

// What the touched entity's ShouldCollide answered for a move by the first named into the second,
// and how often it was asked.
enum
{
	GUN_AT_PLAYER,
	PLAYER_AT_GUN,
	GUN_AT_KNIFE,
	KNIFE_AT_GUN,
	GUN_AT_GUN,
	WORLD_AT_GUN,
	PAIRS
}

new const g_PairNames[PAIRS][] = { "gun at player", "player at gun", "gun at knife", "knife at gun",
	"gun at gun", "world at gun" }
new g_Answer[PAIRS]
new g_Asked[PAIRS]
new bool:g_Watch
new g_Gun
new g_Other
new g_Knife

public plugin_precache()
{
	// The world's private data exists by now; ServerActivate comes after the precache.
	RegisterHamFromEntity(Ham_Activate, 0, "world_activated")
}

public plugin_init()
{
	register_plugin("TS Callback Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_forward(FM_ShouldCollide, "should_collide", 1)
}

public world_activated(ent)
{
	g_WorldActivated++
	return HAM_IGNORED
}

public bench_teardown()
{
	g_Watch = false
	RemoveThrown()
}

RemoveThrown()
{
	new const classnames[][] = { "WorldGun", "knife" }
	for (new i = 0; i < sizeof(classnames); i++)
	{
		new ent = -1
		while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classnames[i])))
			engfunc(EngFunc_RemoveEntity, ent)
	}
}

public should_collide(touched, other)
{
	if (!g_Watch)
		return FMRES_IGNORED
	new pair = -1
	if (touched == g_Target && other == g_Gun)
		pair = GUN_AT_PLAYER
	else if (touched == g_Gun && other == g_Target)
		pair = PLAYER_AT_GUN
	else if (touched == g_Knife && other == g_Gun)
		pair = GUN_AT_KNIFE
	else if (touched == g_Gun && other == g_Knife)
		pair = KNIFE_AT_GUN
	else if (touched == g_Other && other == g_Gun)
		pair = GUN_AT_GUN
	else if (touched == g_Gun && other == 0)
		pair = WORLD_AT_GUN
	if (pair >= 0)
	{
		g_Asked[pair]++
		g_Answer[pair] = get_orig_retval()
	}
	return FMRES_IGNORED
}

// A line from one entity to another, skipping the first: the engine asks each solid entity on the
// way, the second among them, whether the first collides with it.
Trace(from, to)
{
	new Float:start[3], Float:end[3], Float:fraction
	pev(from, pev_origin, start)
	pev(to, pev_origin, end)
	engfunc(EngFunc_TraceLine, start, end, DONT_IGNORE_MONSTERS, from, 0)
	get_tr2(0, TR_flFraction, fraction)
	server_print("ts_callbacks: line %d (%.0f %.0f %.0f) to %d (%.0f %.0f %.0f): fraction %.3f, hit %d",
		from, start[0], start[1], start[2], to, end[0], end[1], end[2], fraction, get_tr2(0, TR_pHit))
}

// Keeps a flying gun or knife in the air (still solid, as it flies) beside and above the player:
// off the ground, a still gun does not settle into a trigger. Each sits off the others' lines.
Hold(ent, id, Float:x, Float:y, Float:z)
{
	new Float:origin[3], Float:none[3]
	pev(id, pev_origin, origin)
	origin[0] += x
	origin[1] += y
	origin[2] += z
	set_pev(ent, pev_movetype, MOVETYPE_NONE)
	set_pev(ent, pev_velocity, none)
	set_pev(ent, pev_flags, pev(ent, pev_flags) & ~FL_ONGROUND)
	engfunc(EngFunc_SetOrigin, ent, origin)
}

FindClass(const classname[], skip = 0)
{
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classname)) > 0)
		if (ent != skip)
			return ent
	return 0
}

// Throwing a little up, the way with the most room, keeps a knife in the air a while.
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

// A line and a point hull from just above a player's head down through him, skipping no entity,
// both stop at him.
public test_trace_with_no_skip_entity_hits_a_player()
{
	g_P = bench_puppet("traced")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "traced_spawned", 20.0, "respawn")
}

public traced_spawned(id)
{
	new Float:origin[3], Float:start[3], Float:end[3]
	pev(id, pev_origin, origin)
	start = origin
	start[2] += 64.0
	end = origin
	end[2] -= 16.0

	new tr = create_tr2()
	engfunc(EngFunc_TraceLine, start, end, DONT_IGNORE_MONSTERS, 0, tr)
	new hit = get_tr2(tr, TR_pHit)
	new Float:fraction
	get_tr2(tr, TR_flFraction, fraction)
	server_print("ts_callbacks: line hit %d (player %d), fraction %f", hit, id, fraction)
	ASSERT_EQ(hit, id)
	ASSERT(fraction < 1.0)

	engfunc(EngFunc_TraceHull, start, end, DONT_IGNORE_MONSTERS, HULL_POINT, 0, tr)
	hit = get_tr2(tr, TR_pHit)
	server_print("ts_callbacks: hull hit %d", hit)
	free_tr2(tr)
	ASSERT_EQ(hit, id)
	bench_pass()
}

// The touched entity decides. A flying gun meets a player (the player's default: collide), a knife
// (the knife's own ShouldCollide: collide) and another flying gun (that gun's: not with a gun); a
// knife meets a flying gun (that gun's: not with a knife), and so does a line skipping the world
// (collide). The engine does not ask a flying gun, which has no size, about a player moving into
// it.
public test_flying_gun_collides_as_the_original()
{
	for (new i = 0; i < PAIRS; i++)
	{
		g_Answer[i] = -1
		g_Asked[i] = 0
	}
	g_Gun = 0
	g_Other = 0
	g_Knife = 0
	// The gun's dropper owns it, and no move between an entity and its owner asks: the player it
	// meets is another.
	g_Target = bench_puppet("collidee")
	ASSERT(g_Target > 0)
	bench_puppet_spawn(g_Target, "collide_target_spawned", 20.0, "respawn")
}

public collide_target_spawned(target)
{
	g_P = bench_puppet("collider")
	ASSERT(g_P > 0)
	bench_puppet_spawn(g_P, "collide_spawned", 20.0, "respawn")
}

public collide_spawned(id)
{
	// The other player stands beside the dropper, where a line from the gun above him reaches.
	ASSERT(bench_puppet_face(g_Target, id, 32.0))
	ts_giveweapon(id, KNIFE, 1, 0)
	LookUp(id)
	bench_next("collide_knife_ready", 1.0, id)
}

public collide_knife_ready(id)
{
	bench_puppet_input(id, IN_ATTACK2)
	bench_wait_until("knife_thrown", "collide_knife_thrown", 2.0, id)
}

public bool:knife_thrown(id)
{
	return FindClass("knife") != 0
}

public collide_knife_thrown(id)
{
	bench_puppet_input(id, 0)
	g_Knife = FindClass("knife")
	ASSERT_EQ(pev(g_Knife, pev_solid), SOLID_BBOX)
	Hold(g_Knife, id, 12.0, 8.0, 60.0)
	ts_giveweapon(id, GLOCK18, 0, 0)
	bench_next("collide_armed", 1.0, id)
}

public collide_armed(id)
{
	bench_puppet_cmd(id, "drop")
	bench_wait_until("gun_dropped", "collide_dropped", 1.0, id)
}

public bool:gun_dropped(id)
{
	return FindClass("WorldGun", g_Gun) != 0
}

public collide_dropped(id)
{
	g_Gun = FindClass("WorldGun")
	// Still in flight: a landed gun is a trigger, which no trace asks.
	ASSERT_EQ(pev(g_Gun, pev_solid), SOLID_BBOX)
	Hold(g_Gun, id, 0.0, 0.0, 48.0)
	// Before the second gun flies: a gun that refuses a move ends the stock engine's search of its
	// area node, which could hide an entity after it.
	g_Watch = true
	Trace(g_Gun, g_Target)
	Trace(g_Gun, g_Knife)
	Trace(g_Target, g_Gun)
	Trace(g_Knife, g_Gun)
	g_Watch = false
	ts_giveweapon(id, GLOCK18, 0, 0)
	bench_next("collide_rearmed", 1.0, id)
}

public collide_rearmed(id)
{
	bench_puppet_cmd(id, "drop")
	bench_wait_until("gun_dropped", "collide_second", 1.0, id)
}

public collide_second(id)
{
	g_Other = FindClass("WorldGun", g_Gun)
	ASSERT_EQ(pev(g_Other, pev_solid), SOLID_BBOX)
	Hold(g_Other, id, -12.0, 8.0, 72.0)
	g_Watch = true
	Trace(g_Gun, g_Other)
	// A line skipping the world (entity 0), from the player's head up to the gun.
	new Float:start[3], Float:end[3]
	pev(id, pev_origin, start)
	start[2] += 40.0
	pev(g_Gun, pev_origin, end)
	engfunc(EngFunc_TraceLine, start, end, DONT_IGNORE_MONSTERS, 0, 0)
	g_Watch = false
	RemoveThrown()

	for (new i = 0; i < PAIRS; i++)
		server_print("ts_callbacks: %s asked %d, answer %d", g_PairNames[i], g_Asked[i], g_Answer[i])
	ASSERT_EQ(g_Answer[GUN_AT_PLAYER], 1)
	ASSERT_EQ(g_Asked[PLAYER_AT_GUN], 0)
	ASSERT_EQ(g_Answer[GUN_AT_KNIFE], 1)
	ASSERT_EQ(g_Answer[KNIFE_AT_GUN], 0)
	ASSERT_EQ(g_Answer[GUN_AT_GUN], 0)
	ASSERT_EQ(g_Answer[WORLD_AT_GUN], 1)
	bench_pass()
}

// ServerActivate skips edicts 0 to clientMax - 1, so the world's Activate never runs.
public test_world_is_not_activated()
{
	server_print("ts_callbacks: world activated %d times", g_WorldActivated)
	ASSERT_EQ(g_WorldActivated, 0)
	bench_pass()
}
