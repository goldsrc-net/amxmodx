// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for ts/stats.sma (TS Stats): the say commands, the stats menu, what a death shows the
// victim and everyone else, and the end of map stats. Every option is off until a test turns it
// on (the options are TS Stats' public variables, as Stats Configuration sets them); all are put
// back after each test.
//
// Damage and deaths reach TS Stats as TSX's client_damage and client_death forwards. TSX has two
// sources for them:
// - custom_weapon_dmg(), for a weapon registered with custom_weapon_add() (this file registers a
//   gun and a blade). The tests use it for hit places, headshots and team attacks.
// - The TSHealth message the game sends after a player is hurt, read with the victim's dmg_take
//   and dmg_inflictor. Grenades, the kill flags (stunt, sliding, double, specialist) and frag
//   counts only come this way. reTS sends TSHealth after it has already cleared dmg_take (stock
//   TS 3.0 sends it before), so TSX never sees a real hit. The "real damage" tests here hurt the
//   victim with Ham_TakeDamage and put dmg_take and dmg_inflictor back from a TSHealth message
//   hook just before TSX reads them, which is what stock TS hands TSX.
//

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <tsx>
#include <tsfun>
#include <amxxbench>

#define OPTIONS 21
#define CHECK(%0,%1)    if (!bench_check(bool:(%0), %1)) return

new const g_Vars[OPTIONS][] =
{
	"EndPlayer", "EndTop15", "SayStatsAll", "SayTop15", "SayRank", "SayStatsMe", "ShowAttackers",
	"ShowVictims", "ShowKiller", "KillerHp", "SayHP", "SayFF", "GrenadeKill", "GrenadeSuicide",
	"HeadShotKill", "HeadShotKillSound", "DoubleKill", "DoubleKillSound", "BulletDamage", "TAInfo",
	"FragInfo"
}

new g_Saved[OPTIONS]
new g_Gun
new g_Blade
new Float:g_FloodTime
new g_FriendlyFire
new Float:g_ChatTime
new bool:g_Intermission

new g_P[8]

// The TSHealth hook.
new g_ShimHook
new g_PendInflictor[MAX_PLAYERS + 1]
new Float:g_PendDamage[MAX_PLAYERS + 1]
new g_PendAttacker[MAX_PLAYERS + 1]
new g_PendStunt[MAX_PLAYERS + 1]
new g_PendFrags[MAX_PLAYERS + 1]
new g_Grenade

