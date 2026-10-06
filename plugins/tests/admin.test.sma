// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for admin.sma (Admin Base): loading users.ini, logging players in by auth ID, name and
// password, amx_mode, amx_default_access and amx_addadmin. Each test writes its own users.ini; the
// server's own is put back after every test.
//

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

new g_UsersFile[PLATFORM_MAX_PATH]
new g_SavedUsers[PLATFORM_MAX_PATH]
new g_Puppet

public plugin_init()
{
	register_plugin("Admin Base Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	bench_coverage_ignore("admin.sma", 154, 154, "a connected player without an auth ID: before Steam validates them, which puppets never are")
	bench_coverage_ignore("admin.sma", 230, 230, "an address lookup only runs for text that is not an address, so it never finds a player")
	bench_coverage_ignore("admin.sma", 326, 326, "users.ini existing but not writable, which a plugin cannot arrange")
	bench_coverage_ignore("admin.sma", 792, 792, "listen servers only")
}

public bench_setup()
{
	get_configsdir(g_UsersFile, charsmax(g_UsersFile))
	formatex(g_SavedUsers, charsmax(g_SavedUsers), "%s/users.ini.bench", g_UsersFile)
	add(g_UsersFile, charsmax(g_UsersFile), "/users.ini")
	// A saved copy already there is the server's own, left by a run that stopped before teardown:
	// keep it, and drop the users.ini that run wrote.
	if (file_exists(g_SavedUsers))
		delete_file(g_UsersFile)
	else
		rename_file(g_UsersFile, g_SavedUsers, 1)
	g_Puppet = 0
}

public bench_teardown()
{
	delete_file(g_UsersFile)
	rename_file(g_SavedUsers, g_UsersFile, 1)
	set_cvar_num("amx_mode", 1)
	set_cvar_string("amx_default_access", "")
	Reload()
}

// Writes users.ini from lines separated by '|'.
WriteUsers(const lines[])
{
	new f = fopen(g_UsersFile, "wt")
	new line[128], rest[512]
	copy(rest, charsmax(rest), lines)
	while (rest[0])
	{
		strtok(rest, line, charsmax(line), rest, charsmax(rest), '|')
		fprintf(f, "%s^n", line)
	}
	fclose(f)
}

Reload()
{
	server_cmd("amx_reloadadmins")
	server_exec()
}

public test_reload_reads_every_account()
{
	WriteUsers("; comment|^"STEAM_0:0:1001^" ^"^" ^"abc^" ^"ce^"|^"Someone^" ^"pw^" ^"d^" ^"a^"|^"10.0.0.^" ^"^" ^"e^" ^"de^"|^"short^"")
	Reload()
	// The comment and the one-field line are skipped.
	ASSERT_EQ(admins_num(), 3)
	bench_pass()
}

public test_auth_id_login_on_join()
{
	WriteUsers("^"STEAM_0:0:1001^" ^"^" ^"abc^" ^"ce^"")
	Reload()
	g_Puppet = bench_puppet("steamadmin", false, "STEAM_0:0:1001")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "auth_id_checked", 5.0, read_flags("abc"))
}

public has_flags(flags)
{
	return is_user_connected(g_Puppet) && get_user_flags(g_Puppet) == flags
}

public auth_id_checked(flags)
{
	new expected = read_flags("abc")
	ASSERT_EQ(get_user_flags(g_Puppet), expected)
	bench_pass()
}

public test_unlisted_player_gets_default_access()
{
	WriteUsers("^"STEAM_0:0:9999^" ^"^" ^"abc^" ^"ce^"")
	set_cvar_string("amx_default_access", "m")
	Reload()
	g_Puppet = bench_puppet("nobody")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "default_access_checked", 5.0, read_flags("m"))
}

public default_access_checked(flags)
{
	new expected = read_flags("m")
	ASSERT_EQ(get_user_flags(g_Puppet), expected)
	bench_pass()
}

public test_unlisted_player_gets_user_flag()
{
	WriteUsers("^"STEAM_0:0:9999^" ^"^" ^"abc^" ^"ce^"")
	Reload()
	g_Puppet = bench_puppet("plainuser")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "user_flag_checked", 5.0, ADMIN_USER)
}

