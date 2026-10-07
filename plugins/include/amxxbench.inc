// amxxbench: tests for AMX Mod X plugins, run inside a real server.
//
// Tests live apart from the plugins they test, in plugins/tests/<name>.test.sma (compiled to
// <name>.test.amxx). Start the server with "-bench run" or "-bench coverage" (optionally
// ":filter"), or set AMXXBENCH=run|coverage[:filter]; the module then loads every
// plugins/tests/*.test.amxx after the configured plugins, runs the tests once the map is up, prints
// a Jest-style report and exits with 0 (all passed) or 1. "bench run [filter]" at the server
// console runs them again on a live server.
//
// Any public named test_<something> in a test plugin is a test. The module calls it, then follows
// the steps it schedules with bench_next() or bench_wait_until(). A test passes by calling
// bench_pass(). A failed check, bench_fail() or a run time error fails it, and so does a test that
// leaves nothing scheduled without passing or whose step does not arrive in time (bench_timeout).

#if defined _amxxbench_included
	#endinput
#endif
#define _amxxbench_included

#include <amxmodx>
#include <fakemeta>

#pragma reqlib amxxbench
#if !defined AMXMODX_NOAUTOLOAD
	#pragma loadlib amxxbench
#endif

// Optional, per plugin: bench_setup() runs before each of the plugin's tests (a failure there fails
// the test without running it), bench_teardown() after each one, while its puppets still exist (a
// failure there turns a pass into a FAIL). Neither can schedule steps.
forward bench_setup();
forward bench_teardown();

// Marks the running test as passed. Pending steps are dropped.
native bench_pass();

// Marks the running test as failed with a formatted reason.
native bench_fail(const fmt[], any:...);

// Fails the running test with "what" when condition is false. Returns the condition.
native bool:bench_check(bool:condition, const what[]);

// Names the running test in the report. Without it the name comes from the public:
// test_menu_opens is reported as "menu opens".
native bench_describe(const fmt[], any:...);

// The running test changes the map, or makes a plugin change it: the run goes on on the new map by
// calling step(data) in this test file, reloaded (its variables start over; puppets are gone, as the
// engine drops fake clients on a map change). A map change no test expects fails the test running.
native bench_expect_map_change(const step[], data = 0);

// Changes to map (the current one if empty) and goes on with step(data) there.
stock bench_change_map(const map[], const step[], data = 0)
{
	new name[64];
	if (map[0])
		copy(name, charsmax(name), map);
	else
		get_mapname(name, charsmax(name));
	bench_expect_map_change(step, data);
	server_cmd("changelevel %s", name);
}

// A run time error whose description contains text is part of the running test: it does not fail
// the test, and the test fails if no such error comes before it ends. For code that must fail.
native bench_expect_error(const text[]);

// Lets the running test take up to seconds game seconds from its start (default bench_timeout).
native bench_set_timeout(Float:seconds);

// The server's local time reads hour:minute (seconds keep running) until the test ends, for code
// that depends on the time of day (get_time, format_time). Done through TZ; UTC is unchanged.
native bench_set_local_time(hour, minute);

// Calls step(data) in this plugin after delay game seconds (0.0 = next frame).
native bench_next(const step[], Float:delay = 0.0, data = 0);

// Calls condition(data) every frame; once it returns true, calls step(data). If that takes longer
// than timeout game seconds, the test fails.
native bench_wait_until(const condition[], const step[], Float:timeout, data = 0);

// Creates a fake client the module drives every frame. Returns its player index, 0 on failure.
// Puppets are kicked when the test ends. A puppet stands in for a person: plugins see an ordinary
// player (is_user_bot() is false, client_print reaches it) with its own auth ID, authid or else
// STEAM_0:0:1001, 1002, ... in creation order. as_bot = true makes it a bot ("BOT") instead.
native bench_puppet(const name[] = "puppet", bool:as_bot = false, const authid[] = "");

// Sets the buttons (IN_*) and movement a puppet holds until changed.
native bench_puppet_input(id, buttons, Float:fwd = 0.0, Float:side = 0.0, Float:up = 0.0, impulse = 0);

// Sets a puppet's view angles: pitch (down positive), yaw, roll.
native bench_puppet_angles(id, const Float:angles[3]);

// Runs a console command from the puppet, as its client would send it: plugins' register_clcmd
// handlers, read_argv/read_args and the game all see it. Example: bench_puppet_cmd(id, "kill").
native bench_puppet_cmd(id, const fmt[], any:...);

// Sets a userinfo key on the puppet the way a client's setinfo does: the game and plugins
// (client_infochanged) see the change. Examples: "_pw" before a login check, "name" for a rename.
native bench_puppet_setinfo(id, const key[], const value[]);

// Says text in chat (team: say_team), as typed into the chat box.
stock bench_puppet_say(id, const text[], bool:team = false)
{
	bench_puppet_cmd(id, "%s ^"%s^"", team ? "say_team" : "say", text);
}

