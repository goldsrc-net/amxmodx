// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for admincmd.sma (Admin Commands): every command an admin puppet can run, and what it
// does: players kicked, slain, slapped and renamed, bans written to banned.cfg and listip.cfg,
// cvars and xvars read and set, configs executed, the pause handshake, and the queue of recently
// disconnected players that amx_addban and amx_last read. The admin gets its access with
// set_user_flags. Permanent bans are checked in the files the engine writes; banned.cfg and
// listip.cfg are put back (or removed, when the server had none) after every test, and the test
// bans are lifted.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#define BOSS_AUTH "STEAM_0:0:7100"

public bench_xvar_num = 42
public Float:bench_xvar_float = 1.5
public bench_xvar_locked = 3

new const BanFiles[][] = {"banned.cfg", "listip.cfg"}
new const TestAuths[][] = {"STEAM_0:0:7101", "STEAM_0:0:7102", "STEAM_0:0:7103", "STEAM_0:0:7201",
	"STEAM_0:0:7202", "STEAM_0:0:7203", "STEAM_0:0:7299"}
new const TestIPs[][] = {"127.0.0.1", "10.66.66.66"}

new g_Cvar
new g_CvarFlags
new g_SavedActivity
new g_SavedMaxTime
new Float:g_SavedTimeLimit
new Float:g_SavedPausable
new g_SavedPassword[64]
new g_SavedRcon[64]
new g_SavedCfgFile[64]
// Set by bench_setup; false in the copy of this file a map change loads, which has nothing to put
// back (the test restores everything before it changes the map).
new bool:g_SetUp

new g_Boss
new g_Target
new g_Third
new g_Fourth
new g_Bot
new g_Step[32]
new g_BossFlags[32]
new g_Batch
new g_UserId
new Float:g_Health

public plugin_init()
{
	register_plugin("Admin Commands Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	g_Cvar = register_cvar("bench_admincmd_cvar", "abc")
	g_CvarFlags = get_pcvar_flags(g_Cvar)

	bench_coverage_ignore("admincmd.sma", 117, 117, "GetInfo is only called with i < g_Size")
	bench_coverage_ignore("admincmd.sma", 800, 800, "a command argument never holds a newline: the engine ends a command at one")
}

public bench_setup()
{
	g_SavedActivity = get_cvar_num("amx_show_activity")
	g_SavedMaxTime = get_cvar_num("amx_tempban_maxtime")
	g_SavedTimeLimit = get_cvar_float("mp_timelimit")
	g_SavedPausable = get_cvar_float("pausable")
	get_cvar_string("sv_password", g_SavedPassword, charsmax(g_SavedPassword))
	get_cvar_string("rcon_password", g_SavedRcon, charsmax(g_SavedRcon))
	get_cvar_string("servercfgfile", g_SavedCfgFile, charsmax(g_SavedCfgFile))
	set_cvar_num("amx_show_activity", 2)
	set_pcvar_string(g_Cvar, "abc")
	set_pcvar_flags(g_Cvar, g_CvarFlags)
	bench_xvar_num = 42
	bench_xvar_float = 1.5
	bench_xvar_locked = 3

	for (new i = 0; i < sizeof(BanFiles); i++)
		SaveFile(BanFiles[i])

	g_Boss = g_Target = g_Third = g_Fourth = g_Bot = 0
	g_Batch = 0
	g_SetUp = true
}

public bench_teardown()
{
	if (g_SetUp)
		Restore()
}

Restore()
{
	g_SetUp = false
	// Let the commands the plugin queued finish first (each "wait" in them stops one pass), so a
	// late writeid or writeip cannot rewrite a ban file after it is put back.
	for (new i = 0; i < 4; i++)
		server_exec()

	for (new i = 0; i < sizeof(TestAuths); i++)
		server_cmd("removeid %s", TestAuths[i])
	for (new i = 0; i < sizeof(TestIPs); i++)
		server_cmd("removeip %s", TestIPs[i])
	server_exec()

	for (new i = 0; i < sizeof(BanFiles); i++)
		RestoreFile(BanFiles[i])

	set_cvar_num("amx_show_activity", g_SavedActivity)
	set_cvar_num("amx_tempban_maxtime", g_SavedMaxTime)
	set_cvar_float("mp_timelimit", g_SavedTimeLimit)
	set_cvar_float("pausable", g_SavedPausable)
	set_cvar_string("sv_password", g_SavedPassword)
	set_cvar_string("rcon_password", g_SavedRcon)
	set_cvar_string("servercfgfile", g_SavedCfgFile)
	set_pcvar_string(g_Cvar, "abc")
	set_pcvar_flags(g_Cvar, g_CvarFlags)
}

// Moves a ban file aside for the test. A saved copy (or the note that there was none) already
// there is the server's own state, left by a run that stopped before teardown: keep it, and drop
// the file that run wrote.
SaveFile(const name[])
{
	new saved[64], none[64]
	formatex(saved, charsmax(saved), "%s.bench", name)
	formatex(none, charsmax(none), "%s.bench-none", name)
	if (file_exists(saved) || file_exists(none))
	{
		delete_file(name)
		return
	}
	if (file_exists(name))
		rename_file(name, saved, 1)
	else
		write_file(none, "; banned.cfg or listip.cfg did not exist before amxxbench's admincmd tests")
}

RestoreFile(const name[])
{
	new saved[64], none[64]
	formatex(saved, charsmax(saved), "%s.bench", name)
	formatex(none, charsmax(none), "%s.bench-none", name)
	delete_file(name)
	if (file_exists(saved))
		rename_file(saved, name, 1)
	delete_file(none)
}

// Whether a line of file name contains text.
bool:FileHas(const name[], const text[])
{
	new f = fopen(name, "rt")
	if (!f)
		return false
	new line[128], bool:found = false
	while (!found && fgets(f, line, charsmax(line)))
		found = contain(line, text) != -1
	fclose(f)
	return found
}

SetFlags(id, const flags[])
{
	remove_user_flags(id, -1)
	set_user_flags(id, read_flags(flags))
}

// Counts the text messages (client_print, console_print) of one kind sent to id containing text:
// print_notify, print_console or print_chat.
CountPrint(id, dest, const text[])
{
	new count, BenchMsg:msg
	while ((msg = bench_msg_next(id, msg, "TextMsg", text)) != BenchMsg:0)
	{
		if (bench_msg_int(msg, 0) == dest)
			count++
	}
	return count
}

// The admin "boss" with these flags and, if named, a plain player; step runs once they are in.
Start(const bossflags[], const target[], const targetauth[], const step[])
{
	copy(g_BossFlags, charsmax(g_BossFlags), bossflags)
	copy(g_Step, charsmax(g_Step), step)
	g_Boss = bench_puppet("boss", false, BOSS_AUTH)
	if (!bench_check(g_Boss > 0, "admin puppet created"))
		return
	if (target[0])
	{
		g_Target = bench_puppet(target, false, targetauth)
		if (!bench_check(g_Target > 0, "target puppet created"))
			return
	}
	bench_next("started", 0.1)
}

public started()
{
	SetFlags(g_Boss, g_BossFlags)
	if (g_Target)
		SetFlags(g_Target, "z")
	bench_next(g_Step)
}

Kick(id)
{
	server_cmd("kick #%d", get_user_userid(id))
	server_exec()
}

public target_gone()
{
	return !is_user_connected(g_Target) || get_user_userid(g_Target) != g_UserId
}

// ---------------------------------------------------------------------------------------------
// amx_kick

public test_kick()
{
	Start("c", "kickme", "", "kick")
}

public kick()
{
	g_Third = bench_puppet("untouchable")
	ASSERT(g_Third > 0)
	SetFlags(g_Third, "a")

	bench_puppet_cmd(g_Target, "amx_kick boss")
	ASSERT_MSG(g_Target, "TextMsg", "You have no access to that command")
	bench_puppet_cmd(g_Boss, "amx_kick")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_kick <name or #userid> [reason]")
	bench_puppet_cmd(g_Boss, "amx_kick nosuchplayer")
	ASSERT_MSG(g_Boss, "TextMsg", "Client with that name or userid not found")
	bench_puppet_cmd(g_Boss, "amx_kick untouchable")
	ASSERT_MSG(g_Boss, "TextMsg", "Client ^"untouchable^" has immunity")

	g_UserId = get_user_userid(g_Target)
	bench_puppet_cmd(g_Boss, "amx_kick kickme ^"go away^"")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Client ^"kickme^" kicked"), 1)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: kick kickme"), 1)
	ASSERT_EQ(CountPrint(g_Third, print_chat, "ADMIN boss: kick kickme"), 1)
	bench_wait_until("target_gone", "kick_without_reason", 5.0)
}