public user_flag_checked(flags)
{
	ASSERT_EQ(get_user_flags(g_Puppet), ADMIN_USER)
	bench_pass()
}

new g_KickUserId

public test_amx_mode_2_kicks_unlisted_players()
{
	WriteUsers("^"STEAM_0:0:9999^" ^"^" ^"abc^" ^"ce^"")
	Reload()
	set_cvar_num("amx_mode", 2)
	g_Puppet = bench_puppet("intruder")
	ASSERT(g_Puppet > 0)
	g_KickUserId = get_user_userid(g_Puppet)
	bench_wait_until("puppet_gone", "kicked_checked", 5.0)
}

public puppet_gone()
{
	return !is_user_connected(g_Puppet) || get_user_userid(g_Puppet) != g_KickUserId
}

public kicked_checked()
{
	bench_pass()
}

public test_wrong_password_with_kick_flag()
{
	// Name account, password required (no "e"), kick on a wrong one ("a").
	WriteUsers("^"pwuser^" ^"secret^" ^"d^" ^"a^"")
	Reload()
	g_Puppet = bench_puppet("pwuser")
	ASSERT(g_Puppet > 0)
	g_KickUserId = get_user_userid(g_Puppet)
	bench_wait_until("puppet_gone", "kicked_checked", 5.0)
}

public test_name_tag_case_insensitive()
{
	// "b": the name only has to contain the tag; no "k": any case.
	WriteUsers("^"[TAG]^" ^"^" ^"i^" ^"be^"")
	Reload()
	g_Puppet = bench_puppet("me[tag]")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "tag_checked", 5.0, read_flags("i"))
}

public tag_checked(flags)
{
	new expected = read_flags("i")
	ASSERT_EQ(get_user_flags(g_Puppet), expected)
	bench_pass()
}

public test_name_case_sensitive_mismatch()
{
	// "k": case matters, so "Exact" does not log in "exact".
	WriteUsers("^"Exact^" ^"^" ^"i^" ^"ek^"")
	Reload()
	g_Puppet = bench_puppet("exact")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "case_checked", 5.0, ADMIN_USER)
}

public case_checked(flags)
{
	ASSERT_EQ(get_user_flags(g_Puppet), ADMIN_USER)
	bench_pass()
}

public test_addadmin_steamid_appends_account()
{
	WriteUsers("; empty")
	Reload()
	server_cmd("amx_addadmin ^"STEAM_0:0:4242^" abc")
	server_exec()
	ASSERT_EQ(admins_num(), 1)
	new auth[44]
	admins_lookup(0, AdminProp_Auth, auth, charsmax(auth))
	ASSERT_STR_EQ(auth, "STEAM_0:0:4242")
	ASSERT_EQ(admins_lookup(0, AdminProp_Access), read_flags("abc"))
	ASSERT_EQ(admins_lookup(0, AdminProp_Flags), read_flags("ce"))
	bench_pass()
}

public test_addadmin_twice_does_not_duplicate()
{
	WriteUsers("; empty")
	Reload()
	server_cmd("amx_addadmin ^"STEAM_0:0:4242^" abc")
	server_exec()
	server_cmd("amx_addadmin ^"STEAM_0:0:4242^" abc")
	server_exec()
	ASSERT_EQ(admins_num(), 1)
	bench_pass()
}

public test_addadmin_player_by_name()
{
	WriteUsers("; empty")
	Reload()
	g_Puppet = bench_puppet("namedadmin")
	ASSERT(g_Puppet > 0)
	bench_next("addadmin_by_name", 0.5)
}

public addadmin_by_name()
{
	server_cmd("amx_addadmin namedadmin abc secret name")
	server_exec()
	ASSERT_EQ(admins_num(), 1)
	new auth[44], password[32]
	admins_lookup(0, AdminProp_Auth, auth, charsmax(auth))
	admins_lookup(0, AdminProp_Password, password, charsmax(password))
	ASSERT_STR_EQ(auth, "namedadmin")
	ASSERT_STR_EQ(password, "secret")
	ASSERT_EQ(admins_lookup(0, AdminProp_Flags), read_flags("a"))
	bench_pass()
}

