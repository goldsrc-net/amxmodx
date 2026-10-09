// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for what The Specialists 3.0's PlayerKilled (0x795e4) does around a kill of one player by
// another: the kill cash (500 a point and 400 more for the killer, 900 for the victim);
// with slowmatch at 1, a slow motion powerup to hold for a scoring kill; a slow-motion bubble where
// the victim fell, after a spectacular kill, as spectacularness allows; the headshot, knife,
// katana and cold cock notices naming the killer; and the kill with the victim's own weapon (the
// one he bought), told to everyone and tagged " (victims_weapon)" in the log.
//
// These need the stock stack (HLDS, TS 3.0 i386): run.sh --tests plugins/tests/ts30 stock
//
// The kills here are scored as in deathmatch. In teamplay a kill of a teammate is a team kill, so
// on a teamplay server the first test changes the map in deathmatch, with game.cfg put aside (as
// tsk_game.cfg) for that change and back once the new map is up, and the last test changes it back
// in teamplay.
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
#define KNIFE		25
#define KATANA		34

new g_P[2]
new g_Weapon
new g_After[32]
new g_Victim
new g_DeathKiller
new g_DeathName[32]
new g_Logged[256]
new g_SlowMatch[16]
new g_Spectacular[16]
new g_FriendlyFire

public plugin_init()
{
	register_plugin("TS Kill Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	register_event("DeathMsg", "on_death_msg", "a")
	RestoreGameCfg()
}

public bench_setup()
{
	g_Victim = 0
	g_DeathKiller = 0
	g_DeathName[0] = 0
	g_Logged[0] = 0
	get_cvar_string("slowmatch", g_SlowMatch, charsmax(g_SlowMatch))
	get_cvar_string("spectacularness", g_Spectacular, charsmax(g_Spectacular))
	g_FriendlyFire = get_cvar_num("mp_friendlyfire")
}

public bench_teardown()
{
	set_cvar_string("slowmatch", g_SlowMatch)
	set_cvar_string("spectacularness", g_Spectacular)
	set_cvar_num("mp_friendlyfire", g_FriendlyFire)
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "ts_slowmotionpoint")))
		engfunc(EngFunc_RemoveEntity, ent)
}

public on_death_msg()
{
	if (!g_Victim || read_data(2) != g_Victim)
		return
	g_DeathKiller = read_data(1)
	read_data(3, g_DeathName, charsmax(g_DeathName))
}