public plugin_init()
{
	register_plugin("TS Stats Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	g_Gun = custom_weapon_add("benchgun", 0, "benchgun")
	g_Blade = custom_weapon_add("benchblade", 1, "benchblade")
}

public bench_setup()
{
	for (new i = 0; i < OPTIONS; i++)
	{
		g_Saved[i] = get_xvar_num(get_xvar_id(g_Vars[i]))
		set_xvar_num(get_xvar_id(g_Vars[i]), 0)
	}
	// Anti Flood would answer the second "say" in a row instead of this plugin.
	g_FloodTime = get_cvar_float("amx_flood_time")
	set_cvar_float("amx_flood_time", 0.0)
	g_FriendlyFire = get_cvar_num("mp_friendlyfire")
	g_ChatTime = get_cvar_float("mp_chattime")
	g_Intermission = false
	g_Grenade = 0
	for (new i = 0; i <= MAX_PLAYERS; i++)
		g_PendDamage[i] = 0.0
	g_ShimHook = register_message(get_user_msgid("TSHealth"), "Shim_TSHealth")
}

public bench_teardown()
{
	for (new i = 0; i < OPTIONS; i++)
		set_xvar_num(get_xvar_id(g_Vars[i]), g_Saved[i])
	set_cvar_float("amx_flood_time", g_FloodTime)
	set_cvar_num("mp_friendlyfire", g_FriendlyFire)
	if (g_Intermission)
	{
		// The map change Nextmap scheduled (and anything else left on ID 0).
		remove_task(0, 1)
		set_cvar_float("mp_chattime", g_ChatTime)
	}
	unregister_message(get_user_msgid("TSHealth"), g_ShimHook)
	if (g_Grenade && pev_valid(g_Grenade))
		engfunc(EngFunc_RemoveEntity, g_Grenade)
}

On(const name[])
{
	set_xvar_num(get_xvar_id(name), 1)
}

// Creates count puppets named <prefix>1, <prefix>2, ...; false if one could not be made.
bool:Puppets(const prefix[], count)
{
	new name[32]
	for (new i = 0; i < count; i++)
	{
		formatex(name, charsmax(name), "%s%d", prefix, i + 1)
		g_P[i] = bench_puppet(name)
		if (!bench_check(g_P[i] > 0, "puppet created"))
			return false
	}
	return true
}

new g_Spawning

// Calls step once the first count puppets are alive.
SpawnFirst(count, const step[])
{
	g_Spawning = count
	bench_wait_until("first_alive", step, 30.0)
}

public first_alive()
{
	new bool:all = true
	for (new i = 0; i < g_Spawning; i++)
	{
		if (!is_user_alive(g_P[i]))
		{
			engclient_cmd(g_P[i], "respawn")
			all = false
		}
	}
	return all
}

// The Specialists kills a second after a kill (its ClientKill only arms a timer): wait for it.
public PuppetDead(id)
{
	return !is_user_alive(id)
}

// Every MOTD text sent to id this test, joined.
Motd(id, text[], len)
{
	new BenchMsg:msg = BenchMsg:0, part[256]
	text[0] = EOS
	while ((msg = bench_msg_next(id, msg, "MOTD")) != BenchMsg:0)
	{
		bench_msg_string(msg, 1, part, charsmax(part))
		add(text, len, part)
	}
}

new g_Text[2048]

bool:MotdHas(id, const part[])
{
	Motd(id, g_Text, charsmax(g_Text))
	if (contain(g_Text, part) != -1)
		return true
	bench_fail("MOTD to %d ^"%s^" has no ^"%s^"", id, g_Text, part)
	return false
}

// The newest HUD message to id containing text, or 0.
BenchMsg:Hud(id, const text[])
{
	return bench_msg_last(id, "svc_temp_entity", text)
}

bool:HudColour(BenchMsg:msg, r, g, b)
{
	return msg != BenchMsg:0 && bench_msg_int(msg, 5) == r && bench_msg_int(msg, 6) == g && bench_msg_int(msg, 7) == b
}

Name(id)
{
	new name[32]
	get_user_name(id, name, charsmax(name))
	return name
}

// ---------------------------------------------------------------------------------------------
// The TSHealth hook. Runs before TSX reads the message (TSX reads it after it is sent).

public Shim_TSHealth(msgid, dest, id)
{
	if (id < 1 || id > MAX_PLAYERS || g_PendDamage[id] <= 0.0)
		return PLUGIN_CONTINUE
	set_pev(id, pev_dmg_take, g_PendDamage[id])
	set_pev(id, pev_dmg_inflictor, g_PendInflictor[id])
	new attacker = g_PendAttacker[id]
	if (g_PendStunt[id])
		set_pev(attacker, pev_iuser4, g_PendStunt[id])
	if (g_PendFrags[id])
	{
		new Float:frags
		pev(attacker, pev_frags, frags)
		set_pev(attacker, pev_frags, frags + float(g_PendFrags[id]))
	}
	g_PendDamage[id] = 0.0
	return PLUGIN_CONTINUE
}

// Hurts victim the game's way. stunt is the attacker's TS move state (pev_iuser4) TSX should see:
// 20 is a stunt, 36 a slide. frags adds to the attacker's frags as the game awards, so TSX finds
// a different count than it expects (what it reads as a slide when the move state says one).
RealDamage(victim, inflictor, attacker, Float:damage, stunt = 0, frags = 0)
{
	g_PendInflictor[victim] = inflictor
	g_PendDamage[victim] = damage
	g_PendAttacker[victim] = attacker
	g_PendStunt[victim] = stunt
	g_PendFrags[victim] = frags
	ExecuteHam(Ham_TakeDamage, victim, inflictor, attacker, damage, DMG_BULLET)
}

// ---------------------------------------------------------------------------------------------
// Say commands

public test_options_off()
{
	if (!Puppets("asker", 1))
		return
	new id = g_P[0]
	bench_puppet_say(id, "/hp")
	bench_puppet_say(id, "/stats")
	bench_puppet_say(id, "/statsme")
	bench_puppet_say(id, "/top15")
	bench_puppet_say(id, "/rank")
	bench_puppet_say(id, "/ff")
	ASSERT_EQ(bench_msg_count(id, "TextMsg", "Server has disabled that option"), 6)
	ASSERT_EQ(bench_msg_count(id, "MOTD", "Kills: "), 0)
	ASSERT_EQ(bench_msg_count(id, "ServerName", "Top 15"), 0)
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), 0)
	bench_pass()
}