// ---------------------------------------------------------------------------------------------
// Messages. Every user message sent to a puppet during the current test is recorded with its
// arguments, along with messages sent to all players. A BenchMsg: handle names one of them; 0 is
// none. name filters by message name ("SayText", "TextMsg", "ShowMenu", ...), text by a substring
// of any string argument. Both are optional. Text the engine prints to a puppet (engclient_print)
// is recorded too, under the names "console", "center" and "chat" (console_print and client_print
// reach a player as TextMsg messages), commands stuffed into its console (client_cmd) as
// "stufftext", and every line the server console shows during the test as "server" for id 0:
// ASSERT_MSG(0, "server", "Loaded 1 admin").

// Whether this engine supports capture (ReHLDS 3.15+, or the stock HLDS engine).
native bool:bench_msg_available();

native bench_msg_count(id, const name[] = "", const text[] = "");
native BenchMsg:bench_msg_last(id, const name[] = "", const text[] = "");

// The first matching message after "after" (BenchMsg:0 = from the start of the test).
native BenchMsg:bench_msg_next(id, BenchMsg:after = BenchMsg:0, const name[] = "", const text[] = "");

native bench_msg_name(BenchMsg:msg, out[], len);
native bench_msg_args(BenchMsg:msg);
native bench_msg_int(BenchMsg:msg, arg);
native Float:bench_msg_float(BenchMsg:msg, arg);
native bench_msg_string(BenchMsg:msg, arg, out[], len);

// The message's string arguments joined together (e.g. a SayText's format and text).
native bench_msg_text(BenchMsg:msg, out[], len);

stock __bench_wait_name[32];
stock __bench_wait_text[128];

// Calls step(id) once a message matching name and text has been sent to puppet id this test.
stock bench_wait_message(id, const name[], const text[], const step[], Float:timeout)
{
	copy(__bench_wait_name, charsmax(__bench_wait_name), name);
	copy(__bench_wait_text, charsmax(__bench_wait_text), text);
	bench_wait_until("__bench_has_message", step, timeout, id);
}

public __bench_has_message(id)
{
	return bench_msg_last(id, __bench_wait_name, __bench_wait_text) != BenchMsg:0;
}

// Fails unless puppet id was sent a message matching name and text this test.
#define ASSERT_MSG(%0,%1,%2)    if (!__bench_msg(%0, %1, %2)) return

stock bool:__bench_msg(id, const name[], const text[])
{
	if (!bench_msg_available())
	{
		bench_fail("message capture is not available on this engine");
		return false;
	}
	if (bench_msg_last(id, name, text) != BenchMsg:0)
		return true;
	new BenchMsg:last = bench_msg_last(id, name), got[128] = "nothing";
	if (last != BenchMsg:0)
		bench_msg_text(last, got, charsmax(got));
	bench_fail("no %s containing ^"%s^" sent to %d; last %s: ^"%s^"", name, text, id, name, got);
	return false;
}

// Assertions. Each fails the test with what was expected and received, and the report gives the
// assertion's file:line. (They do not quote the expression: amxxpc cannot stringize an argument
// that holds a string literal.) ASSERT_EQ(received, expected); ASSERT_STR_EQ(received, "expected").
#define ASSERT(%0)              if (!bench_check(bool:(%0), "expected true, received false")) return
#define ASSERT_TRUE(%0)         if (!bench_check(bool:(%0), "expected true, received false")) return
#define ASSERT_FALSE(%0)        if (!bench_check(!(%0), "expected false, received true")) return
#define ASSERT_EQ(%0,%1)        if (!__bench_eq(%0, %1)) return
#define ASSERT_STR_EQ(%0,%1)    if (!__bench_str_eq(%0, %1)) return

stock bool:__bench_eq(received, expected)
{
	if (received == expected)
		return true;
	bench_fail("expected %d, received %d", expected, received);
	return false;
}

stock bool:__bench_str_eq(const received[], const expected[])
{
	if (equal(received, expected))
		return true;
	bench_fail("expected ^"%s^", received ^"%s^"", expected, received);
	return false;
}

// ---------------------------------------------------------------------------------------------
// Puppet helpers

stock __bench_join_cmd[32];
stock __bench_after_press[32];

// Calls step(id) once the puppet is alive. If joincmd is set (TS: "respawn"), the puppet sends it
// as a client command while waiting, the way a real player joins on that mod.
stock bench_puppet_spawn(id, const step[], Float:timeout = 20.0, const joincmd[] = "")
{
	copy(__bench_join_cmd, charsmax(__bench_join_cmd), joincmd);
	bench_wait_until("__bench_puppet_alive", step, timeout, id);
}

public __bench_puppet_alive(id)
{
	if (is_user_alive(id))
		return true;
	if (__bench_join_cmd[0])
		engclient_cmd(id, __bench_join_cmd);
	return false;
}