public kick_without_reason()
{
	ASSERT(is_user_connected(g_Third))
	g_Target = bench_puppet("noreason")
	ASSERT(g_Target > 0)
	g_UserId = get_user_userid(g_Target)
	bench_puppet_cmd(g_Boss, "amx_kick #%d", g_UserId)
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Client ^"noreason^" kicked")
	bench_wait_until("target_gone", "kick_bot", 5.0)
}

public kick_bot()
{
	g_Target = bench_puppet("kickbot", true)
	ASSERT(g_Target > 0)
	ASSERT(is_user_bot(g_Target))
	g_UserId = get_user_userid(g_Target)
	bench_puppet_cmd(g_Boss, "amx_kick kickbot ^"bots get no reason^"")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Client ^"kickbot^" kicked")
	bench_wait_until("target_gone", "kicked_all", 5.0)
}

public kicked_all()
{
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_slay, amx_slap

public test_slay()
{
	Start("e", "slayme", "", "slay_spawn")
}

public slay_spawn()
{
	bench_puppet_spawn(g_Target, "slay", 20.0, "respawn")
}

public slay(id)
{
	bench_puppet_cmd(g_Boss, "amx_slay")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_slay <name or #userid>")
	bench_puppet_cmd(g_Boss, "amx_slay slayme")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Client ^"slayme^" slayed"), 1)
	ASSERT_EQ(CountPrint(g_Target, print_chat, "ADMIN boss: slay slayme"), 1)
	// The Specialists kills a second after a slay (its ClientKill only arms a timer).
	bench_wait_until("target_dead", "slain", 5.0)
}

public target_dead()
{
	return !is_user_alive(g_Target)
}

public slain()
{
	// Only the living can be slain.
	bench_puppet_cmd(g_Boss, "amx_slay slayme")
	ASSERT_MSG(g_Boss, "TextMsg", "That action can't be performed on dead client ^"slayme^"")
	bench_pass()
}

public test_slap()
{
	Start("e", "slapme", "", "slap_spawn")
}

public slap_spawn()
{
	bench_puppet_spawn(g_Target, "slap", 20.0, "respawn")
}

public slap(id)
{
	bench_puppet_cmd(g_Boss, "amx_slap")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_slap <name or #userid> [power]")
	bench_puppet_cmd(g_Boss, "amx_slap nosuchplayer 5")
	ASSERT_MSG(g_Boss, "TextMsg", "Client with that name or userid not found")

	pev(g_Target, pev_health, g_Health)
	bench_puppet_cmd(g_Boss, "amx_slap slapme 5")
	new Float:health
	pev(g_Target, pev_health, health)
	ASSERT_EQ(floatround(g_Health - health), 5)
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Client ^"slapme^" slapped with 5 damage"), 1)
	ASSERT_EQ(CountPrint(g_Target, print_chat, "ADMIN boss: slap slapme with 5 damage"), 1)

	// No power, or a negative one, is a harmless slap.
	bench_puppet_cmd(g_Boss, "amx_slap slapme -3")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Client ^"slapme^" slapped with 0 damage")
	pev(g_Target, pev_health, g_Health)
	ASSERT(g_Health == health)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_ban, amx_banip

public test_ban_permanent()
{
	Start("d", "banme", "STEAM_0:0:7101", "ban_permanent")
}

public ban_permanent()
{
	g_Third = bench_puppet("watcher")
	ASSERT(g_Third > 0)
	SetFlags(g_Third, "z")
	bench_puppet_cmd(g_Boss, "amx_ban banme")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_ban <name or #userid> <minutes> [reason]")
	bench_puppet_cmd(g_Boss, "amx_ban nosuchplayer 0")
	ASSERT_MSG(g_Boss, "TextMsg", "Client with that name or userid not found")

	// A negative time is a permanent ban.
	g_UserId = get_user_userid(g_Target)
	bench_puppet_cmd(g_Boss, "amx_ban banme -5 cheating")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Client ^"banme^" banned"), 1)
	ASSERT_EQ(CountPrint(g_Third, print_chat, "ADMIN boss: ban banme permanently (reason: cheating)"), 1)
	bench_wait_until("target_gone", "ban_permanent_written", 5.0)
}

public ban_permanent_written()
{
	bench_next("ban_permanent_file", 0.5)
}

public ban_permanent_file()
{
	// The engine wrote its ban list. (On this server, sv_lan 1 turns every Steam ID given to banid
	// into STEAM_ID_LAN, which is not written, so the entry itself cannot be checked.)
	ASSERT(file_exists("banned.cfg"))
	bench_pass()
}

public test_temporary_ban_by_temp_admin()
{
	Start("v", "tempban", "STEAM_0:0:7102", "temp_ban")
}

public temp_ban()
{
	set_cvar_num("amx_tempban_maxtime", 60)
	// A temp-ban admin may not ban for good, nor longer than amx_tempban_maxtime.
	bench_puppet_cmd(g_Boss, "amx_ban tempban 0")
	bench_puppet_cmd(g_Boss, "amx_ban tempban 61")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "You can only temporarily ban players, for up to 60 minutes"), 2)
	ASSERT(is_user_connected(g_Target))

	g_UserId = get_user_userid(g_Target)
	bench_puppet_cmd(g_Boss, "amx_ban tempban 30")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Client ^"tempban^" banned"), 1)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: ban tempban for 30 min"), 1)
	ASSERT_EQ(bench_msg_count(g_Boss, "", "(reason"), 0)
	bench_wait_until("target_gone", "temp_unban", 5.0)
}