public test_say_ff()
{
	if (!Puppets("ffasker", 1))
		return
	On("SayFF")
	set_cvar_num("mp_friendlyfire", 0)
	bench_puppet_say(g_P[0], "/ff")
	ASSERT_MSG(g_P[0], "TextMsg", "Friendly fire:  OFF")
	set_cvar_num("mp_friendlyfire", 1)
	bench_puppet_say(g_P[0], "/ff")
	ASSERT_MSG(g_P[0], "TextMsg", "Friendly fire:  ON")
	bench_pass()
}

public test_statsme_lists_weapons()
{
	if (!Puppets("shooter", 2))
		return
	SpawnFirst(2, "statsme_spawned")
}

public statsme_spawned()
{
	new a = g_P[0], b = g_P[1]
	On("SayStatsMe")
	set_pev(a, pev_team, 1)
	set_pev(b, pev_team, 2)
	custom_weapon_shot(g_Gun, a)
	custom_weapon_shot(g_Gun, a)
	custom_weapon_dmg(g_Gun, a, b, 30, HIT_CHEST)
	custom_weapon_shot(g_Blade, a)
	custom_weapon_dmg(g_Blade, a, b, 10, HIT_STOMACH)

	bench_puppet_say(a, "/statsme")
	if (!MotdHas(a, "Kills: 0^nDeaths: 0^nTKs: 0^nDamage: 40^nHits: 2^nShots: 3")) return
	if (!MotdHas(a, "benchgun shots: 2  hits: 1  damage: 30  kills: 0  deaths: 0")) return
	// A melee weapon has no shots to count.
	if (!MotdHas(a, "benchblade shots: -1  hits: 1  damage: 10  kills: 0  deaths: 0")) return
	ASSERT_MSG(a, "ServerName", Name(a))
	bench_pass()
}

public test_rank()
{
	if (!Puppets("ranked", 2))
		return
	SpawnFirst(2, "rank_spawned")
}

public rank_spawned()
{
	new a = g_P[0], b = g_P[1]
	On("SayRank")
	set_pev(a, pev_team, 1)
	set_pev(b, pev_team, 2)
	custom_weapon_dmg(g_Gun, a, b, 15, HIT_RIGHTLEG)
	bench_puppet_say(a, "/rank")
	if (!MotdHas(a, "Hits:^nhead: 0^nchest: 0^nstomach: 0^nleft arm: 0^nright arm: 0^nleft leg: 0^nright leg: ")) return
	new expected[64]
	formatex(expected, charsmax(expected), " of %d", get_statsnum())
	if (!MotdHas(a, "Your rank is ")) return
	if (!MotdHas(a, expected)) return
	bench_pass()
}

// The rank is kept by name, and TSX saves it to tsstats.dat at every map change, so "<top>1" and
// others may already have stats from an earlier test or run. The test gives "<top>1" enough kills
// to pass the top score, and expects its earlier stats plus those.
new g_TopBefore[STATSX_MAX_STATS]
new g_TopKills

Score(const stats[STATSX_MAX_STATS])
{
	return stats[STATSX_KILLS] - stats[STATSX_DEATHS] - stats[STATSX_TEAMKILLS]
}

public test_top15()
{
	// TS Stats writes "<" and ">" in names as "[" and "]" (the MOTD is HTML on some clients).
	new top[STATSX_MAX_STATS], bodyhits[MAX_BODYHITS], name[32]
	RankedStats("<top>1", g_TopBefore)
	g_TopKills = 2
	if (get_statsnum() > 0)
	{
		get_stats(0, top, bodyhits, name, charsmax(name))
		g_TopKills = max(2, Score(top) - Score(g_TopBefore) + 1)
	}
	if (!Puppets("<top>", 3))
		return
	// The Specialists 3.0 spawns a player who has just joined and puts him into spectate on his
	// first frame (CTSGameRules::InitHUD). Until then a hit is no kill.
	bench_wait_until("top15_down", "top15_hit", 5.0)
}

public top15_down()
{
	return !is_user_alive(g_P[0]) && !is_user_alive(g_P[1])
}

public top15_hit()
{
	new a = g_P[0], b = g_P[1]
	On("SayTop15")
	set_pev(a, pev_team, 1)
	set_pev(b, pev_team, 2)
	// TSX adds a player's stats to the rank when they leave.
	for (new i = 0; i < g_TopKills; i++)
		custom_weapon_dmg(g_Gun, a, b, 100, HIT_CHEST)
	server_cmd("kick #%d", get_user_userid(a))
	server_cmd("kick #%d", get_user_userid(b))
	server_exec()
	bench_next("top15_asked", 0.1)
}

