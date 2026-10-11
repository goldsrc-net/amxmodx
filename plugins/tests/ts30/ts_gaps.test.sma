// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for server behaviour of The Specialists 3.0 that reTS has to match: the cvars the game
// does not register; the game's teamplay flag taken from the rules, not from mp_teamplay; the chat
// (the %h and %a substitutions, "timeleft", the "(TEAM)" prefix a spectator gets, the half-second
// chat clock); the stock Half-Life models refused as a player model in deathmatch; the timer and
// custom target entities; the ammo pack a dead player leaves; the grenades a dead player leaves;
// the M61 left out of the spawn loadout outside the round modes; the cold cock's close-combat
// damage bit; and no server-side bullet trail sprites with realbullet.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//
// They pass in deathmatch and in teamplay; the model test only checks deathmatch.
//

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <tsx>
#include <tsfun>
#include <amxxbench>

// The Specialists 3.0 weapon ids.
#define GLOCK18		1
#define DEAGLE		12
#define M61			24

// The close-combat damage bit The Specialists adds to melee hits.
#define DMG_TSCLOSECOMBAT	0x4000000

new g_P[2]
new g_Weapon
new g_After[32]
new g_RealBullet[16]
new g_FriendlyFire
new g_TeamplayCvar
new g_DamageBits
new g_Trails
new bool:g_Grenades
new Float:g_Fell[3]

public plugin_init()
{
	register_plugin("TS 3.0 Server Gap Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	RegisterHam(Ham_TakeDamage, "player", "on_damage")
	register_forward(FM_SetModel, "on_set_model")
}

public bench_setup()
{
	g_DamageBits = -1
	g_Trails = 0
	get_cvar_string("realbullet", g_RealBullet, charsmax(g_RealBullet))
	g_FriendlyFire = get_cvar_num("mp_friendlyfire")
	g_TeamplayCvar = get_cvar_num("mp_teamplay")
	g_Grenades = false
}

public bench_teardown()
{
	set_cvar_string("realbullet", g_RealBullet)
	set_cvar_num("mp_friendlyfire", g_FriendlyFire)
	if (get_cvar_num("mp_teamplay") != g_TeamplayCvar)
		set_cvar_num("mp_teamplay", g_TeamplayCvar)
	// The grenades a dead player left, so the next player to spawn does not pick them up.
	if (g_Grenades)
	{
		new ent = -1, Float:origin[3]
		while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_powerup")))
		{
			pev(ent, pev_origin, origin)
			if (get_distance_f(origin, g_Fell) < 64.0)
				set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_KILLME)
		}
	}
}

public on_damage(victim, inflictor, attacker, Float:damage, bits)
{
	if (g_P[1] && victim == g_P[1] && attacker == g_P[0])
		g_DamageBits = bits
	return HAM_IGNORED
}

public on_set_model(ent, const model[])
{
	if (contain(model, "bullet_trail") != -1 || contain(model, "shotgun_pellets") != -1)
		g_Trails++
	return FMRES_IGNORED
}

// Holds buttons for a fifth of a second, then calls step(id).
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

// Stands a dist units from b's bounds, facing b's middle.
bool:Face(a, b, Float:dist)
{
	if (!bench_puppet_face(a, b, dist))
		return false
	new Float:target[3]
	pev(b, pev_origin, target)
	bench_puppet_look_at(a, target)
	return true
}

// Makes an attacker and a target, both alive, the attacker holding weapon, then calls step.
new g_Ready[32]

Pair(const attacker[], const target[], weapon, const step[])
{
	copy(g_Ready, charsmax(g_Ready), step)
	g_Weapon = weapon
	g_P[0] = bench_puppet(attacker)
	g_P[1] = bench_puppet(target)
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	bench_puppet_spawn(g_P[1], "pair_target", 20.0, "respawn")
}

public pair_target(id)
{
	bench_puppet_spawn(g_P[0], "pair_attacker", 20.0, "respawn")
}

public pair_attacker(id)
{
	ts_giveweapon(id, g_Weapon, 100, 0)
	bench_wait_until("holds_it", "pair_armed", 3.0, id)
}

public bool:holds_it(id)
{
	new BenchMsg:msg = bench_msg_last(id, "WeaponInfo")
	return msg != BenchMsg:0 && bench_msg_int(msg, 0) == g_Weapon
}

