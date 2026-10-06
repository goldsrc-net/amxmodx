// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/logtest.sma. The original waited for the game to log a round start.
// These tests have a puppet join, which the game logs ("<player>" entered the game) through the
// engine table Metamod hooks. A plugin's own log_message() is no use here: plugins call the engine
// directly, so their log lines never reach plugin_log or logevents.
//

#include <amxmodx>
#include <amxxbench>

#define JOIN_LOG "entered the game"

new g_BlockLog
new bool:g_Watching
new g_LogEvents
new g_LastLog[256]
new bool:g_JoinSeen
new g_Joins

public plugin_init()
{
	register_plugin("Log Tester", "1.0", "BAILOPAN")
	register_srvcmd("log_setblock", "Command_LogSetBlock")
}

public bench_teardown()
{
	g_Watching = false
	g_BlockLog = false
}

public event_entered()
{
	g_Joins++
}

public Command_LogSetBlock()
{
	if (read_argc() < 2)
	{
		server_print("Specify 1 or 0.")
		return PLUGIN_HANDLED
	}

	new temp[12]
	read_argv(1, temp, 11)

	g_BlockLog = str_to_num(temp) ? true : false

	return PLUGIN_HANDLED
}

public plugin_log()
{
	if (g_Watching)
	{
		g_LogEvents++
		read_logdata(g_LastLog, charsmax(g_LastLog))
		if (contain(g_LastLog, JOIN_LOG) != -1)
			g_JoinSeen = true
	}

	return g_BlockLog ? PLUGIN_HANDLED : PLUGIN_CONTINUE
}

// Has a puppet join and calls step once the game has logged it.
JoinAndWatch(const step[])
{
	g_LogEvents = 0
	g_LastLog[0] = 0
	g_JoinSeen = false
	g_Watching = true
	bench_puppet("logger")
	bench_wait_until("join_logged", step, 5.0)
}

// The game may log more after the join (a renamed duplicate name, a team), so this does not look
// at the last line only.
public join_logged()
{
	return g_JoinSeen
}

public test_plugin_log()
{
	server_cmd("log_setblock 0")
	server_exec()
	ASSERT_FALSE(g_BlockLog)

	JoinAndWatch("plugin_log_seen")
}

public plugin_log_seen()
{
	g_Watching = false
	ASSERT(g_LogEvents >= 1)
	bench_pass()
}

public test_plugin_log_blocking()
{
	server_cmd("log_setblock 1")
	server_exec()
	ASSERT_TRUE(g_BlockLog)

	// a blocked line still reaches plugin_log; blocking keeps it out of the log
	JoinAndWatch("plugin_log_blocked_seen")
}

public plugin_log_blocked_seen()
{
	g_Watching = false
	ASSERT(g_LogEvents >= 1)

	server_cmd("log_setblock 0")
	server_exec()
	ASSERT_FALSE(g_BlockLog)
	bench_pass()
}

new g_JoinEvent

public test_logevent()
{
	g_Joins = 0
	g_JoinEvent = register_logevent("event_entered", 2, "1=entered the game")
	JoinAndWatch("logevent_seen")
}

public logevent_seen()
{
	g_Watching = false
	disable_logevent(g_JoinEvent)
	ASSERT_EQ(g_Joins, 1)

	// once disabled, the event no longer fires
	JoinAndWatch("logevent_disabled")
}

public logevent_disabled()
{
	g_Watching = false
	ASSERT_EQ(g_Joins, 1)
	bench_pass()
}