public temp_unban()
{
	// The admin may lift a ban they made, and only that.
	bench_puppet_cmd(g_Boss, "amx_unban ^"STEAM_0:0:7298^"")
	ASSERT_MSG(g_Boss, "TextMsg", "You can only unban players that you have recently banned")
	bench_puppet_cmd(g_Boss, "amx_unban ^"STEAM_0:0:7102^"")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Authid ^"STEAM_0:0:7102^" removed from ban list"), 1)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: unban STEAM_0:0:7102"), 1)
	bench_pass()
}

public test_banip_permanent()
{
	Start("d", "ipbanme", "STEAM_0:0:7103", "banip_permanent")
}

public banip_permanent()
{
	bench_puppet_cmd(g_Boss, "amx_banip ipbanme")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_banip <name or #userid> <minutes> [reason]")
	bench_puppet_cmd(g_Boss, "amx_banip nosuchplayer 0")
	ASSERT_MSG(g_Boss, "TextMsg", "Client with that name or userid not found")

	g_UserId = get_user_userid(g_Target)
	bench_puppet_cmd(g_Boss, "amx_banip ipbanme -1")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Client ^"ipbanme^" banned"), 1)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: ban ipbanme permanently"), 1)
	bench_wait_until("target_gone", "banip_written", 5.0)
}

public banip_written()
{
	bench_next("banip_file", 0.5)
}

public banip_file()
{
	// Puppets connect from 127.0.0.1.
	ASSERT(FileHas("listip.cfg", "127.0.0.1"))
	bench_pass()
}

public test_banip_temporary()
{
	Start("v", "iptemp", "STEAM_0:0:7103", "banip_temporary")
}

public banip_temporary()
{
	set_cvar_num("amx_tempban_maxtime", 60)
	bench_puppet_cmd(g_Boss, "amx_banip iptemp 0")
	ASSERT_MSG(g_Boss, "TextMsg", "You can only temporarily ban players, for up to 60 minutes")
	ASSERT(is_user_connected(g_Target))

	g_UserId = get_user_userid(g_Target)
	bench_puppet_cmd(g_Boss, "amx_banip iptemp 10")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Client ^"iptemp^" banned")
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: ban iptemp for 10 min"), 1)
	bench_wait_until("target_gone", "banip_temporary_done", 5.0)
}

public banip_temporary_done()
{
	bench_next("banip_temporary_file", 0.5)
}

public banip_temporary_file()
{
	ASSERT_FALSE(FileHas("listip.cfg", "127.0.0.1"))
	bench_pass()
}

// amx_ban says "ban <name> for 10 min (reason: spam)". amx_banip writes the time at msg[len]
// without adding its length to len (admincmd.sma:573, 577), so the reason overwrites it.
public test_banip_reason_keeps_time()
{
	bench_describe("banip with a reason keeps the time")
	Start("d", "ipreason", "STEAM_0:0:7103", "banip_reason")
}

public banip_reason()
{
	g_UserId = get_user_userid(g_Target)
	bench_puppet_cmd(g_Boss, "amx_banip ipreason 10 spam")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Client ^"ipreason^" banned")
	bench_wait_until("target_gone", "banip_reason_done", 5.0)
}

public banip_reason_done()
{
	new BenchMsg:msg = bench_msg_last(g_Boss, "TextMsg", "(reason: spam)"), text[128]
	ASSERT(msg != BenchMsg:0)
	bench_msg_text(msg, text, charsmax(text))
	trim(text)
	ASSERT_STR_EQ(text, "ADMIN boss: ban ipreason for 10 min (reason: spam)")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_unban

public test_unban()
{
	Start("d", "", "", "unban")
}

public unban()
{
	bench_puppet_cmd(g_Boss, "amx_unban")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_unban <^"authid^" or ip>")

	server_cmd("addip 0 10.66.66.66")
	server_cmd("writeip")
	server_exec()
	ASSERT(FileHas("listip.cfg", "10.66.66.66"))
	bench_puppet_cmd(g_Boss, "amx_unban 10.66.66.66")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] IP ^"10.66.66.66^" removed from ban list"), 1)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: unban 10.66.66.66"), 1)
	bench_next("unban_written", 0.2)
}

public unban_written()
{
	ASSERT_FALSE(FileHas("listip.cfg", "10.66.66.66"))

	bench_puppet_cmd(g_Boss, "amx_unban ^"STEAM_0:0:7201^"")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Authid ^"STEAM_0:0:7201^" removed from ban list")

	// A ';' would end the command the plugin builds and start another.
	bench_puppet_cmd(g_Boss, "amx_unban ^"STEAM_0:0:7202;writeid^"")
	ASSERT_MSG(g_Boss, "TextMsg", "Client with that name or userid not found")
	bench_next("unban_authid_written", 0.2)
}