public pair_armed(id)
{
	bench_next(g_Ready, 1.0, id)
}

// Kills puppet id as the world does, at once (a suicide right after spawning is refused).
Die(id)
{
	set_pev(id, pev_health, 1.0)
	ExecuteHamB(Ham_TakeDamage, id, 0, 0, 10.0, DMG_GENERIC)
}

// Whether puppet id was sent a WeaponInfo for weapon this test.
bool:WasGiven(id, weapon)
{
	new BenchMsg:msg = BenchMsg:0
	while ((msg = bench_msg_next(id, msg, "WeaponInfo")) != BenchMsg:0)
		if (bench_msg_int(msg, 0) == weapon)
			return true
	return false
}

CountClass(const classname[])
{
	new ent = -1, count = 0
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classname)))
		count++
	return count
}

// --- cvars -----------------------------------------------------------------------------------

// The game defines initial_cash, cashforwin, cashforlose and respawnnumber but registers none of
// them (GameDLLInit @0x9b9a0; the 3.0 changelog: "Removed initial_cash ... set at 1200").
public test_unregistered_cvars()
{
	ASSERT_FALSE(cvar_exists("initial_cash"))
	ASSERT_FALSE(cvar_exists("cashforwin"))
	ASSERT_FALSE(cvar_exists("cashforlose"))
	ASSERT_FALSE(cvar_exists("respawnnumber"))
	// The ones it does register around them.
	ASSERT(cvar_exists("respawntime"))
	ASSERT(cvar_exists("usecash"))
	bench_pass()
}

// StartFrame copies the rules' teamplay decision into the engine's teamplay flag every frame
// (@0x9eadc), so changing mp_teamplay mid-map does not change it.
new g_TeamplayFlag

public test_teamplay_flag_follows_the_rules()
{
	new Float:flag
	global_get(glb_teamplay, flag)
	g_TeamplayFlag = floatround(flag)
	set_cvar_num("mp_teamplay", g_TeamplayCvar ? 0 : 1)
	bench_next("flag_after", 0.3)
}

public flag_after()
{
	new Float:flag
	global_get(glb_teamplay, flag)
	new now = floatround(flag)
	set_cvar_num("mp_teamplay", g_TeamplayCvar)
	ASSERT_EQ(now, g_TeamplayFlag)
	bench_pass()
}

// --- chat ------------------------------------------------------------------------------------

// %h in chat is the sender's health and %a "no kevlar" or "with kevlar" (@0x9d25c).
public test_chat_health_and_kevlar()
{
	new id = bench_puppet("hpsayer")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "hp_spawned", 20.0, "respawn")
}

public hp_spawned(id)
{
	set_pev(id, pev_health, 73.0)
	set_pev(id, pev_armorvalue, 0.0)
	bench_puppet_say(id, "hp %h %a")
	bench_next("hp_said", 0.3, id)
}

public hp_said(id)
{
	ASSERT_MSG(id, "SayText", "hp 73 no kevlar")
	set_pev(id, pev_armorvalue, 40.0)
	// Past the chat clock.
	bench_next("armor_say", 0.7, id)
}

public armor_say(id)
{
	bench_puppet_say(id, "armor %a")
	bench_next("armor_said", 0.3, id)
}

public armor_said(id)
{
	ASSERT_MSG(id, "SayText", "armor with kevlar")
	bench_pass()
}

// "timeleft" in chat answers the sender alone with "Time left: m:ss" and is not shown as chat
// (@0x9d3a1).
public test_chat_timeleft()
{
	new id = bench_puppet("timesayer")
	ASSERT(id > 0)
	bench_next("time_joined", 0.5, id)
}

public time_joined(id)
{
	bench_puppet_say(id, "timeleft")
	bench_next("time_said", 0.3, id)
}

public time_said(id)
{
	ASSERT_MSG(id, "TextMsg", "Time left: ")
	ASSERT_EQ(bench_msg_count(id, "SayText", "timeleft"), 0)
	bench_pass()
}

// A spectator's team chat is prefixed "(TEAM)" like anyone's (@0x9d1c0).
public test_spectator_team_chat_prefix()
{
	new id = bench_puppet("specsayer")
	ASSERT(id > 0)
	bench_next("spec_joined", 0.5, id)
}