public test_addadmin_unknown_type_adds_nothing()
{
	WriteUsers("; empty")
	Reload()
	server_cmd("amx_addadmin someone abc pw bogus")
	server_exec()
	ASSERT_EQ(admins_num(), 0)
	bench_pass()
}

public test_addadmin_ip_address()
{
	WriteUsers("; empty")
	Reload()
	server_cmd("amx_addadmin 10.1.2.3 abc ^"^" ip")
	server_exec()
	ASSERT_EQ(admins_num(), 1)
	ASSERT_EQ(admins_lookup(0, AdminProp_Flags), read_flags("de"))
	bench_pass()
}

public test_addadmin_steam_type_looks_up_player()
{
	WriteUsers("; empty")
	Reload()
	g_Puppet = bench_puppet("lookupme", false, "STEAM_0:0:5150")
	ASSERT(g_Puppet > 0)
	bench_next("addadmin_steam_lookup", 0.2)
}

public addadmin_steam_lookup()
{
	server_cmd("amx_addadmin lookupme abc ^"^" steam")
	server_exec()
	ASSERT_EQ(admins_num(), 1)
	new auth[44]
	admins_lookup(0, AdminProp_Auth, auth, charsmax(auth))
	ASSERT_STR_EQ(auth, "STEAM_0:0:5150")
	bench_pass()
}

public test_addadmin_connected_auth_id()
{
	WriteUsers("; empty")
	Reload()
	g_Puppet = bench_puppet("connectedadmin", false, "STEAM_0:0:5151")
	ASSERT(g_Puppet > 0)
	bench_next("addadmin_connected", 0.2)
}

public addadmin_connected()
{
	server_cmd("amx_addadmin ^"STEAM_0:0:5151^" abc")
	server_exec()
	ASSERT_EQ(admins_num(), 1)
	// The connected player gets the access right away.
	new expected = read_flags("abc")
	ASSERT_EQ(get_user_flags(g_Puppet), expected)
	bench_pass()
}

public test_addadmin_name_of_absent_player()
{
	WriteUsers("; empty")
	Reload()
	server_cmd("amx_addadmin ghost abc ^"^" name")
	server_exec()
	ASSERT_EQ(admins_num(), 1)
	new auth[44]
	admins_lookup(0, AdminProp_Auth, auth, charsmax(auth))
	ASSERT_STR_EQ(auth, "ghost")
	bench_pass()
}

public test_addadmin_malformed_ip_is_looked_up()
{
	WriteUsers("; empty")
	Reload()
	// An empty octet, then too many octets: neither is an address, and no player has them.
	server_cmd("amx_addadmin 1..2.3 abc ^"^" ip")
	server_exec()
	server_cmd("amx_addadmin 1.2.3.4.5 abc ^"^" ip")
	server_exec()
	ASSERT_EQ(admins_num(), 0)
	bench_pass()
}

public test_addadmin_without_users_ini()
{
	delete_file(g_UsersFile)
	server_cmd("amx_addadmin ^"STEAM_0:0:4242^" abc")
	server_exec()
	ASSERT_FALSE(file_exists(g_UsersFile))
	bench_pass()
}

public test_addadmin_skips_malformed_lines()
{
	// The three-field line is skipped when looking for a duplicate.
	WriteUsers("^"STEAM_0:0:4242^" ^"^" ^"abc^"")
	Reload()
	server_cmd("amx_addadmin ^"STEAM_0:0:4242^" abc")
	server_exec()
	ASSERT_EQ(admins_num(), 2)
	bench_pass()
}

public test_ip_prefix_account()
{
	// Puppets connect from 127.0.0.1; "127.0.0." matches the prefix.
	WriteUsers("^"127.0.0.^" ^"^" ^"j^" ^"de^"")
	Reload()
	g_Puppet = bench_puppet("prefixed")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "ip_checked", 5.0, read_flags("j"))
}

public ip_checked(flags)
{
	ASSERT_EQ(get_user_flags(g_Puppet), flags)
	bench_pass()
}

public test_ip_exact_account()
{
	WriteUsers("^"127.0.0.1^" ^"^" ^"j^" ^"de^"")
	Reload()
	g_Puppet = bench_puppet("exactip")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "ip_checked", 5.0, read_flags("j"))
}