public unban_authid_written()
{
	// removeid's writeid ran.
	ASSERT(file_exists("banned.cfg"))
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_addban and the queue of recently disconnected players

public test_addban_by_rcon_admin()
{
	// ADMIN_RCON without ADMIN_BAN may ban any auth ID or address.
	Start("l", "", "", "addban_rcon")
}

public addban_rcon()
{
	bench_puppet_cmd(g_Boss, "amx_addban ^"STEAM_0:0:7201^"")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_addban")

	bench_puppet_cmd(g_Boss, "amx_addban ^"STEAM_0:0:7201^" 0 ^"for the test^"")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Authid ^"STEAM_0:0:7201^" added to ban list"), 1)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: ban STEAM_0:0:7201"), 1)
	bench_puppet_cmd(g_Boss, "amx_addban 10.66.66.66 0")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Ip ^"10.66.66.66^" added to ban list"), 1)
	bench_puppet_cmd(g_Boss, "amx_addban ^"STEAM_0:0:7202;writeid^" 0")
	ASSERT_MSG(g_Boss, "TextMsg", "Client with that name or userid not found")
	bench_next("addban_rcon_written", 0.5)
}

public addban_rcon_written()
{
	ASSERT(file_exists("banned.cfg"))
	ASSERT(FileHas("listip.cfg", "10.66.66.66"))
	bench_pass()
}

public test_addban_access()
{
	Start("d", "noaccess", "", "addban_access")
}

public addban_access()
{
	// Without ADMIN_BAN or ADMIN_RCON: refused.
	bench_puppet_cmd(g_Target, "amx_addban ^"STEAM_0:0:7299^" 0")
	ASSERT_MSG(g_Target, "TextMsg", "You have no access to that command")
	// ADMIN_BAN with too few arguments: the usage, and no second refusal for lacking ADMIN_RCON.
	bench_puppet_cmd(g_Boss, "amx_addban ^"STEAM_0:0:7299^"")
	ASSERT_EQ(bench_msg_count(g_Boss, "TextMsg", "Usage:  amx_addban"), 1)
	ASSERT_EQ(bench_msg_count(g_Boss, "TextMsg", "You have no access"), 0)
	// Placeholder IDs are never banned.
	bench_puppet_cmd(g_Boss, "amx_addban STEAM_ID_LAN 0")
	ASSERT_MSG(g_Boss, "TextMsg", "Cannot ban STEAM_ID_LAN")
	// Without ADMIN_RCON, only players in the disconnect queue.
	bench_puppet_cmd(g_Boss, "amx_addban ^"STEAM_0:0:7299^" 0")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] You may only ban recently disconnected clients.  Use ^"amx_last^" to view.")
	bench_pass()
}

public test_addban_recently_disconnected()
{
	Start("d", "", "", "addban_queue")
}

public addban_queue()
{
	g_Target = bench_puppet("leftimmune", false, "STEAM_0:0:7202")
	g_Third = bench_puppet("leftplain", false, "STEAM_0:0:7203")
	ASSERT(g_Target > 0 && g_Third > 0)
	SetFlags(g_Target, "a")
	SetFlags(g_Third, "z")
	Kick(g_Target)
	Kick(g_Third)
	ASSERT_FALSE(is_user_connected(g_Target))

	// An immune player stays protected after leaving.
	bench_puppet_cmd(g_Boss, "amx_addban ^"STEAM_0:0:7202^" 0")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] STEAM_0:0:7202 : Client ^"leftimmune^" has immunity")
	bench_puppet_cmd(g_Boss, "amx_addban 127.0.0.1 0")
	// (Any immune player who left from this address will do: every puppet has it.)
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] 127.0.0.1 : Client ^"")
	ASSERT_MSG(g_Boss, "TextMsg", "^" has immunity")

	bench_puppet_cmd(g_Boss, "amx_addban ^"STEAM_0:0:7203^" 0 ^"left to dodge^"")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Authid ^"STEAM_0:0:7203^" added to ban list")
	bench_next("addban_queue_written", 0.5)
}

public addban_queue_written()
{
	ASSERT(file_exists("banned.cfg"))
	bench_pass()
}

// The queue holds the last ten. Twenty-one more leave (filling it and going round twice), none
// immune, so the immune one above is gone and the address may be banned.
public test_addban_address_after_queue_turns_over()
{
	Start("d", "", "", "turnover")
}

public turnover()
{
	new ids[7]
	for (new i = 0; i < 7; i++)
	{
		ids[i] = bench_puppet(fmt("leaver%d", g_Batch * 7 + i), false, fmt("STEAM_0:0:74%02d", g_Batch * 7 + i))
		ASSERT(ids[i] > 0)
		SetFlags(ids[i], "z")
	}
	for (new i = 0; i < 7; i++)
		Kick(ids[i])
	if (++g_Batch < 3)
	{
		bench_next("turnover", 0.1)
		return
	}
	bench_puppet_cmd(g_Boss, "amx_last")
	ASSERT_MSG(g_Boss, "TextMsg", "10 old connections saved.")
	ASSERT_MSG(g_Boss, "TextMsg", "STEAM_0:0:7420")
	ASSERT_EQ(bench_msg_count(g_Boss, "TextMsg", "STEAM_0:0:7410"), 0)

	bench_puppet_cmd(g_Boss, "amx_addban 127.0.0.1 0")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Ip ^"127.0.0.1^" added to ban list")
	bench_next("turnover_written", 0.5)
}

