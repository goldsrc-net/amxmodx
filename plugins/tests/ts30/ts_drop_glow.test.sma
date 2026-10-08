// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for how the original The Specialists 3.0 shows a dropped gun: the gun itself has no glow, and
// the entity state the game builds for the player who dropped it (AddToFullPack) draws it with a
// white glow shell, which no other player gets. ../ts_drop_glow.test.sma is the same on reTS.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon id.
#define GLOCK18		1

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