public test_name_tag_case_sensitive()
{
	WriteUsers("^"[Tag]^" ^"^" ^"i^" ^"bek^"")
	Reload()
	g_Puppet = bench_puppet("x[Tag]x")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "tag_checked", 5.0, read_flags("i"))
}

public test_name_exact_case_sensitive()
{
	WriteUsers("^"Exact^" ^"^" ^"i^" ^"ek^"")
	Reload()
	g_Puppet = bench_puppet("Exact")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "tag_checked", 5.0, read_flags("i"))
}

public test_reload_denied_without_access()
{
	WriteUsers("^"STEAM_0:0:1001^" ^"^" ^"abc^" ^"ce^"")
	Reload()
	g_Puppet = bench_puppet("noaccess")
	ASSERT(g_Puppet > 0)
	bench_next("try_reload", 0.2)
}

public try_reload()
{
	// Without "h" the command is refused, so the account written now is not loaded.
	WriteUsers("^"STEAM_0:0:1001^" ^"^" ^"abc^" ^"ce^"|^"STEAM_0:0:1002^" ^"^" ^"abc^" ^"ce^"")
	bench_puppet_cmd(g_Puppet, "amx_reloadadmins")
	ASSERT_EQ(admins_num(), 1)
	bench_puppet_cmd(g_Puppet, "amx_addadmin ^"STEAM_0:0:7^" abc")
	ASSERT_EQ(admins_num(), 1)
	bench_pass()
}

public test_reload_by_admin_player()
{
	WriteUsers("^"STEAM_0:0:3003^" ^"^" ^"h^" ^"ce^"")
	Reload()
	g_Puppet = bench_puppet("cfgadmin", false, "STEAM_0:0:3003")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "admin_reloads", 5.0, read_flags("h"))
}

public admin_reloads(flags)
{
	bench_puppet_cmd(g_Puppet, "amx_reloadadmins")
	ASSERT_EQ(admins_num(), 1)
	WriteUsers("^"STEAM_0:0:3003^" ^"^" ^"h^" ^"ce^"|^"STEAM_0:0:3004^" ^"^" ^"h^" ^"ce^"")
	bench_puppet_cmd(g_Puppet, "amx_reloadadmins")
	ASSERT_EQ(admins_num(), 2)
	bench_pass()
}

public test_password_login()
{
	// A name account with a password and no kick flag: a wrong password only says so.
	WriteUsers("^"pwplayer^" ^"secret^" ^"d^" ^"^"")
	Reload()
	g_Puppet = bench_puppet("pwplayer")
	ASSERT(g_Puppet > 0)
	bench_wait_until("told_invalid_password", "send_password", 5.0)
}

public told_invalid_password()
{
	return bench_msg_last(g_Puppet, "console", "Invalid Password!") != BenchMsg:0
}

public send_password()
{
	ASSERT_EQ(get_user_flags(g_Puppet), 0)
	bench_puppet_setinfo(g_Puppet, "_pw", "secret")
	Reload()
	new expected = read_flags("d")
	ASSERT_EQ(get_user_flags(g_Puppet), expected)
	ASSERT_MSG(g_Puppet, "console", "Password accepted")
	ASSERT_MSG(g_Puppet, "console", "Privileges set")
	bench_pass()
}

public test_rename_logs_in()
{
	WriteUsers("^"Renamed^" ^"^" ^"i^" ^"e^"")
	Reload()
	g_Puppet = bench_puppet("before")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "rename", 5.0, ADMIN_USER)
}

public rename(flags)
{
	bench_puppet_setinfo(g_Puppet, "name", "Renamed")
	new expected = read_flags("i")
	ASSERT_EQ(get_user_flags(g_Puppet), expected)
	bench_pass()
}

public test_rename_away_from_case_sensitive_name()
{
	WriteUsers("^"Exact^" ^"^" ^"i^" ^"ek^"")
	Reload()
	g_Puppet = bench_puppet("Exact")
	ASSERT(g_Puppet > 0)
	bench_wait_until("has_flags", "rename_away", 5.0, read_flags("i"))
}

public rename_away(flags)
{
	bench_puppet_setinfo(g_Puppet, "name", "exact")
	ASSERT_EQ(get_user_flags(g_Puppet), ADMIN_USER)
	bench_pass()
}