public turnover_written()
{
	ASSERT(FileHas("listip.cfg", "127.0.0.1"))
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_last

public test_last_merges_a_player_leaving_twice()
{
	Start("d", "", "", "last")
}

public last()
{
	g_Target = bench_puppet("firstvisit", false, "STEAM_0:0:7299")
	ASSERT(g_Target > 0)
	SetFlags(g_Target, "z")
	Kick(g_Target)
	// Back under a new name and gone again: one entry, with the new name and access.
	g_Target = bench_puppet("secondvisit", false, "STEAM_0:0:7299")
	ASSERT(g_Target > 0)
	SetFlags(g_Target, "bz")
	Kick(g_Target)
	// A bot is not recorded.
	g_Bot = bench_puppet("leavingbot", true)
	ASSERT(g_Bot > 0)
	Kick(g_Bot)

	bench_puppet_cmd(g_Boss, "amx_last")
	ASSERT_MSG(g_Boss, "TextMsg", "access")
	ASSERT_MSG(g_Boss, "TextMsg", "old connections saved.")
	ASSERT_EQ(bench_msg_count(g_Boss, "TextMsg", "STEAM_0:0:7299"), 1)
	new BenchMsg:msg = bench_msg_last(g_Boss, "TextMsg", "STEAM_0:0:7299"), text[128]
	bench_msg_text(msg, text, charsmax(text))
	ASSERT(contain(text, "secondvisit") != -1)
	ASSERT(contain(text, "127.0.0.1") != -1)
	ASSERT(contain(text, " bz") != -1)
	// The only other mentions of the bot are the game's "has left the game".
	while ((msg = bench_msg_next(g_Boss, msg, "TextMsg", "leavingbot")) != BenchMsg:0)
	{
		bench_msg_text(msg, text, charsmax(text))
		ASSERT(contain(text, "has left the game") != -1)
	}
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_who

public test_who()
{
	Start("d", "lister", "STEAM_0:0:7101", "who")
}

public who()
{
	g_Third = bench_puppet("shielded")
	ASSERT(g_Third > 0)
	SetFlags(g_Third, "ab")
	bench_puppet_cmd(g_Target, "amx_who")
	ASSERT_MSG(g_Target, "TextMsg", "You have no access to that command")

	bench_puppet_cmd(g_Boss, "amx_who")
	ASSERT_MSG(g_Boss, "TextMsg", "Clients on server:")
	ASSERT_MSG(g_Boss, "TextMsg", "Total 3")
	new BenchMsg:msg = bench_msg_last(g_Boss, "TextMsg", "lister"), text[128]
	bench_msg_text(msg, text, charsmax(text))
	ASSERT(contain(text, "STEAM_0:0:7101") != -1)
	ASSERT(contain(text, "No     No") != -1)
	msg = bench_msg_last(g_Boss, "TextMsg", "shielded")
	bench_msg_text(msg, text, charsmax(text))
	ASSERT(contain(text, "Yes    Yes    ab") != -1)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_cvar

public test_cvar_read_and_set()
{
	Start("g", "cvarwatch", "", "cvar_set")
}

public cvar_set()
{
	bench_puppet_cmd(g_Boss, "amx_cvar")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_cvar <cvar> [value]")
	bench_puppet_cmd(g_Boss, "amx_cvar bench_admincmd_cvar")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Cvar ^"bench_admincmd_cvar^" is ^"abc^"")
	bench_puppet_cmd(g_Boss, "amx_cvar nosuchcvar_qq")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Unknown cvar: nosuchcvar_qq")

	bench_puppet_cmd(g_Boss, "amx_cvar bench_admincmd_cvar xyz")
	new value[32]
	get_pcvar_string(g_Cvar, value, charsmax(value))
	ASSERT_STR_EQ(value, "xyz")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Cvar ^"bench_admincmd_cvar^" changed to ^"xyz^""), 1)
	ASSERT_EQ(CountPrint(g_Target, print_chat, "ADMIN boss:  set cvar bench_admincmd_cvar to ^"xyz^""), 1)
	bench_pass()
}

public test_cvar_protected()
{
	Start("g", "cvarwatch", "", "cvar_protected")
}

public cvar_protected()
{
	// rcon_password is protected: ADMIN_RCON only.
	bench_puppet_cmd(g_Boss, "amx_cvar rcon_password")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] You have no access to that cvar")

	// sv_password is protected too, but ADMIN_PASSWORD may set it; its value is not shown.
	bench_puppet_cmd(g_Boss, "amx_cvar sv_password hunter2")
	ASSERT_EQ(bench_msg_count(g_Boss, "TextMsg", "You have no access to that cvar"), 2)
	SetFlags(g_Boss, "gk")
	bench_puppet_cmd(g_Boss, "amx_cvar sv_password hunter2")
	new value[32]
	get_cvar_string("sv_password", value, charsmax(value))
	ASSERT_STR_EQ(value, "hunter2")
	ASSERT_EQ(CountPrint(g_Target, print_chat, "set cvar sv_password to ^"*** PROTECTED ***^""), 1)
	ASSERT_EQ(bench_msg_count(g_Target, "", "hunter2"), 0)
	bench_pass()
}

public test_cvar_add_protection()
{
	Start("gl", "cvarwatch", "", "cvar_add")
}

public cvar_add()
{
	// "add" by an ADMIN_RCON admin protects a cvar; a cvar that does not exist is ignored.
	bench_puppet_cmd(g_Boss, "amx_cvar add nosuchcvar_qq")
	bench_puppet_cmd(g_Boss, "amx_cvar add bench_admincmd_cvar")
	ASSERT(get_pcvar_flags(g_Cvar) & FCVAR_PROTECTED)
	// Again: already protected.
	bench_puppet_cmd(g_Boss, "amx_cvar add bench_admincmd_cvar")
	ASSERT(get_pcvar_flags(g_Cvar) & FCVAR_PROTECTED)

	// ADMIN_RCON may still set it; everyone sees it as protected.
	bench_puppet_cmd(g_Boss, "amx_cvar bench_admincmd_cvar secretvalue")
	ASSERT_EQ(CountPrint(g_Target, print_chat, "set cvar bench_admincmd_cvar to ^"*** PROTECTED ***^""), 1)
	ASSERT_EQ(bench_msg_count(g_Target, "", "secretvalue"), 0)
	// Without ADMIN_RCON it is out of reach.
	SetFlags(g_Boss, "g")
	bench_puppet_cmd(g_Boss, "amx_cvar bench_admincmd_cvar other")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] You have no access to that cvar")
	// Without ADMIN_RCON, "add" is the name of a cvar, which does not exist.
	bench_puppet_cmd(g_Boss, "amx_cvar add bench_admincmd_cvar")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Unknown cvar: add")
	new value[32]
	get_pcvar_string(g_Cvar, value, charsmax(value))
	ASSERT_STR_EQ(value, "secretvalue")
	bench_pass()
}

public test_cvar_config_file_names_stop_at_semicolon()
{
	Start("g", "", "", "cvar_cfgfile")
}

public cvar_cfgfile()
{
	bench_puppet_cmd(g_Boss, "amx_cvar servercfgfile ^"bench.cfg;echo injected^"")
	new value[64]
	get_cvar_string("servercfgfile", value, charsmax(value))
	ASSERT_STR_EQ(value, "bench.cfg")
	bench_puppet_cmd(g_Boss, "amx_cvar servercfgfile plain.cfg")
	get_cvar_string("servercfgfile", value, charsmax(value))
	ASSERT_STR_EQ(value, "plain.cfg")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_xvar_int, amx_xvar_float

public test_xvar_read_and_set()
{
	Start("g", "xvarwatch", "", "xvar_set")
}

public xvar_set()
{
	bench_puppet_cmd(g_Boss, "amx_xvar_int")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_xvar_int <xvar> [value]")
	bench_puppet_cmd(g_Boss, "amx_xvar_int nosuchxvar_qq")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Unknown xvar: nosuchxvar_qq")

	bench_puppet_cmd(g_Boss, "amx_xvar_int bench_xvar_num")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Xvar ^"bench_xvar_num^" is ^"42^"")
	bench_puppet_cmd(g_Boss, "amx_xvar_float bench_xvar_float")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Xvar ^"bench_xvar_float^" is ^"1.5")

	bench_puppet_cmd(g_Boss, "amx_xvar_int bench_xvar_num 7")
	ASSERT_EQ(bench_xvar_num, 7)
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Xvar ^"bench_xvar_num^" changed to ^"7^""), 1)
	ASSERT_EQ(CountPrint(g_Target, print_chat, "ADMIN boss:  set xvar bench_xvar_num to ^"7^""), 1)
	bench_puppet_cmd(g_Boss, "amx_xvar_float bench_xvar_float 2.25")
	ASSERT(bench_xvar_float == 2.25)
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Xvar ^"bench_xvar_float^" changed to ^"2.25")

	// A value that is not a number changes nothing.
	bench_puppet_cmd(g_Boss, "amx_xvar_int bench_xvar_num seven")
	bench_puppet_cmd(g_Boss, "amx_xvar_float bench_xvar_float half")
	ASSERT_EQ(bench_xvar_num, 7)
	ASSERT(bench_xvar_float == 2.25)
	bench_pass()
}