public spec_joined(id)
{
	bench_puppet_say(id, "spectating", true)
	bench_next("spec_said", 0.3, id)
}

public spec_said(id)
{
	ASSERT_MSG(id, "SayText", "(TEAM) specsayer: spectating")
	ASSERT_EQ(bench_msg_count(id, "SayText", "(SPEC)"), 0)
	bench_pass()
}

// The chat clock is half a second (@0x9d826): a second line 0.7 s after the first is shown.
public test_chat_clock_is_half_a_second()
{
	new id = bench_puppet("quicksayer")
	ASSERT(id > 0)
	bench_next("quick_joined", 0.5, id)
}

public quick_joined(id)
{
	bench_puppet_say(id, "firstline")
	bench_next("quick_second", 0.7, id)
}

public quick_second(id)
{
	bench_puppet_say(id, "secondline")
	bench_next("quick_said", 0.3, id)
}

public quick_said(id)
{
	ASSERT_MSG(id, "SayText", "firstline")
	ASSERT_MSG(id, "SayText", "secondline")
	bench_pass()
}

// --- the player model ------------------------------------------------------------------------

// In deathmatch a model named after a stock Half-Life one is put back, with "* Can't change team
// to '<model>'" and "* HLDM models not allowed." (@0x7b244).
public test_hldm_model_refused()
{
	if (get_cvar_num("mp_teamplay"))
	{
		bench_pass()
		return
	}
	new id = bench_puppet("modeler")
	ASSERT(id > 0)
	bench_puppet_spawn(id, "model_spawned", 20.0, "respawn")
}

public model_spawned(id)
{
	bench_puppet_setinfo(id, "model", "scientist")
	bench_next("model_set", 0.5, id)
}

public model_set(id)
{
	ASSERT_MSG(id, "SayText", "Can't change team to 'scientist'")
	ASSERT_MSG(id, "SayText", "HLDM models not allowed.")
	new model[32]
	get_user_info(id, "model", model, charsmax(model))
	ASSERT_FALSE(equali(model, "scientist"))
	bench_pass()
}

// --- the point entities ----------------------------------------------------------------------

// ts_timer and ts_customtarget spawn as movetype 5 (fly), not solid (@0x62deb, @0x630b8).
public test_timer_and_custom_target_spawn()
{
	new timer = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_timer"))
	ASSERT(timer > 0)
	dllfunc(DLLFunc_Spawn, timer)
	new target = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "ts_customtarget"))
	ASSERT(target > 0)
	dllfunc(DLLFunc_Spawn, target)
	new tmove = pev(timer, pev_movetype), tsolid = pev(timer, pev_solid)
	new cmove = pev(target, pev_movetype), csolid = pev(target, pev_solid)
	engfunc(EngFunc_RemoveEntity, timer)
	engfunc(EngFunc_RemoveEntity, target)
	ASSERT_EQ(tmove, MOVETYPE_FLY)
	ASSERT_EQ(tsolid, SOLID_NOT)
	ASSERT_EQ(cmove, MOVETYPE_FLY)
	ASSERT_EQ(csolid, SOLID_NOT)
	bench_pass()
}

// --- what a dead player leaves ---------------------------------------------------------------

// A dead player holding reserve rounds leaves them as an AmmoPack, which carries no armor: the
// armor argument of CreateAmmoPack is read nowhere (@0x91334).
new g_Packs

public test_ammo_pack_carries_no_armor()
{
	new id = bench_puppet("packdropper")
	ASSERT(id > 0)
	g_P[0] = id
	g_Weapon = GLOCK18
	bench_puppet_spawn(id, "pack_spawned", 20.0, "respawn")
}

public pack_spawned(id)
{
	ts_giveweapon(id, GLOCK18, 100, 0)
	bench_wait_until("holds_it", "pack_armed", 3.0, id)
}

public pack_armed(id)
{
	set_pev(id, pev_armorvalue, 50.0)
	g_Packs = CountClass("AmmoPack")
	Die(id)
	bench_next("pack_dead", 0.3, id)
}