// The game's own "killed" log line for the victim, if any.
public plugin_log()
{
	if (!g_Victim)
		return PLUGIN_CONTINUE
	new line[256], name[32]
	read_logdata(line, charsmax(line))
	get_user_name(g_Victim, name, charsmax(name))
	new pattern[48]
	formatex(pattern, charsmax(pattern), "killed ^"%s<", name)
	if (contain(line, pattern) != -1)
		copy(g_Logged, charsmax(g_Logged), line)
	return PLUGIN_CONTINUE
}

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

// Makes a killer and a victim, both alive, the killer holding weapon (0: nothing, kung fu), then
// calls step.
new g_Ready[32]

Pair(const killer[], const victim[], weapon, const step[])
{
	copy(g_Ready, charsmax(g_Ready), step)
	g_Weapon = weapon
	g_P[0] = bench_puppet(killer)
	g_P[1] = bench_puppet(victim)
	ASSERT(g_P[0] > 0 && g_P[1] > 0)
	g_Victim = g_P[1]
	bench_puppet_spawn(g_P[1], "pair_victim", 20.0, "respawn")
}

public pair_victim(id)
{
	bench_puppet_spawn(g_P[0], "pair_killer", 20.0, "respawn")
}

public pair_killer(id)
{
	if (!g_Weapon)
	{
		bench_next(g_Ready, 1.0, id)
		return
	}
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
	// The gun is out a moment after it comes.
	bench_next(g_Ready, 1.0, id)
}

// The killer does the victim's last point of damage himself, as a shot that hits does, so the kill
// comes in this very frame.
Kill()
{
	set_pev(g_P[1], pev_health, 1.0)
	ExecuteHamB(Ham_TakeDamage, g_P[1], g_P[0], g_P[0], 10.0, DMG_BULLET)
}

public bool:died(id)
{
	return g_DeathKiller != 0
}

// The notice the game told everyone, as a TSMessage to the killer.
bool:Notice(const text[])
{
	return bench_msg_last(g_P[0], "TSMessage", text) != BenchMsg:0
}

// --- deathmatch ------------------------------------------------------------------------------

#define GAMECFG "game.cfg"
#define GAMECFG_SAVED "tsk_game.cfg"

RestoreGameCfg()
{
	if (file_exists(GAMECFG_SAVED))
	{
		delete_file(GAMECFG)
		rename_file(GAMECFG_SAVED, GAMECFG, 1)
	}
}

// Copies game.cfg aside and writes it back without its mp_teamplay line.
new g_CfgLines[32][128]

SetGameCfgAside()
{
	new count = 0
	new f = fopen(GAMECFG, "rt")
	if (!f)
		return
	while (count < sizeof(g_CfgLines) && fgets(f, g_CfgLines[count], charsmax(g_CfgLines[])))
		count++
	fclose(f)
	rename_file(GAMECFG, GAMECFG_SAVED, 1)
	f = fopen(GAMECFG, "wt")
	for (new i = 0; i < count; i++)
		if (containi(g_CfgLines[i], "mp_teamplay") == -1)
			fputs(f, g_CfgLines[i])
	fclose(f)
}

public test_deathmatch_for_the_kill_tests()
{
	if (!get_cvar_num("mp_teamplay"))
	{
		bench_pass()
		return
	}
	set_localinfo("tsk_teamplay", "1")
	set_cvar_num("mp_teamplay", 0)
	SetGameCfgAside()
	new map[32]
	get_mapname(map, charsmax(map))
	bench_change_map(map, "deathmatch_up")
}

public deathmatch_up()
{
	RestoreGameCfg()
	ASSERT_EQ(get_cvar_num("mp_teamplay"), 0)
	bench_pass()
}

// --- the kill cash ---------------------------------------------------------------------------

// A one-point kill pays the killer 1 x 500 + 400 = 900 and the victim 900 (0x7aab8).
public test_kill_pays_cash()
{
	Pair("cashkiller", "cashvictim", GLOCK18, "cash_ready")
}

public cash_ready()
{
	ts_setusercash(g_P[0], 0)
	ts_setusercash(g_P[1], 0)
	Kill()
	bench_wait_until("died", "cash_killed", 1.0)
}

public cash_killed()
{
	bench_next("cash_done", 0.3)
}

public cash_done()
{
	ASSERT_EQ(g_DeathKiller, g_P[0])
	ASSERT_EQ(ts_getusercash(g_P[0]), 900)
	ASSERT_EQ(ts_getusercash(g_P[1]), 900)
	bench_pass()
}

// --- slowmatch -------------------------------------------------------------------------------

// With slowmatch at 1, a kill that scores gives the killer a slow motion powerup to hold, a second
// of it for each such kill, up to 3 (0x7ac15). The PwUp message tells him: type 1, the seconds.
// (Spawning sends him PwUp messages of his own; the one after the kill is new.)
public test_slowmatch_gives_a_slow_motion_powerup()
{
	set_cvar_float("slowmatch", 1.0)
	Pair("slowkiller", "slowvictim", GLOCK18, "slow_ready")
}

new g_PwUps

public slow_ready()
{
	g_PwUps = bench_msg_count(g_P[0], "PwUp")
	Kill()
	bench_wait_until("died", "slow_killed", 1.0)
}

public slow_killed()
{
	bench_next("slow_told", 0.3)
}

public slow_told()
{
	ASSERT(bench_msg_count(g_P[0], "PwUp") > g_PwUps)
	new BenchMsg:msg = bench_msg_last(g_P[0], "PwUp")
	ASSERT_EQ(bench_msg_int(msg, 0), TSPWUP_SLOWMO)
	ASSERT_EQ(bench_msg_int(msg, 1), 1)
	bench_puppet_spawn(g_P[1], "slow_again", 20.0, "respawn")
}

public slow_again(id)
{
	g_DeathKiller = 0
	Kill()
	bench_wait_until("died", "slow_killed_again", 1.0)
}

public slow_killed_again()
{
	bench_next("slow_told_again", 0.3)
}

public slow_told_again()
{
	new BenchMsg:msg = bench_msg_last(g_P[0], "PwUp")
	ASSERT_EQ(bench_msg_int(msg, 0), TSPWUP_SLOWMO)
	ASSERT_EQ(bench_msg_int(msg, 1), 2)
	bench_pass()
}

// With slowmatch at 0 there is none.
public test_no_powerup_without_slowmatch()
{
	set_cvar_float("slowmatch", 0.0)
	Pair("noslowkiller", "noslowvictim", GLOCK18, "noslow_ready")
}

public noslow_ready()
{
	g_PwUps = bench_msg_count(g_P[0], "PwUp")
	Kill()
	bench_wait_until("died", "noslow_killed", 1.0)
}

public noslow_killed()
{
	bench_next("noslow_done", 0.3)
}

public noslow_done()
{
	ASSERT_EQ(bench_msg_count(g_P[0], "PwUp"), g_PwUps)
	bench_pass()
}

// --- the spectacular kill --------------------------------------------------------------------

// A kill by a stunting killer is spectacular: with spectacularness at 100 the roll always wins and
// a slow-motion bubble (ts_slowmotionpoint) appears where the victim fell (0x7a3bb).
new Float:g_Fell[3]

public test_spectacular_kill_leaves_a_slow_motion_bubble()
{
	set_cvar_num("spectacularness", 100)
	Pair("stuntkiller", "stuntvictim", GLOCK18, "stunt_ready")
}

public stunt_ready()
{
	ASSERT_EQ(engfunc(EngFunc_FindEntityByString, -1, "classname", "ts_slowmotionpoint"), 0)
	pev(g_P[1], pev_origin, g_Fell)
	// The dive flag, as a diving killer has it.
	set_pev(g_P[0], pev_iuser4, pev(g_P[0], pev_iuser4) | 0x10)
	Kill()
	bench_wait_until("died", "stunt_killed", 1.0)
}

public stunt_killed()
{
	new ent = engfunc(EngFunc_FindEntityByString, -1, "classname", "ts_slowmotionpoint")
	ASSERT(ent > 0)
	new Float:origin[3]
	pev(ent, pev_origin, origin)
	ASSERT(get_distance_f(origin, g_Fell) < 1.0)
	bench_pass()
}

// A plain kill (one point, no stunt, no close combat) is not.
public test_plain_kill_leaves_no_bubble()
{
	set_cvar_num("spectacularness", 100)
	Pair("plainkiller", "plainvictim", GLOCK18, "plain_ready")
}

public plain_ready()
{
	Kill()
	bench_wait_until("died", "plain_killed", 1.0)
}

public plain_killed()
{
	ASSERT_EQ(engfunc(EngFunc_FindEntityByString, -1, "classname", "ts_slowmotionpoint"), 0)
	bench_pass()
}

// --- the notices -----------------------------------------------------------------------------

// A headshot kill: "#TS_Headshot #TS_FrgFr <killer>!" (0x7a434).
public test_headshot_notice()
{
	Pair("headkiller", "headvictim", GLOCK18, "head_ready")
}

public head_ready()
{
	ASSERT(Face(g_P[0], g_P[1], 60.0))
	new Float:eye[3], Float:ofs[3]
	pev(g_P[1], pev_origin, eye)
	pev(g_P[1], pev_view_ofs, ofs)
	eye[2] += ofs[2]
	bench_puppet_look_at(g_P[0], eye)
	set_pev(g_P[1], pev_health, 1.0)
	Hold(g_P[0], IN_ATTACK, "head_fired")
}

public head_fired(id)
{
	bench_wait_until("died", "head_killed", 2.0)
}

public head_killed()
{
	ASSERT_EQ(g_DeathKiller, g_P[0])
	ASSERT(Notice("#TS_Headshot #TS_FrgFr headkiller!"))
	bench_pass()
}

// A kill with a knife slash: "#TS_KnifeKill #TS_FrgFr <killer>!" (0x7a4f5, fire type 3).
public test_knife_kill_notice()
{
	Pair("knifekiller", "knifevictim", KNIFE, "slash_ready")
}

public slash_ready()
{
	ASSERT(Face(g_P[0], g_P[1], 20.0))
	set_pev(g_P[1], pev_health, 1.0)
	Hold(g_P[0], IN_ATTACK, "slashed")
}

public slashed(id)
{
	bench_wait_until("died", "slash_killed", 2.0)
}

public slash_killed()
{
	ASSERT_EQ(g_DeathKiller, g_P[0])
	ASSERT(Notice("#TS_KnifeKill #TS_FrgFr knifekiller!"))
	bench_pass()
}

// With a katana: "#TS_KatanaKill #TS_FrgFr <killer>!" (0x7a531, fire type 10).
public test_katana_kill_notice()
{
	Pair("katanakiller", "katanavictim", KATANA, "katana_ready")
}

public katana_ready()
{
	ASSERT(Face(g_P[0], g_P[1], 20.0))
	set_pev(g_P[1], pev_health, 1.0)
	Hold(g_P[0], IN_ATTACK, "katana_swung")
}

public katana_swung(id)
{
	bench_wait_until("died", "katana_killed", 2.0)
}

public katana_killed()
{
	ASSERT_EQ(g_DeathKiller, g_P[0])
	ASSERT(Notice("#TS_KatanaKill #TS_FrgFr katanakiller!"))
	bench_pass()
}

// A kill with the gun's butt (cold cock): "#TS_Coldcock #TS_FrgFr <killer>!", the killer's name
// (0x7a57e).
public test_coldcock_notice_names_the_killer()
{
	Pair("basher", "bashed", DEAGLE, "bash_ready")
}

public bash_ready()
{
	ASSERT(Face(g_P[0], g_P[1], 20.0))
	set_pev(g_P[1], pev_health, 1.0)
	Hold(g_P[0], IN_CANCEL, "bashed_him")
}

public bashed_him(id)
{
	bench_wait_until("died", "bash_killed", 2.0)
}

public bash_killed()
{
	ASSERT_EQ(g_DeathKiller, g_P[0])
	ASSERT(Notice("#TS_Coldcock #TS_FrgFr basher!"))
	ASSERT_FALSE(Notice("#TS_Coldcock #TS_FrgFr bashed!"))
	bench_pass()
}

// --- his own weapon --------------------------------------------------------------------------

// The victim buys a Glock-18 (his loadout, given at his next spawn, records him as its owner) and
// drops it; the killer picks it up and kills him with it: "<killer> #TS_Killed <victim>
// #TS_OwnWeapon" (0x7ab45), and the log line carries " (victims_weapon)" (0x79f91).
public test_kill_with_the_victims_own_weapon()
{
	bench_set_timeout(60.0)
	Pair("ownkiller", "ownvictim", 0, "own_ready")
}

// His loadout is cleared as he goes to spectate after a death, so he picks it there.
public own_ready()
{
	user_kill(g_P[1], 1)
	bench_next("own_dead", 5.0)
}

public own_dead()
{
	bench_puppet_cmd(g_P[1], "tkw %d_0", GLOCK18)
	bench_puppet_spawn(g_P[1], "own_spawned", 20.0, "respawn")
}

public own_spawned(id)
{
	g_Weapon = GLOCK18
	bench_wait_until("holds_it", "own_bought", 3.0, id)
}

public own_bought(id)
{
	bench_next("own_drop", 1.0, id)
}

public own_drop(id)
{
	bench_puppet_cmd(id, "drop")
	bench_next("own_dropped", 1.5, id)
}

new g_Gun

public own_dropped(id)
{
	new gun = -1, found = 0
	while ((gun = engfunc(EngFunc_FindEntityByString, gun, "classname", "WorldGun")))
		if (pev(gun, pev_owner) == 0 || pev(gun, pev_owner) == id)
			found = gun
	ASSERT(found > 0)
	g_Gun = found
	// The killer stands on it holding use (a dropped gun is picked up with use), put back over it each
	// frame until he has it, in case it still moves.
	bench_puppet_input(g_P[0], IN_USE)
	bench_wait_until("on_the_gun", "own_picked", 5.0, g_P[0])
}

public bool:on_the_gun(killer)
{
	if (holds_it(killer))
		return true
	if (pev_valid(g_Gun))
	{
		new Float:origin[3]
		pev(g_Gun, pev_origin, origin)
		origin[2] += 40.0
		engfunc(EngFunc_SetOrigin, killer, origin)
		set_pev(killer, pev_velocity, Float:{0.0, 0.0, -100.0})
	}
	return false
}

public own_picked(killer)
{
	bench_puppet_input(killer, 0)
	bench_next("own_kill", 1.0)
}

public own_kill()
{
	g_DeathKiller = 0
	Kill()
	bench_wait_until("died", "own_killed", 1.0)
}

public own_killed()
{
	ASSERT_EQ(g_DeathKiller, g_P[0])
	ASSERT(Notice("ownkiller #TS_Killed ownvictim #TS_OwnWeapon"))
	ASSERT(contain(g_Logged, "with ^"glock-18^" (victims_weapon)") != -1)
	bench_pass()
}

// The server's own mode again, after the last kill test.
public test_back_to_the_servers_mode()
{
	new teamplay[4]
	get_localinfo("tsk_teamplay", teamplay, charsmax(teamplay))
	if (!teamplay[0])
	{
		bench_pass()
		return
	}
	set_localinfo("tsk_teamplay", "")
	set_cvar_num("mp_teamplay", 1)
	new map[32]
	get_mapname(map, charsmax(map))
	bench_change_map(map, "servers_mode_up")
}

public servers_mode_up()
{
	ASSERT_EQ(get_cvar_num("mp_teamplay"), 1)
	bench_pass()
}