public test_xvar_add_protection()
{
	Start("g", "", "", "xvar_add")
}

public xvar_add()
{
	// Without ADMIN_RCON, "add" does nothing.
	bench_puppet_cmd(g_Boss, "amx_xvar_int add bench_xvar_locked")
	bench_puppet_cmd(g_Boss, "amx_xvar_int bench_xvar_locked 4")
	ASSERT_EQ(bench_xvar_locked, 4)

	// With it, the xvar is kept for ADMIN_RCON (for the rest of the map: the plugin cannot undo
	// it, so only this test's own xvar is used).
	SetFlags(g_Boss, "gl")
	bench_puppet_cmd(g_Boss, "amx_xvar_int add nosuchxvar_qq")
	bench_puppet_cmd(g_Boss, "amx_xvar_int add bench_xvar_locked")
	bench_puppet_cmd(g_Boss, "amx_xvar_int bench_xvar_locked 5")
	ASSERT_EQ(bench_xvar_locked, 5)
	SetFlags(g_Boss, "g")
	bench_puppet_cmd(g_Boss, "amx_xvar_int bench_xvar_locked 6")
	ASSERT_EQ(bench_xvar_locked, 5)
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] You have no access to that xvar")
	// Reading is still allowed.
	bench_puppet_cmd(g_Boss, "amx_xvar_int bench_xvar_locked")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Xvar ^"bench_xvar_locked^" is ^"5^"")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_plugins, amx_modules

public test_admin_lists_need_access()
{
	Start("d", "plainplayer", "", "lists_need_access")
}

public lists_need_access()
{
	// amx_plugins, amx_modules and amx_who need any admin flag, amx_last ADMIN_BAN, amx_pause
	// ADMIN_CVAR.
	bench_puppet_cmd(g_Target, "amx_plugins")
	bench_puppet_cmd(g_Target, "amx_modules")
	bench_puppet_cmd(g_Target, "amx_last")
	bench_puppet_cmd(g_Target, "amx_pause")
	ASSERT_EQ(CountPrint(g_Target, print_console, "You have no access to that command"), 4)
	ASSERT_EQ(bench_msg_count(g_Target, "TextMsg", "Currently loaded"), 0)
	ASSERT_EQ(bench_msg_count(g_Target, "TextMsg", "old connections saved"), 0)
	ASSERT_EQ(bench_msg_count(g_Target, "TextMsg", "pausing"), 0)
	bench_pass()
}

public test_plugins()
{
	Start("d", "", "", "plugins")
}

public plugins()
{
	new num = get_pluginsnum()
	ASSERT(num > 10)
	new file[64], name[64], version[32], author[32], status[32]
	get_plugin(0, file, charsmax(file), name, charsmax(name), version, charsmax(version), author, charsmax(author), status, charsmax(status))

	bench_puppet_cmd(g_Boss, "amx_plugins")
	ASSERT_MSG(g_Boss, "TextMsg", "----- Currently loaded plugins -----")
	ASSERT_MSG(g_Boss, "TextMsg", fmt("%-18.17s %-11.10s %-17.16s %-16.15s %-9.8s", "name", "version", "author", "file", "status"))
	ASSERT_MSG(g_Boss, "TextMsg", fmt("%-18.17s", name))
	ASSERT_MSG(g_Boss, "TextMsg", "10 plugins, ")
	ASSERT_MSG(g_Boss, "TextMsg", fmt("----- Entries 1 - 10 of %d -----", num))
	ASSERT_MSG(g_Boss, "TextMsg", "----- Use 'amx_plugins 11' for more -----")

	bench_puppet_cmd(g_Boss, "amx_plugins %d", num)
	ASSERT_MSG(g_Boss, "TextMsg", fmt("----- Entries %d - %d of %d -----", num, num, num))
	ASSERT_MSG(g_Boss, "TextMsg", "----- Use 'amx_plugins 1' for begin -----")

	// From the server console it hands over to "amxx plugins".
	server_cmd("amx_plugins")
	server_exec()
	ASSERT_MSG(0, "server", "Currently loaded plugins:")
	ASSERT_EQ(bench_msg_count(0, "server", "----- Currently loaded plugins -----"), 0)
	bench_pass()
}

public test_modules()
{
	Start("d", "", "", "modules")
}