public pack_dead(id)
{
	ASSERT_FALSE(is_user_alive(id))
	new count = 0, ent = -1, Float:armor = 0.0
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "AmmoPack")))
	{
		if (pev(ent, pev_owner) != id)
			continue
		count++
		armor += Float:pev(ent, pev_armorvalue)
	}
	ASSERT(CountClass("AmmoPack") > g_Packs)
	ASSERT_EQ(count, 1)
	ASSERT_EQ(floatround(armor), 0)
	bench_pass()
}

// A player who dies holding M61 grenades in deathmatch or teamplay leaves them as grenade
// powerups (ts_powerup), 5 units apart (@0x84ac1).
new g_Powerups

public test_dead_players_grenades_become_powerups()
{
	new id = bench_puppet("grenadier")
	ASSERT(id > 0)
	g_P[0] = id
	g_Weapon = M61
	bench_puppet_spawn(id, "gren_spawned", 20.0, "respawn")
}

public gren_spawned(id)
{
	ts_giveweapon(id, M61, 3, 0)
	bench_wait_until("holds_it", "gren_armed", 3.0, id)
}

public gren_armed(id)
{
	g_Powerups = CountClass("ts_powerup")
	pev(id, pev_origin, g_Fell)
	g_Grenades = true
	Die(id)
	bench_next("gren_dead", 0.3, id)
}

public gren_dead(id)
{
	ASSERT_FALSE(is_user_alive(id))
	ASSERT(CountClass("ts_powerup") > g_Powerups)
	new ent = -1, near = 0, Float:origin[3]
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_powerup")))
	{
		pev(ent, pev_origin, origin)
		if (get_distance_f(origin, g_Fell) < 64.0)
			near++
	}
	ASSERT(near > 0)
	bench_pass()
}

// --- the loadout -----------------------------------------------------------------------------

// The spawn loadout buys an M61 only in the round modes (BuyWeapon @0x84616): in deathmatch and
// teamplay the rest of the loadout comes and the grenade does not.
public test_no_m61_in_the_loadout()
{
	new id = bench_puppet("grenbuyer")
	ASSERT(id > 0)
	bench_next("buyer_joined", 0.5, id)
}

public buyer_joined(id)
{
	ts_setusercash(id, 10000)
	bench_puppet_cmd(id, "tkw %d_0 %d_0", GLOCK18, M61)
	bench_puppet_spawn(id, "buyer_spawned", 20.0, "respawn")
}

public buyer_spawned(id)
{
	bench_next("buyer_settled", 1.5, id)
}

public buyer_settled(id)
{
	ASSERT(WasGiven(id, GLOCK18))
	ASSERT_FALSE(WasGiven(id, M61))
	bench_pass()
}

// --- the cold cock ---------------------------------------------------------------------------

// The gun-butt hit adds the close-combat bit to its damage (@0x86a56).
public test_coldcock_is_close_combat()
{
	set_cvar_num("mp_friendlyfire", 1)
	Pair("butter", "butted", DEAGLE, "butt_ready")
}

public butt_ready()
{
	ASSERT(Face(g_P[0], g_P[1], 20.0))
	set_pev(g_P[1], pev_health, 100.0)
	Hold(g_P[0], IN_CANCEL, "butted_him")
}

public butted_him(id)
{
	bench_wait_until("was_hit", "butt_hit", 2.0)
}

public bool:was_hit()
{
	return g_DamageBits != -1
}

public butt_hit()
{
	ASSERT(g_DamageBits & DMG_TSCLOSECOMBAT)
	bench_pass()
}

// --- realbullet ------------------------------------------------------------------------------

// With realbullet the server makes no trail or pellet sprites for the bullets; the client draws
// them.
public test_realbullet_makes_no_server_sprites()
{
	set_cvar_num("realbullet", 1)
	set_cvar_num("mp_friendlyfire", 1)
	Pair("realshooter", "realtarget", GLOCK18, "real_ready")
}

public real_ready()
{
	ASSERT(Face(g_P[0], g_P[1], 200.0))
	g_Trails = 0
	Hold(g_P[0], IN_ATTACK, "real_fired")
}

public real_fired(id)
{
	bench_next("real_done", 0.5)
}

public real_done()
{
	// The shot landed.
	ASSERT(g_DamageBits != -1)
	ASSERT_EQ(g_Trails, 0)
	bench_pass()
}