// The ranked stats of name, or zeros if it has no entry.
RankedStats(const name[], stats[STATSX_MAX_STATS])
{
	new bodyhits[MAX_BODYHITS], ranked[32], next = 0, i
	do
	{
		next = get_stats(i = next, stats, bodyhits, ranked, charsmax(ranked))
		if (equal(ranked, name))
			return
	}
	while (next)
	for (i = 0; i < STATSX_MAX_STATS; i++)
		stats[i] = 0
}

public top15_asked()
{
	new id = g_P[2], line[128], b[STATSX_MAX_STATS]
	b = g_TopBefore
	bench_puppet_say(id, "/top15")
	ASSERT_MSG(id, "ServerName", "Top 15")
	if (!MotdHas(id, "#   nick                           kills/deaths    TKs      hits/shots/headshots^n")) return
	formatex(line, charsmax(line), " 1.  %-28.27s    %d/%d          %d            %d/%d/%d^n", "[top]1",
		b[STATSX_KILLS] + g_TopKills, b[STATSX_DEATHS], b[STATSX_TEAMKILLS], b[STATSX_HITS] + g_TopKills,
		b[STATSX_SHOTS], b[STATSX_HEADSHOTS])
	if (!MotdHas(id, line)) return
	ASSERT_EQ(bench_msg_count(id, "MOTD", "<top>"), 0)
	bench_pass()
}