public modules()
{
	new num = get_modulesnum()
	ASSERT(num > 0)
	bench_puppet_cmd(g_Boss, "amx_modules")
	ASSERT_MSG(g_Boss, "TextMsg", "Currently loaded modules:")
	ASSERT_MSG(g_Boss, "TextMsg", fmt("%d modules", num))
	new name[32], author[32], version[32], status
	for (new i = 0; i < num; i++)
	{
		get_module(i, name, charsmax(name), author, charsmax(author), version, charsmax(version), status)
		ASSERT_EQ(status, module_loaded)
		ASSERT_MSG(g_Boss, "TextMsg", fmt("%-23.22s", name))
	}
	ASSERT_EQ(bench_msg_count(g_Boss, "TextMsg", "bad load"), 0)
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_map, amx_extendmap, amx_cfg

public test_map_refuses_bad_names()
{
	Start("f", "", "", "map")
}

public map()
{
	bench_puppet_cmd(g_Boss, "amx_map")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_map <mapname>")
	bench_puppet_cmd(g_Boss, "amx_map nosuchmap_qq")
	bench_puppet_cmd(g_Boss, "amx_map ../ts/maps/ts_lobby")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Map with that name not found or map is invalid"), 2)
	bench_pass()
}

// A valid map: everyone is told, and two seconds later the level changes (to the same map here).
// This also runs the plugin's plugin_end.
public test_map_changes_level()
{
	bench_set_timeout(60.0)
	Start("f", "mapwatch", "", "map_change")
}

public map_change()
{
	new mapname[32]
	get_mapname(mapname, charsmax(mapname))
	bench_expect_map_change("map_changed")
	bench_puppet_cmd(g_Boss, "amx_map %s", mapname)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, fmt("ADMIN boss: changelevel %s", mapname)), 1)
	ASSERT_EQ(CountPrint(g_Target, print_chat, fmt("ADMIN boss: changelevel %s", mapname)), 1)
	// Not at once: the change is a task.
	ASSERT(is_user_connected(g_Target))
	// This copy of the file is gone after the change, so put everything back now.
	Restore()
}

public map_changed()
{
	// A new map: game time starts again.
	ASSERT(get_gametime() < 10.0)
	bench_pass()
}

public test_extendmap()
{
	Start("f", "", "", "extendmap")
}

public extendmap()
{
	set_cvar_float("mp_timelimit", 30.0)
	bench_puppet_cmd(g_Boss, "amx_extendmap")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_extendmap <number of minutes> - extend map")
	bench_puppet_cmd(g_Boss, "amx_extendmap 0")
	bench_puppet_cmd(g_Boss, "amx_extendmap -5")
	ASSERT_EQ(get_cvar_num("mp_timelimit"), 30)

	bench_puppet_cmd(g_Boss, "amx_extendmap 15")
	ASSERT_EQ(get_cvar_num("mp_timelimit"), 45)
	new mapname[32]
	get_mapname(mapname, charsmax(mapname))
	ASSERT_EQ(CountPrint(g_Boss, print_console, fmt("Map ^"%s^" has been extended for 15 minutes", mapname)), 1)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: extend map for 15 minutes"), 1)
	bench_pass()
}

public test_cfg()
{
	Start("h", "", "", "cfg")
}

public cfg()
{
	bench_puppet_cmd(g_Boss, "amx_cfg")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_cfg <filename>")
	bench_puppet_cmd(g_Boss, "amx_cfg nosuchfile_qq.cfg")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] File ^"nosuchfile_qq.cfg^" not found")

	new path[128]
	bench_fixture("admincmd_exec.cfg", path, charsmax(path))
	bench_puppet_cmd(g_Boss, "amx_cfg ^"%s^"", path)
	ASSERT_MSG(g_Boss, "TextMsg", fmt("[AMXX] Executing file ^"%s^"", path))
	ASSERT_MSG(g_Boss, "TextMsg", fmt("ADMIN boss: execute config %s", path))
	server_exec()
	new value[32]
	get_pcvar_string(g_Cvar, value, charsmax(value))
	ASSERT_STR_EQ(value, "fromcfg")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_pause and its pauseAck handshake. A puppet never runs the "pause;pauseAck" it is sent (the
// tests see it as a stufftext message), so the tests answer pauseAck themselves; the game is never
// actually paused.

public test_pause_handshake()
{
	Start("g", "", "", "pause_steps")
}

public pause_steps()
{
	set_cvar_float("pausable", 0.0)
	// pauseAck without an amx_pause first is left alone.
	bench_puppet_cmd(g_Boss, "pauseAck")
	ASSERT_EQ(bench_msg_count(g_Boss, "TextMsg", "Server"), 0)

	bench_puppet_cmd(g_Boss, "amx_pause")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] pausing"), 1)
	ASSERT_EQ(CountPrint(g_Boss, print_chat, "ADMIN boss: pause server"), 1)
	// The client is told to pause and answer.
	ASSERT_MSG(g_Boss, "stufftext", "pause;pauseAck")
	// pausable is turned on until the client answers.
	ASSERT_EQ(get_cvar_num("pausable"), 1)
	bench_puppet_cmd(g_Boss, "pauseAck")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Server paused")
	ASSERT_EQ(get_cvar_num("pausable"), 0)

	bench_puppet_cmd(g_Boss, "amx_pause")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] unpausing")
	ASSERT_MSG(g_Boss, "TextMsg", "ADMIN boss: unpause server")
	bench_puppet_cmd(g_Boss, "pauseAck")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Server unpaused")
	ASSERT_EQ(get_cvar_num("pausable"), 0)
	bench_pass()
}

public test_pause_from_server_console()
{
	// No players: nobody to send the pause through.
	ASSERT_EQ(find_player("h"), 0)
	set_cvar_float("pausable", 0.0)
	server_cmd("amx_pause")
	server_exec()
	ASSERT_EQ(get_cvar_num("pausable"), 0)
	ASSERT_MSG(0, "server", "[AMXX] Server was unable to pause the game. Real players on server are needed.")

	// With a player, the first one in the game is used.
	g_Target = bench_puppet("pausecarrier")
	ASSERT(g_Target > 0)
	server_cmd("amx_pause")
	server_exec()
	ASSERT_EQ(get_cvar_num("pausable"), 1)
	ASSERT_MSG(0, "server", "[AMXX] pausing")
	ASSERT_MSG(g_Target, "stufftext", "pause;pauseAck")
	bench_puppet_cmd(g_Target, "pauseAck")
	ASSERT_EQ(get_cvar_num("pausable"), 0)
	server_cmd("amx_pause")
	server_exec()
	bench_puppet_cmd(g_Target, "pauseAck")
	ASSERT_EQ(get_cvar_num("pausable"), 0)
	ASSERT_MSG(g_Target, "TextMsg", ": pause server")
	ASSERT_MSG(g_Target, "TextMsg", ": unpause server")
	bench_pass()
}