// Presses buttons for one frame, then calls step(id) on the frame after the release.
stock bench_puppet_press(id, buttons, const step[])
{
	bench_puppet_input(id, buttons);
	copy(__bench_after_press, charsmax(__bench_after_press), step);
	bench_next("__bench_release", 0.0, id);
}


public __bench_release(id)
{
	bench_puppet_input(id, 0);
	bench_next(__bench_after_press, 0.0, id);
}

// Looks at a point: yaw and pitch from the puppet's eyes to target.
stock bench_puppet_look_at(id, const Float:target[3])
{
	new Float:origin[3], Float:ofs[3], Float:dir[3], Float:angles[3];
	pev(id, pev_origin, origin);
	pev(id, pev_view_ofs, ofs);
	for (new i = 0; i < 3; i++)
		dir[i] = target[i] - (origin[i] + ofs[i]);
	engfunc(EngFunc_VecToAngles, dir, angles);
	angles[0] = -angles[0];
	bench_puppet_angles(id, angles);
}

// Stands the puppet on the floor dist units from ent, on the first of eight compass points that has
// room for it and a level line of sight from its eyes to ent, facing ent. Returns false if none.
stock bool:bench_puppet_face(id, ent, Float:dist = 56.0)
{
	new Float:center[3], Float:pos[3], Float:end[3], Float:eye[3], Float:ofs[3], Float:yaw;
	pev(ent, pev_origin, center);
	pev(id, pev_view_ofs, ofs);
	new tr = create_tr2(), bool:found = false;

	for (new i = 0; i < 8 && !found; i++)
	{
		yaw = float(i) * 45.0;
		pos[0] = center[0] + floatcos(yaw, degrees) * dist;
		pos[1] = center[1] + floatsin(yaw, degrees) * dist;
		pos[2] = center[2] + 18.0;

		engfunc(EngFunc_TraceHull, pos, pos, DONT_IGNORE_MONSTERS, HULL_HUMAN, id, tr);
		if (get_tr2(tr, TR_StartSolid) || get_tr2(tr, TR_AllSolid))
			continue;

		end = pos;
		end[2] -= 128.0;
		engfunc(EngFunc_TraceHull, pos, end, DONT_IGNORE_MONSTERS, HULL_HUMAN, id, tr);
		get_tr2(tr, TR_vecEndPos, pos);

		for (new k = 0; k < 3; k++)
			eye[k] = pos[k] + ofs[k];
		end[0] = eye[0] - floatcos(yaw, degrees) * (dist + 32.0);
		end[1] = eye[1] - floatsin(yaw, degrees) * (dist + 32.0);
		end[2] = eye[2];
		engfunc(EngFunc_TraceLine, eye, end, DONT_IGNORE_MONSTERS, id, tr);
		if (get_tr2(tr, TR_pHit) != ent)
			continue;

		engfunc(EngFunc_SetOrigin, id, pos);
		set_pev(id, pev_velocity, Float:{0.0, 0.0, 0.0});
		new Float:angles[3];
		angles[1] = yaw + 180.0;
		bench_puppet_angles(id, angles);
		found = true;
	}
	free_tr2(tr);
	return found;
}

// ---------------------------------------------------------------------------------------------
// Menus. AMX Mod X sends menus to the client as ShowMenu messages, which a fake client never
// receives, so these read the menu AMX Mod X has open for the player instead.

// Returns the open newmenu (menu_create) for id, or -1. oldmenu gets the old-style menu id, if any.
stock bench_menu_open(id, &oldmenu = 0)
{
	new newmenu, page;
	if (!player_menu_info(id, oldmenu, newmenu, page))
		return -1;
	return newmenu;
}

// Copies the text of item (0-based) of id's open newmenu. Returns false if there is none.
stock bool:bench_menu_item(id, item, name[], len, info[] = "", infolen = 0)
{
	new menu = bench_menu_open(id);
	if (menu < 0 || item >= menu_items(menu))
		return false;
	new access, callback;
	menu_item_getinfo(menu, item, access, info, infolen, name, len, callback);
	return true;
}

// ---------------------------------------------------------------------------------------------
// Fixtures: files a test reads, kept next to the tests in plugins/tests/fixtures/ and installed
// with them (addons/amxmodx/plugins/tests/fixtures/).

// Copies the path of fixture name, as file natives take it (relative to the mod directory).
stock bench_fixture(const name[], path[], len)
{
	new dir[128];
	get_localinfo("amxx_pluginsdir", dir, charsmax(dir));
	if (!dir[0])
		copy(dir, charsmax(dir), "addons/amxmodx/plugins");
	return formatex(path, len, "%s/tests/fixtures/%s", dir, name);
}

// ---------------------------------------------------------------------------------------------
// Coverage

// Leaves lines first..last of a source file (by name, e.g. "admin.sma") out of coverage; the
// report lists them with the reason. For code a test cannot reach, such as listen-server-only
// paths. Call it from the test file (plugin_init or bench_setup), not from the plugin under test.
native bench_coverage_ignore(const file[], first, last, const reason[]);
