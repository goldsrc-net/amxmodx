// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for how the original The Specialists 3.0 shows a dropped gun and a thrown knife: the entity
// itself has no glow, and the entity state the game builds for the player who dropped or threw it
// (AddToFullPack) draws it with a white glow shell, which no other player gets.
// ../ts_drop_glow.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <xs>
#include <tsx>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1
#define KNIFE		25

new g_P[2]

public plugin_init()
{
	register_plugin("TS Drop Glow Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_teardown()
{
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "WorldGun")))
		engfunc(EngFunc_RemoveEntity, ent)
	ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "knife")))
		engfunc(EngFunc_RemoveEntity, ent)
}

FindClass(const classname[])
{
	return engfunc(EngFunc_FindEntityByString, -1, "classname", classname)
}

// What the game sends player `host` about entity `ent`: its render fx, amount and colour.
bool:StateFor(ent, host, &fx, &amt, color[3])
{
	if (!dllfunc(DLLFunc_AddToFullPack, 0, ent, ent, host, 0, 0, 0))
		return false
	fx = get_es(0, ES_RenderFx)
	amt = get_es(0, ES_RenderAmt)
	get_es(0, ES_RenderColor, color)
	return true
}

public test_dropped_gun_glows_for_the_dropper_only()
{
	g_P[0] = bench_puppet("glowdrop")
	g_P[1] = bench_puppet("glowsee")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[1], "glow_watcher", 20.0, "respawn")
}

public glow_watcher(id)
{
	bench_puppet_spawn(g_P[0], "glow_spawned", 20.0, "respawn")
}

public glow_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	bench_next("glow_armed", 1.0, id)
}

public glow_armed(id)
{
	bench_puppet_cmd(id, "drop")
	bench_wait_until("glow_gun_dropped", "glow_check", 1.0, id)
}

public bool:glow_gun_dropped(id)
{
	return FindClass("WorldGun") != 0
}

public glow_check(id)
{
	new gun = FindClass("WorldGun")
	ASSERT_EQ(pev(gun, pev_renderfx), kRenderFxNone)

	new fx, amt, color[3]
	ASSERT(StateFor(gun, g_P[0], fx, amt, color))
	ASSERT_EQ(fx, kRenderFxGlowShell)
	ASSERT_EQ(amt, 2)
	ASSERT_EQ(color[0], 100)
	ASSERT_EQ(color[1], 100)
	ASSERT_EQ(color[2], 100)

	ASSERT(StateFor(gun, g_P[1], fx, amt, color))
	ASSERT_EQ(fx, kRenderFxNone)
	bench_pass()
}

// Throwing a little up, the way with the most room, keeps the knife in the air a while.
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

// The thrower is kept in the knife itself, not as its owner, and only he sees it glow.
public test_thrown_knife_glows_for_the_thrower_only()
{
	g_P[0] = bench_puppet("glowthrow")
	g_P[1] = bench_puppet("glowwatch")
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[1], "knife_watcher", 20.0, "respawn")
}

public knife_watcher(id)
{
	bench_puppet_spawn(g_P[0], "knife_spawned", 20.0, "respawn")
}

public knife_spawned(id)
{
	ts_giveweapon(id, KNIFE, 1, 0)
	LookUp(id)
	bench_next("knife_ready", 1.0, id)
}

public knife_ready(id)
{
	bench_puppet_input(id, IN_ATTACK2)
	bench_wait_until("knife_thrown", "knife_check", 2.0, id)
}

public bool:knife_thrown(id)
{
	return FindClass("knife") != 0
}

public knife_check(id)
{
	bench_puppet_input(id, 0)
	new knife = FindClass("knife")
	ASSERT_EQ(pev(knife, pev_owner), 0)
	ASSERT_EQ(pev(knife, pev_renderfx), kRenderFxNone)

	new fx, amt, color[3]
	ASSERT(StateFor(knife, g_P[0], fx, amt, color))
	ASSERT_EQ(fx, kRenderFxGlowShell)
	ASSERT_EQ(amt, 2)
	ASSERT_EQ(color[0], 100)
	ASSERT_EQ(color[1], 100)
	ASSERT_EQ(color[2], 100)

	ASSERT(StateFor(knife, g_P[1], fx, amt, color))
	ASSERT_EQ(fx, kRenderFxNone)
	bench_pass()
}