// cmdPause formats each player's "pause server" with the loop index (admincmd.sma:1149) where it
// means the player, so a player gets the language of whoever has index 0 (the server) instead of
// their own. A German player should read "Pause server" and "Fortsetzen server".
public test_pause_message_in_player_language()
{
	bench_describe("pause message in the player's language")
	Start("g", "", "", "pause_language")
}

public pause_language()
{
	bench_puppet_setinfo(g_Boss, "lang", "de")
	// Pause and unpause, so the plugin is left unpaused whatever the checks find.
	bench_puppet_cmd(g_Boss, "amx_pause")
	bench_puppet_cmd(g_Boss, "pauseAck")
	bench_puppet_cmd(g_Boss, "amx_pause")
	bench_puppet_cmd(g_Boss, "pauseAck")
	// The console replies are in German, so the player's language is set.
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] pausiert den Server...")
	// The two activity lines, in order.
	new got[2][128], BenchMsg:msg
	for (new i = 0; i < 2; i++)
	{
		msg = bench_msg_next(g_Boss, msg, "TextMsg", "ADMIN boss: ")
		ASSERT(msg != BenchMsg:0)
		bench_msg_text(msg, got[i], charsmax(got[]))
		trim(got[i])
	}
	if (!equal(got[0], "ADMIN boss: Pause server") || !equal(got[1], "ADMIN boss: Fortsetzen server"))
	{
		bench_fail("expected ^"ADMIN boss: Pause server^" then ^"ADMIN boss: Fortsetzen server^", received ^"%s^" then ^"%s^"", got[0], got[1])
		return
	}
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_rcon, amx_showrcon

public test_rcon()
{
	Start("l", "", "", "rcon")
}

public rcon()
{
	bench_puppet_cmd(g_Boss, "amx_rcon")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_rcon <command line>")
	bench_puppet_cmd(g_Boss, "amx_rcon bench_admincmd_cvar fromrcon")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Command line ^"bench_admincmd_cvar fromrcon^" sent to server console")
	server_exec()
	new value[32]
	get_pcvar_string(g_Cvar, value, charsmax(value))
	ASSERT_STR_EQ(value, "fromrcon")
	bench_pass()
}

public test_showrcon()
{
	Start("l", "", "", "showrcon")
}

public showrcon()
{
	bench_puppet_cmd(g_Boss, "amx_showrcon")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_showrcon <command line>")

	// Without an rcon password it is amx_rcon.
	set_cvar_string("rcon_password", "")
	bench_puppet_cmd(g_Boss, "amx_showrcon bench_admincmd_cvar showrcon1")
	server_exec()
	new value[32]
	get_pcvar_string(g_Cvar, value, charsmax(value))
	ASSERT_STR_EQ(value, "showrcon1")

	// With one, the client is given the password and sends the command itself; the server runs
	// nothing.
	set_cvar_string("rcon_password", "benchpw")
	bench_puppet_cmd(g_Boss, "amx_showrcon bench_admincmd_cvar showrcon2")
	server_exec()
	get_pcvar_string(g_Cvar, value, charsmax(value))
	ASSERT_STR_EQ(value, "showrcon1")
	ASSERT_EQ(bench_msg_count(g_Boss, "TextMsg", "showrcon2"), 0)
	ASSERT_MSG(g_Boss, "stufftext", "rcon_password benchpw")
	ASSERT_MSG(g_Boss, "stufftext", "rcon bench_admincmd_cvar showrcon2")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_nick

public test_nick()
{
	Start("e", "oldnick", "", "nick")
}

public nick()
{
	bench_puppet_cmd(g_Boss, "amx_nick oldnick")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_nick <name or #userid> <new nick>")
	bench_puppet_cmd(g_Boss, "amx_nick nosuchplayer newnick")
	ASSERT_MSG(g_Boss, "TextMsg", "Client with that name or userid not found")

	bench_puppet_cmd(g_Boss, "amx_nick oldnick newnick")
	ASSERT_EQ(CountPrint(g_Boss, print_console, "[AMXX] Changed nick of oldnick to ^"newnick^""), 1)
	ASSERT_EQ(CountPrint(g_Target, print_chat, "ADMIN boss: change nick of oldnick to ^"newnick^""), 1)
	bench_next("nick_changed", 0.1)
}

public nick_changed()
{
	new name[32]
	get_user_name(g_Target, name, charsmax(name))
	ASSERT_STR_EQ(name, "newnick")
	bench_pass()
}

// ---------------------------------------------------------------------------------------------
// amx_leave

public test_leave()
{
	Start("c", "", "", "leave")
}

public leave()
{
	set_user_info(g_Boss, "name", "[T]boss")
	g_Target = bench_puppet("[T]friend")
	g_Third = bench_puppet("immortal")
	g_Fourth = bench_puppet("outsider")
	g_Bot = bench_puppet("leavebot", true)
	ASSERT(g_Target > 0 && g_Third > 0 && g_Fourth > 0 && g_Bot > 0)
	SetFlags(g_Target, "z")
	SetFlags(g_Third, "a")
	SetFlags(g_Fourth, "z")
	bench_next("leave_named", 0.1)
}

public leave_named()
{
	new name[32]
	get_user_name(g_Boss, name, charsmax(name))
	ASSERT_STR_EQ(name, "[T]boss")
	// The rename logged the admin in again with the default access.
	SetFlags(g_Boss, "c")
	bench_puppet_cmd(g_Boss, "amx_leave")
	ASSERT_MSG(g_Boss, "TextMsg", "Usage:  amx_leave <tag> [tag] [tag] [tag]")

	bench_puppet_cmd(g_Boss, "amx_leave [T] nomatch")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Skipping ^"[T]boss^" (matching ^"[T]^")")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Skipping ^"[T]friend^" (matching ^"[T]^")")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Skipping ^"immortal^" (immunity)")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Kicking ^"outsider^"")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Kicking ^"leavebot^"")
	ASSERT_MSG(g_Boss, "TextMsg", "[AMXX] Kicked 2 clients")
	ASSERT_MSG(g_Boss, "TextMsg", "ADMIN [T]boss: leave [T] nomatch")
	g_UserId = get_user_userid(g_Fourth)
	bench_next("leave_done", 0.3)
}

public leave_done()
{
	ASSERT(is_user_connected(g_Target))
	ASSERT(is_user_connected(g_Third))
	ASSERT(!is_user_connected(g_Fourth) || get_user_userid(g_Fourth) != g_UserId)
	ASSERT_FALSE(is_user_connected(g_Bot))
	bench_pass()
}