public test_hp_without_killer()
{
	if (!Puppets("alive", 1))
		return
	On("SayHP")
	bench_puppet_say(g_P[0], "/hp")
	ASSERT_MSG(g_P[0], "TextMsg", "You have no killer...")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// The stats menu: seven players a page, 8 switches stats/rank, 9 More, 0 Back or Exit.

MenuText(id, text[], len)
{
	new BenchMsg:msg = BenchMsg:0, part[256], bool:more = false
	text[0] = EOS
	while ((msg = bench_msg_next(id, msg, "ShowMenu")) != BenchMsg:0)
	{
		if (!more)
			text[0] = EOS
		bench_msg_string(msg, 3, part, charsmax(part))
		add(text, len, part)
		more = bench_msg_int(msg, 2) != 0
	}
}

bool:MenuHas(id, const part[])
{
	new text[512]
	MenuText(id, text, charsmax(text))
	if (contain(text, part) != -1)
		return true
	bench_fail("menu ^"%s^" has no ^"%s^"", text, part)
	return false
}

MenuKeys(id)
{
	new BenchMsg:msg = bench_msg_last(id, "ShowMenu")
	return msg == BenchMsg:0 ? -1 : bench_msg_int(msg, 0)
}

// The name on a line of the stats menu.
MenuName(id, number, name[], len)
{
	new text[512], item[8], pos
	MenuText(id, text, charsmax(text))
	formatex(item, charsmax(item), "%d. ", number)
	name[0] = EOS
	if ((pos = contain(text, item)) != -1)
		copyc(name, len, text[pos + strlen(item)], '^n')
}

public test_stats_menu()
{
	// Eight players: two pages.
	if (!Puppets("menu", 8))
		return
	new id = g_P[0], name[32]
	On("SayStatsAll")
	bench_puppet_say(id, "/stats")
	if (!MenuHas(id, "Server Stats 1/2")) return
	if (!MenuHas(id, "8. Show stats")) return
	if (!MenuHas(id, "9. More...^n0. Exit")) return
	ASSERT_EQ(MenuKeys(id), 0x3FF)

	// A player: their stats, then the menu again.
	MenuName(id, 2, name, charsmax(name))
	bench_puppet_cmd(id, "menuselect 2")
	ASSERT_MSG(id, "ServerName", name)
	Motd(id, g_Text, charsmax(g_Text))
	ASSERT(contain(g_Text, "Kills: ") != -1)
	ASSERT_EQ(bench_msg_count(id, "ShowMenu", "Server Stats 1/2"), 2)

	// 8: ranks instead.
	bench_puppet_cmd(id, "menuselect 8")
	if (!MenuHas(id, "8. Show rank")) return
	bench_puppet_cmd(id, "menuselect 2")
	if (!MotdHas(id, "His rank is ")) return

	// Page 2 has the last player and Back.
	bench_puppet_cmd(id, "menuselect 9")
	if (!MenuHas(id, "Server Stats 2/2")) return
	if (!MenuHas(id, "^n0. Back")) return
	ASSERT_EQ(MenuKeys(id), (1<<9)|(1<<7)|(1<<0))
	bench_puppet_cmd(id, "menuselect 10")
	if (!MenuHas(id, "Server Stats 1/2")) return

	// Exit closes it.
	new count = bench_msg_count(id, "ShowMenu")
	bench_puppet_cmd(id, "menuselect 10")
	ASSERT_EQ(bench_msg_count(id, "ShowMenu"), count)
	bench_pass()
}

new g_MenuUser

public test_stats_menu_page_gone()
{
	if (!Puppets("pager", 8))
		return
	g_MenuUser = g_P[0]
	On("SayStatsAll")
	bench_puppet_say(g_MenuUser, "/stats")
	bench_puppet_cmd(g_MenuUser, "menuselect 9")
	if (!MenuHas(g_MenuUser, "Server Stats 2/2")) return
	// The player on page 2 leaves; the next redraw of page 2 starts over at page 1.
	server_cmd("kick #%d", get_user_userid(g_P[7]))
	server_exec()
	bench_next("page_gone", 0.2)
}

public page_gone()
{
	bench_puppet_cmd(g_MenuUser, "menuselect 8")
	if (!MenuHas(g_MenuUser, "Server Stats 1/1")) return
	if (!MenuHas(g_MenuUser, "^n0. Exit")) return
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Deaths (custom weapons)

new g_K, g_V, g_X, g_C

public test_death_shows_who_and_how()
{
	// Killer, victim, the victim's own victim and another attacker.
	if (!Puppets("d", 4))
		return
	g_K = g_P[0]
	g_V = g_P[1]
	g_X = g_P[2]
	g_C = g_P[3]
	SpawnFirst(2, "death_spawned")
}

// TSX clears a player's stats a quarter of a second after the spawn's ResetHUD; the hits come after
// that, or the clear lands while the test waits for the kill.
public death_spawned()
{
	bench_next("death_ready", 0.5)
}

public death_ready()
{
	for (new i = 0; i < 4; i++)
		set_pev(g_P[i], pev_team, i + 1)
	On("ShowKiller")
	On("ShowVictims")
	On("ShowAttackers")
	On("KillerHp")
	On("SayHP")
	On("BulletDamage")
	On("HeadShotKill")
	On("HeadShotKillSound")
	On("FragInfo")

	// The victim hits the killer and kills X (not alive: any hit kills), C hits the victim.
	custom_weapon_dmg(g_Gun, g_V, g_K, 5, HIT_LEFTARM)
	custom_weapon_dmg(g_Gun, g_V, g_X, 50, HIT_CHEST)
	custom_weapon_dmg(g_Blade, g_C, g_V, 7, HIT_STOMACH)

	// The damage shows as a number to both sides.
	CHECK(HudColour(Hud(g_V, "5"), 0, 100, 200), "death check 1")
	CHECK(HudColour(Hud(g_K, "5"), 200, 0, 0), "death check 2")

	// The killer's headshot.
	user_silentkill(g_V)
	bench_wait_until("PuppetDead", "death_headshot", 5.0, g_V)
}

public death_headshot()
{
	custom_weapon_dmg(g_Gun, g_K, g_V, 80, HIT_HEAD)

	new expected[256]
	formatex(expected, charsmax(expected), "%s killed you with benchgun^nfrom distance of ", Name(g_K))
	CHECK(Hud(g_V, expected) != BenchMsg:0, "death check 3")
	formatex(expected, charsmax(expected), "He did 80 damage to you with 1 hit(s)^nand still has %dhp.^nYou did 5 damage to him with 1 hit(s).^nHe hits you in:^nhead: 1^n", get_user_health(g_K))
	CHECK(Hud(g_V, expected) != BenchMsg:0, "death check 4")

	// Listed by player index: the killer was made first.
	formatex(expected, charsmax(expected), "Victims:^n%s -- 5 dmg / 1 hit(s)^n%s -- 50 dmg / 1 hit(s) -- benchgun^n", Name(g_K), Name(g_X))
	CHECK(Hud(g_V, expected) != BenchMsg:0, "death check 5")
	formatex(expected, charsmax(expected), "Attackers:^n%s -- 80 dmg / 1 hit(s) -- benchgun^n%s -- 7 dmg / 1 hit(s)^n", Name(g_K), Name(g_C))
	CHECK(Hud(g_V, expected) != BenchMsg:0, "death check 6")

	formatex(expected, charsmax(expected), "%s still has %dhp", Name(g_K), get_user_health(g_K))
	ASSERT_MSG(g_V, "TextMsg", expected)
	CHECK(Hud(g_V, expected) != BenchMsg:0, "death check 7")

	// Everyone not just killed sees the headshot; the victim and X do not.
	CHECK(HudColour(Hud(g_K, Name(g_V)), 100, 100, 255), "death check 8")
	CHECK(HudColour(Hud(g_C, Name(g_V)), 100, 100, 255), "death check 9")
	ASSERT_FALSE(HudColour(Hud(g_X, Name(g_V)), 100, 100, 255))

	// Frag info for the killer.
	CHECK(Hud(g_K, "LastKill: ") != BenchMsg:0, "death check 10")
	// The headshot sound, to everyone.
	CHECK(bench_msg_last(g_C, "stufftext", "spk misc/headshot") != BenchMsg:0, "headshot sound")

	// "say /hp" repeats it in chat.
	bench_puppet_say(g_V, "/hp")
	formatex(expected, charsmax(expected), "%s killed you with benchgun from distance of ", Name(g_K))
	ASSERT_MSG(g_V, "TextMsg", expected)
	formatex(expected, charsmax(expected), "He did 80 damage to you with 1 hit(s) and still had %dhp", get_user_health(g_K))
	ASSERT_MSG(g_V, "TextMsg", expected)
	ASSERT_MSG(g_V, "TextMsg", "You did 5 damage to him with 1 hit(s)")
	formatex(expected, charsmax(expected), "You hit %s in: left arm: 1 ", Name(g_K))
	ASSERT_MSG(g_V, "TextMsg", expected)

	// The HUD comes back when the game resets the dead player's HUD.
	bench_wait_until("shown_again", "victim_respawns", 10.0)
}

public shown_again()
{
	new expected[64]
	formatex(expected, charsmax(expected), "%s killed you with", Name(g_K))
	return bench_msg_count(g_V, "svc_temp_entity", expected) >= 2
}

public victim_respawns()
{
	g_Spawning = 0
	bench_puppet_spawn(g_V, "victim_alive", 30.0, "respawn")
}

public victim_alive()
{
	// Alive again: no killer to report.
	bench_puppet_say(g_V, "/hp")
	ASSERT_MSG(g_V, "TextMsg", "You have no killer...")
	bench_pass()
}

public test_no_killer_info_when_off()
{
	if (!Puppets("quiet", 2))
		return
	SpawnFirst(1, "quiet_spawned")
}

public quiet_spawned()
{
	new k = g_P[0], v = g_P[1]
	set_pev(k, pev_team, 1)
	set_pev(v, pev_team, 2)
	On("SayHP")
	// v is not alive: the hit kills.
	custom_weapon_dmg(g_Gun, k, v, 50, HIT_HEAD)
	ASSERT_EQ(bench_msg_count(v, "svc_temp_entity", "killed you"), 0)
	bench_puppet_say(v, "/hp")
	new expected[64]
	formatex(expected, charsmax(expected), "%s killed you with benchgun", Name(k))
	ASSERT_MSG(v, "TextMsg", expected)
	// No hits on the killer: no "You hit" line.
	ASSERT_EQ(bench_msg_count(v, "TextMsg", "You hit"), 0)
	bench_pass()
}

public test_melee_headshot_not_announced()
{
	if (!Puppets("blade", 3))
		return
	SpawnFirst(1, "blade_spawned")
}

public blade_spawned()
{
	new k = g_P[0], v = g_P[1], w = g_P[2]
	set_pev(k, pev_team, 1)
	set_pev(v, pev_team, 2)
	set_pev(w, pev_team, 3)
	On("HeadShotKill")
	custom_weapon_dmg(g_Blade, k, v, 50, HIT_HEAD)
	ASSERT_EQ(bench_msg_count(w, "svc_temp_entity", Name(v)), 0)
	bench_pass()
}

public test_own_damage_and_death_show_nothing()
{
	if (!Puppets("self", 1))
		return
	SpawnFirst(1, "self_spawned")
}

public self_spawned()
{
	new a = g_P[0]
	On("BulletDamage")
	On("ShowKiller")
	custom_weapon_dmg(g_Gun, a, a, 10, HIT_CHEST)
	ASSERT_EQ(bench_msg_count(a, "svc_temp_entity", "10"), 0)
	user_silentkill(a)
	bench_wait_until("PuppetDead", "self_dead", 5.0, a)
}

public self_dead(a)
{
	custom_weapon_dmg(g_Gun, a, a, 10, HIT_CHEST)
	ASSERT_EQ(bench_msg_count(a, "svc_temp_entity", "killed you"), 0)
	bench_pass()
}

public test_team_attack_and_team_kill()
{
	if (!Puppets("mate", 2))
		return
	SpawnFirst(2, "mates_spawned")
}

public mates_spawned()
{
	new a = g_P[0], b = g_P[1], expected[64]
	// Same team. The Specialists 3.0 never writes a player's pev_team, so a slot keeps what an
	// earlier test gave it.
	set_pev(a, pev_team, 1)
	set_pev(b, pev_team, 1)
	On("TAInfo")
	On("BulletDamage")
	custom_weapon_dmg(g_Gun, a, b, 10, HIT_CHEST)
	formatex(expected, charsmax(expected), "%s attacked a teammate", Name(a))
	ASSERT_MSG(b, "TextMsg", expected)
	// No damage number for a team attack.
	ASSERT_EQ(bench_msg_count(a, "svc_temp_entity", "10"), 0)

	user_silentkill(b)
	bench_wait_until("PuppetDead", "mate_dead", 5.0, b)
}

public mate_dead(b)
{
	new a = g_P[0], expected[64]
	custom_weapon_dmg(g_Gun, a, b, 10, HIT_CHEST)
	formatex(expected, charsmax(expected), "%s killed a teammate !", Name(a))
	ASSERT_MSG(b, "TextMsg", expected)
	// A hit on a dead teammate is no team attack message.
	formatex(expected, charsmax(expected), "%s attacked a teammate", Name(a))
	ASSERT_EQ(bench_msg_count(b, "TextMsg", expected), 1)
	bench_pass()
}

public test_team_attack_quiet_when_off()
{
	if (!Puppets("mute", 2))
		return
	SpawnFirst(2, "mute_spawned")
}

public mute_spawned()
{
	new a = g_P[0], b = g_P[1]
	set_pev(a, pev_team, 1)
	set_pev(b, pev_team, 1)
	custom_weapon_dmg(g_Gun, a, b, 10, HIT_CHEST)
	user_silentkill(b)
	bench_wait_until("PuppetDead", "mute_dead", 5.0, b)
}

public mute_dead(b)
{
	custom_weapon_dmg(g_Gun, g_P[0], b, 10, HIT_CHEST)
	ASSERT_EQ(bench_msg_count(b, "TextMsg", "teammate"), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// Deaths the game reports (see the top of the file)

public test_grenade_kill_and_suicide()
{
	// Thrower, victim, bystander.
	if (!Puppets("nade", 3))
		return
	SpawnFirst(3, "nade_spawned")
}

public nade_spawned()
{
	On("GrenadeKill")
	On("GrenadeSuicide")
	g_Grenade = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"))
	set_pev(g_Grenade, pev_classname, "grenade")
	set_pev(g_Grenade, pev_owner, g_P[0])
	RealDamage(g_P[1], g_Grenade, g_P[0], 500.0)
	bench_next("nade_killed", 0.1)
}

public nade_killed()
{
	new BenchMsg:msg = Hud(g_P[2], Name(g_P[1]))
	ASSERT(HudColour(msg, 255, 100, 100))
	new text[128]
	bench_msg_string(msg, bench_msg_args(msg) - 1, text, charsmax(text))
	ASSERT(contain(text, Name(g_P[0])) != -1)

	// Now the thrower on himself.
	RealDamage(g_P[0], g_Grenade, g_P[0], 500.0)
	bench_next("nade_suicide", 0.1)
}

public nade_suicide()
{
	new BenchMsg:msg = Hud(g_P[2], Name(g_P[0]))
	ASSERT(HudColour(msg, 255, 100, 100))
	new text[128]
	bench_msg_string(msg, bench_msg_args(msg) - 1, text, charsmax(text))
	ASSERT(contain(text, "grenade") != -1 || contain(text, "explodes!") != -1)
	bench_pass()
}

new g_Kill
new g_Enemies[8]
new g_EnemyCount

// In teamplay with mp_friendlyfire off the killer only hurts the other team (the puppets alternate
// between the two teams as they join); in deathmatch, where nobody has a team, he hurts everyone.
public test_kill_flags()
{
	if (!Puppets("kf", 8))
		return
	SpawnFirst(8, "kf_spawned")
}

public kf_spawned()
{
	new k = g_P[0], team[16], other[16]
	get_user_team(k, team, charsmax(team))
	g_EnemyCount = 0
	for (new i = 1; i < 8; i++)
	{
		get_user_team(g_P[i], other, charsmax(other))
		if (!team[0] || !equal(team, other))
			g_Enemies[g_EnemyCount++] = g_P[i]
	}
	CHECK(g_EnemyCount >= 2, "two puppets to kill")
	On("FragInfo")
	On("DoubleKill")
	On("DoubleKillSound")
	g_Kill = 0
	bench_next("kf_next", 0.0)
}

// One kill a frame, so all but the first of a round are double kills (within a second).
public kf_next()
{
	new k = g_P[0], victim = 0
	for (new i = 0; i < g_EnemyCount && !victim; i++)
		if (is_user_alive(g_Enemies[i]))
			victim = g_Enemies[i]
	if (!victim)
	{
		// Everyone down: wait for them to come back (the killer stays alive).
		bench_wait_until("enemies_alive", "kf_next", 30.0)
		return
	}
	g_Kill++
	if (g_Kill == 1)
		RealDamage(victim, k, k, 500.0, 20)		// a stunt
	else if (g_Kill == 3)
		RealDamage(victim, k, k, 500.0, 36, 1)	// a slide
	else
		RealDamage(victim, k, k, 500.0)
	if (g_Kill == 3)
		bench_next("kf_flags", 0.1)
	else if (g_Kill == 10)
		bench_next("kf_specialist", 0.1)
	else
		bench_next("kf_next", 0.0)
}

public enemies_alive()
{
	new bool:all = true
	for (new i = 0; i < g_EnemyCount; i++)
	{
		if (!is_user_alive(g_Enemies[i]))
		{
			engclient_cmd(g_Enemies[i], "respawn")
			all = false
		}
	}
	return all
}

public kf_flags()
{
	new k = g_P[0], expected[64]
	CHECK(is_user_alive(k), "killer alive")
	ASSERT_EQ(ts_getkillingstreak(k), 3)
	ASSERT(Hud(k, "[ stunt ]") != BenchMsg:0)
	ASSERT(Hud(k, " sliding ") != BenchMsg:0)
	ASSERT(Hud(k, " double ") != BenchMsg:0)
	ASSERT_MSG(k, "stufftext", "spk misc/doublekill")
	formatex(expected, charsmax(expected), "Wow! %s made a double kill !!!", Name(k))
	ASSERT(Hud(k, expected) != BenchMsg:0)
	bench_next("kf_next", 0.0)
}

public kf_specialist()
{
	new k = g_P[0], killer = 0
	// Ten in a row: a specialist.
	ASSERT_EQ(ts_getkillingstreak(k), 10)
	ASSERT(Hud(k, " spec ") != BenchMsg:0)
	// Killed by the other team.
	for (new i = 0; i < g_EnemyCount && !killer; i++)
		if (is_user_alive(g_Enemies[i]))
			killer = g_Enemies[i]
	if (!killer)
	{
		bench_wait_until("enemies_alive", "kf_specialist", 30.0)
		return
	}
	g_P[1] = killer
	RealDamage(k, killer, killer, 500.0)
	bench_next("kf_killed_specialist", 0.1)
}

public kf_killed_specialist()
{
	ASSERT(Hud(g_P[1], " kspec ") != BenchMsg:0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// End of map. Nextmap schedules the map change on the same intermission message: mp_chattime is
// made long first and the change removed afterwards.

Intermission()
{
	g_Intermission = true
	set_cvar_float("mp_chattime", 100000.0)
	emessage_begin(MSG_ALL, SVC_INTERMISSION)
	emessage_end()
}

public test_end_of_map_player_stats()
{
	ASSERT_FALSE(task_exists(0, 1))
	if (!Puppets("ender", 2))
		return
	On("EndPlayer")
	On("EndTop15")
	Intermission()
	bench_next("end_stats", 1.2)
}

public end_stats()
{
	// Each player gets their own stats (EndPlayer wins over EndTop15).
	for (new i = 0; i < 2; i++)
	{
		ASSERT_MSG(g_P[i], "ServerName", Name(g_P[i]))
		if (!MotdHas(g_P[i], "Kills: ")) return
	}
	ASSERT_EQ(bench_msg_count(g_P[0], "ServerName", "Top 15"), 0)
	bench_pass()
}

public test_end_of_map_top15()
{
	ASSERT_FALSE(task_exists(0, 1))
	if (!Puppets("topender", 2))
		return
	On("EndTop15")
	Intermission()
	bench_next("end_top15", 1.2)
}

public end_top15()
{
	for (new i = 0; i < 2; i++)
	{
		ASSERT_MSG(g_P[i], "ServerName", "Top 15")
		if (!MotdHas(g_P[i], "#   nick")) return
	}
	bench_pass()
}

public test_end_of_map_nothing_when_off()
{
	ASSERT_FALSE(task_exists(0, 1))
	if (!Puppets("noender", 1))
		return
	Intermission()
	bench_next("end_nothing", 1.2)
}

public end_nothing()
{
	ASSERT_EQ(bench_msg_count(g_P[0], "MOTD", "Kills: "), 0)
	ASSERT_EQ(bench_msg_count(g_P[0], "ServerName", "Top 15"), 0)
	bench_pass()
}
