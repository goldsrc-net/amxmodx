// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for what the original The Specialists 3.0 gives a gun a player drops and a knife or grenade he
// throws: how long a dropped gun lies, its skin, and the slow-motion rate each starts at.
// ../ts_dropped.test.sma is the same on reTS.
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
#define M61			24
#define KNIFE		25

new g_Gun
new Float:g_Dropped
new Float:g_Stay

public plugin_init()
{
	register_plugin("TS Dropped Tests", AMXX_VERSION_STR, "AMXX Dev Team")
}

public bench_setup()
{
	g_Stay = get_cvar_float("weaponstay")
}

public bench_teardown()
{
	set_cvar_float("weaponstay", g_Stay)
	new const classnames[][] = { "WorldGun", "knife", "grenade" }
	for (new i = 0; i < sizeof(classnames); i++)
	{
		new ent = -1
		while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classnames[i])))
			engfunc(EngFunc_RemoveEntity, ent)
	}
}

FindClass(const classname[])
{
	return max(engfunc(EngFunc_FindEntityByString, -1, "classname", classname), 0)
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

Float:Fuser1(ent)
{
	new Float:value
	pev(ent, pev_fuser1, value)
	return value
}

bool:IsWorldGun(ent)
{
	if (!pev_valid(ent))
		return false
	new classname[32]
	pev(ent, pev_classname, classname, charsmax(classname))
	return equal(classname, "WorldGun") != 0
}

// Throwing a little up, the way with the most room, keeps a knife or grenade in the air a while.
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

public bool:gun_dropped(id)
{
	return FindClass("WorldGun") != 0
}

// A gun dropped with the drop key lies twice weaponstay (clamped 10 to 120 s), not weaponstay
// (clamped 5 to 60 s) as a gun dropped any other way.
public test_drop_key_doubles_the_lifetime()
{
	set_cvar_float("weaponstay", 6.0)
	new id = bench_puppet("staydrop")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "stay_spawned", 20.0, "respawn")
}

public stay_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	bench_next("stay_armed", 1.0, id)
}

public stay_armed(id)
{
	bench_puppet_cmd(id, "drop")
	bench_wait_until("gun_dropped", "stay_dropped", 1.0, id)
}

public stay_dropped(id)
{
	g_Gun = FindClass("WorldGun")
	g_Dropped = get_gametime()
	// Past weaponstay (6 s), short of twice it (12 s).
	bench_next("stay_nine", 9.0, id)
}

public stay_nine(id)
{
	ASSERT(IsWorldGun(g_Gun))
	bench_next("stay_thirteen", 13.5 - (get_gametime() - g_Dropped), id)
}

public stay_thirteen(id)
{
	ASSERT_FALSE(IsWorldGun(g_Gun))
	bench_pass()
}

// The dropped gun keeps its world model's skin, whatever the dropper's, and runs at the dropper's
// slow-motion rate (1.0 here).
public test_dropped_gun_keeps_no_skin()
{
	new id = bench_puppet("skindrop")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "skin_spawned", 20.0, "respawn")
}

public skin_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	bench_next("skin_armed", 1.0, id)
}

public skin_armed(id)
{
	set_pev(id, pev_skin, 2)
	bench_puppet_cmd(id, "drop")
	bench_wait_until("gun_dropped", "skin_dropped", 1.0, id)
}

public skin_dropped(id)
{
	new gun = FindClass("WorldGun")
	ASSERT_EQ(pev(gun, pev_skin), 0)
	ASSERT_NEAR(Fuser1(gun), 1.0)
	bench_pass()
}

// In his own slow motion a player's dropped gun starts at the rate he slows others to (0.35).
public test_dropped_gun_takes_the_droppers_slow_motion()
{
	new id = bench_puppet("slowdrop")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "slowdrop_spawned", 20.0, "respawn")
}

public slowdrop_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 0, 0)
	ts_set_fakeslowmo(id, 10.0)
	bench_next("slowdrop_armed", 1.0, id)
}

public slowdrop_armed(id)
{
	bench_puppet_cmd(id, "drop")
	bench_wait_until("gun_dropped", "slowdrop_dropped", 1.0, id)
}

public slowdrop_dropped(id)
{
	ASSERT_NEAR(Fuser1(FindClass("WorldGun")), 0.35)
	bench_pass()
}

// So does a knife he throws.
public test_thrown_knife_takes_the_throwers_slow_motion()
{
	new id = bench_puppet("slowknife")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "slowknife_spawned", 20.0, "respawn")
}

public slowknife_spawned(id)
{
	ts_giveweapon(id, KNIFE, 1, 0)
	ts_set_fakeslowmo(id, 10.0)
	LookUp(id)
	bench_next("slowknife_ready", 1.0, id)
}

public slowknife_ready(id)
{
	bench_puppet_input(id, IN_ATTACK2)
	bench_wait_until("knife_thrown", "slowknife_thrown", 2.0, id)
}

public bool:knife_thrown(id)
{
	return FindClass("knife") != 0
}

public slowknife_thrown(id)
{
	bench_puppet_input(id, 0)
	ASSERT_NEAR(Fuser1(FindClass("knife")), 0.35)
	bench_pass()
}

// And a grenade.
public test_grenade_takes_the_throwers_slow_motion()
{
	new id = bench_puppet("slowgren")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "slowgren_spawned", 20.0, "respawn")
}

public slowgren_spawned(id)
{
	ts_giveweapon(id, M61, 1, 0)
	ts_set_fakeslowmo(id, 10.0)
	LookUp(id)
	bench_next("slowgren_pull", 1.0, id)
}

public slowgren_pull(id)
{
	// Slow motion stretches the pull, so it is held longer than at the normal rate.
	bench_puppet_input(id, IN_ATTACK)
	bench_next("slowgren_release", 1.0, id)
}

public slowgren_release(id)
{
	bench_puppet_input(id, 0)
	bench_wait_until("grenade_thrown", "slowgren_thrown", 4.0, id)
}

public bool:grenade_thrown(id)
{
	return FindClass("grenade") != 0
}

public slowgren_thrown(id)
{
	ASSERT_NEAR(Fuser1(FindClass("grenade")), 0.35)
	bench_pass()
}
