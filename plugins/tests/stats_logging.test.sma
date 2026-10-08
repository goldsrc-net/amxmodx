// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for ts/stats_logging.sma (Stats Logging): when a player leaves, their weapon stats, time
// played and average ping go to the server log. The test server does not log, so each test turns
// logging on ("log on" writes a new file under logsdir), closes it ("log off") to read it, then
// deletes it. Weapon stats come from a TSX custom weapon.
//

#include <amxmodx>
#include <fakemeta>
#include <tsx>
#include <amxxbench>

new g_Gun
new g_LogsDir[64]
new g_Before[64][32]
new g_BeforeCount
new g_NewLog[128]
new g_Puppet
new g_Other
new g_Name[32]
new g_Auth[44]
new g_UserId

public plugin_init()
{
	register_plugin("Stats Logging Tests", AMXX_VERSION_STR, "AMXX Dev Team")
	g_Gun = custom_weapon_add("loggun", 0, "loggun")
}

public bench_setup()
{
	get_cvar_string("logsdir", g_LogsDir, charsmax(g_LogsDir))
	if (!g_LogsDir[0])
		copy(g_LogsDir, charsmax(g_LogsDir), "logs")
	g_NewLog[0] = EOS
	g_Puppet = 0
	g_Other = 0
}

public bench_teardown()
{
	server_cmd("log off")
	server_exec()
	if (g_NewLog[0])
		delete_file(g_NewLog)
}

ListLogs()
{
	new name[32], dir = open_dir(g_LogsDir, name, charsmax(name))
	g_BeforeCount = 0
	if (!dir)
		return
	do
	{
		if (g_BeforeCount < sizeof(g_Before))
			copy(g_Before[g_BeforeCount++], charsmax(g_Before[]), name)
	}
	while (next_file(dir, name, charsmax(name)))
	close_dir(dir)
}

// The log file not there before ListLogs.
bool:FindNewLog()
{
	new name[32], dir = open_dir(g_LogsDir, name, charsmax(name))
	if (!dir)
		return false
	do
	{
		new bool:known = false
		for (new i = 0; i < g_BeforeCount && !known; i++)
			known = bool:equal(g_Before[i], name)
		if (!known && containi(name, ".log") != -1)
		{
			formatex(g_NewLog, charsmax(g_NewLog), "%s/%s", g_LogsDir, name)
			break
		}
	}
	while (next_file(dir, name, charsmax(name)))
	close_dir(dir)
	return g_NewLog[0] != EOS
}

StartLog()
{
	ListLogs()
	server_cmd("log on")
	server_exec()
}

// Whether the new log has a line containing text.
bool:Logged(const text[])
{
	new line[512], f = fopen(g_NewLog, "rt")
	if (!f)
		return false
	new bool:found = false
	while (!found && fgets(f, line, charsmax(line)))
		found = contain(line, text) != -1
	fclose(f)
	return found
}

bool:CheckLogged(const text[])
{
	if (Logged(text))
		return true
	bench_fail("no log line containing ^"%s^" in %s", text, g_NewLog)
	return false
}

public test_leaving_player_logs_stats()
{
	g_Puppet = bench_puppet("logged")
	g_Other = bench_puppet("target")
	ASSERT(g_Puppet > 0 && g_Other > 0)
	get_user_name(g_Puppet, g_Name, charsmax(g_Name))
	get_user_authid(g_Puppet, g_Auth, charsmax(g_Auth))
	g_UserId = get_user_userid(g_Puppet)

	// The Specialists spawns a joiner and sends him to spectate on his first frame (TS 3.0 and reTS);
	// TSX counts a hit as a kill only when the victim is not alive, so wait for that.
	bench_wait_until("target_down", "hits", 5.0)
}

public bool:target_down()
{
	return !is_user_alive(g_Other)
}

public hits()
{
	// Two shots, one hit in the head for 25. The target is spectating, so the hit kills.
	set_pev(g_Puppet, pev_team, 1)
	set_pev(g_Other, pev_team, 2)
	custom_weapon_shot(g_Gun, g_Puppet)
	custom_weapon_shot(g_Gun, g_Puppet)
	custom_weapon_dmg(g_Gun, g_Puppet, g_Other, 25, HIT_HEAD)

	// The ping is sampled every 19.5 seconds while the player is on.
	bench_next("leave", 20.0)
}

public leave()
{
	StartLog()
	server_cmd("kick #%d", g_UserId)
	server_exec()
	server_cmd("log off")
	server_exec()
	ASSERT(FindNewLog())

	new prefix[128]
	formatex(prefix, charsmax(prefix), "^"%s<%d><%s><", g_Name, g_UserId, g_Auth)
	ASSERT(CheckLogged(prefix))
	// The weapon's log name is the one custom_weapon_add was given.
	new logname[32], expected[256]
	xmod_get_wpnlogname(g_Gun, logname, charsmax(logname))
	ASSERT_STR_EQ(logname, "loggun")
	formatex(expected, charsmax(expected), "triggered ^"weaponstats^" (weapon ^"%s^") (shots ^"2^") (hits ^"1^") (kills ^"1^") (headshots ^"1^") (tks ^"0^") (damage ^"25^") (deaths ^"0^")", logname)
	ASSERT(CheckLogged(expected))
	formatex(expected, charsmax(expected), "triggered ^"weaponstats2^" (weapon ^"%s^") (head ^"1^") (chest ^"0^") (stomach ^"0^") (leftarm ^"0^") (rightarm ^"0^") (leftleg ^"0^") (rightleg ^"0^")", logname)
	ASSERT(CheckLogged(expected))
	ASSERT(CheckLogged("triggered ^"time^" (time ^"0:"))
	ASSERT(CheckLogged("triggered ^"latency^" (ping ^""))
	bench_pass()
}

public test_bots_are_not_logged()
{
	g_Puppet = bench_puppet("logbot", true)
	ASSERT(g_Puppet > 0)
	get_user_name(g_Puppet, g_Name, charsmax(g_Name))
	g_UserId = get_user_userid(g_Puppet)
	custom_weapon_shot(g_Gun, g_Puppet)

	StartLog()
	server_cmd("kick #%d", g_UserId)
	server_exec()
	server_cmd("log off")
	server_exec()
	ASSERT(FindNewLog())

	new prefix[64]
	formatex(prefix, charsmax(prefix), "^"%s<%d>", g_Name, g_UserId)
	// The game logs the bot leaving; TS Stats Logging adds nothing.
	ASSERT(CheckLogged(prefix))
	ASSERT_FALSE(Logged("triggered ^"weaponstats^""))
	ASSERT_FALSE(Logged("triggered ^"time^""))
	bench_pass()
}
