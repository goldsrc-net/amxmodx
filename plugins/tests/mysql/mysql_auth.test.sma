// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Logins through the MySQL module with each authentication plugin MariaDB 11 and MySQL 8.4 offer
// over TCP (host amxxbench-db, database amxxbench5). Each test makes a bench5_* user with one
// plugin, logs in with the right and a wrong password, and checks who the server says it is. On
// MariaDB the server plugins ed25519, caching_sha2_password and parsec are installed for the test
// when missing and uninstalled after it; table bench5_auth_installed records them first, so a run
// that stops halfway is put right by the next.
//

#include <amxmodx>
#include <sqlx>
#include <amxxbench>

#pragma loadlib mysql

#define DB_HOST "amxxbench-db"
#define DB_NAME "amxxbench5"

new Handle:g_Admin
new bool:g_MariaDB

new const g_Users[][] = {"bench5_auth", "bench5_noprivs"}
// MariaDB server plugins the tests need: library and plugin name.
new const g_Plugins[][][] =
{
	{"auth_ed25519", "ed25519"},
	{"auth_mysql_sha2", "caching_sha2_password"},
	{"auth_parsec", "parsec"}
}

public plugin_init()
{
	register_plugin("MySQL Authentication Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	SQL_SetAffinity("mysql")
}

public bench_setup()
{
	new errcode, error[128]
	new Handle:tuple = SQL_MakeDbTuple(DB_HOST, "bench", "bench", DB_NAME)
	g_Admin = SQL_Connect(tuple, errcode, error, charsmax(error))
	SQL_FreeHandle(tuple)
	if (!bench_check(g_Admin != Empty_Handle, "the bench user connects"))
		return
	g_MariaDB = Int("SELECT VERSION() LIKE '%%MariaDB%%'") == 1
	DropUsers()
	if (!g_MariaDB)
		return
	Exec("CREATE TABLE IF NOT EXISTS bench5_auth_installed (soname VARCHAR(64) PRIMARY KEY)")
	for (new i = 0; i < sizeof(g_Plugins); i++)
	{
		if (Int("SELECT COUNT(*) FROM information_schema.plugins WHERE plugin_name = '%s'", g_Plugins[i][1]) > 0)
			continue
		Exec("INSERT INTO bench5_auth_installed VALUES ('%s')", g_Plugins[i][0])
		Exec("INSTALL SONAME '%s'", g_Plugins[i][0])
	}
}

public bench_teardown()
{
	if (g_Admin == Empty_Handle)
		return
	DropUsers()
	if (g_MariaDB)
	{
		new Handle:query = SQL_PrepareQuery(g_Admin, "SELECT soname FROM bench5_auth_installed")
		new soname[64]
		if (SQL_Execute(query))
		{
			while (SQL_MoreResults(query))
			{
				SQL_ReadResult(query, 0, soname, charsmax(soname))
				Exec("UNINSTALL SONAME '%s'", soname)
				SQL_NextRow(query)
			}
		}
		SQL_FreeHandle(query)
		Exec("DROP TABLE IF EXISTS bench5_auth_installed")
	}
	SQL_FreeHandle(g_Admin)
	g_Admin = Empty_Handle
}

DropUsers()
{
	for (new i = 0; i < sizeof(g_Users); i++)
		Exec("DROP USER IF EXISTS %s", g_Users[i])
}

bool:Exec(const fmt[], any:...)
{
	new sql[256], error[128]
	vformat(sql, charsmax(sql), fmt, 2)
	new Handle:query = SQL_PrepareQuery(g_Admin, "%s", sql)
	new bool:ok = SQL_Execute(query) != 0
	if (!ok)
	{
		new code = SQL_QueryError(query, error, charsmax(error))
		bench_fail("%s: [%d] %s", sql, code, error)
	}
	SQL_FreeHandle(query)
	return ok
}

Int(const fmt[], any:...)
{
	new sql[256]
	vformat(sql, charsmax(sql), fmt, 2)
	new Handle:query = SQL_PrepareQuery(g_Admin, "%s", sql)
	new value = -1
	if (SQL_Execute(query) && SQL_MoreResults(query))
		value = SQL_ReadResult(query, 0)
	SQL_FreeHandle(query)
	return value
}

// Runs a CREATE USER, then lets the user read amxxbench5. Returns the error code (0: made).
CreateUser(const sql[], const user[], error[] = "", len = 0)
{
	new Handle:query = SQL_PrepareQuery(g_Admin, "%s", sql)
	new ok = SQL_Execute(query)
	new code = SQL_QueryError(query, error, len)
	SQL_FreeHandle(query)
	if (ok && !Exec("GRANT SELECT ON amxxbench5.* TO %s", user))
		return -1
	return ok ? 0 : code
}

// Logs in; returns the error code (0: logged in) and, on success, CURRENT_USER().
Login(const user[], const pass[], error[], len, who[] = "", wholen = 0, const db[] = DB_NAME)
{
	new Handle:tuple = SQL_MakeDbTuple(DB_HOST, user, pass, db)
	new errcode
	error[0] = 0
	new Handle:conn = SQL_Connect(tuple, errcode, error, len)
	SQL_FreeHandle(tuple)
	if (conn == Empty_Handle)
		return errcode
	new Handle:query = SQL_PrepareQuery(conn, "SELECT CURRENT_USER()")
	if (wholen && SQL_Execute(query) && SQL_MoreResults(query))
		SQL_ReadResult(query, 0, who, wholen)
	SQL_FreeHandle(query)
	SQL_FreeHandle(conn)
	return 0
}

bool:Denied(const user[], const error[])
{
	new expected[64]
	formatex(expected, charsmax(expected), "Access denied for user '%s'@", user)
	if (contain(error, expected) == 0 && contain(error, "(using password: YES)") > 0)
		return true
	bench_fail("expected ^"%s...(using password: YES)^", received ^"%s^"", expected, error)
	return false
}

// A plugin the server does not have: CREATE USER fails.
bool:NotLoaded(code, const error[], const plugin[])
{
	new expected[64]
	formatex(expected, charsmax(expected), "Plugin '%s' is not loaded", plugin)
	if (code == 1524 && equal(error, expected))
		return true
	bench_fail("expected [1524] ^"%s^", received [%d] ^"%s^"", expected, code, error)
	return false
}

public test_bench_user()
{
	new error[128], who[64]
	ASSERT_EQ(Login("bench", "bench", error, charsmax(error), who, charsmax(who)), 0)
	ASSERT_STR_EQ(who, "bench@%")
	new plugin[32]
	new Handle:query = SQL_PrepareQuery(g_Admin, "SELECT plugin FROM mysql.user WHERE user = 'bench'")
	ASSERT(SQL_Execute(query))
	SQL_ReadResult(query, 0, plugin, charsmax(plugin))
	SQL_FreeHandle(query)
	ASSERT_STR_EQ(plugin, g_MariaDB ? "mysql_native_password" : "caching_sha2_password")
	// The account given to this run.
	ASSERT_EQ(Login("bench5", "bench", error, charsmax(error), who, charsmax(who)), 0)
	ASSERT_STR_EQ(who, "bench5@%")
	bench_pass()
}

public test_mysql_native_password()
{
	new error[128], who[64]
	new code = CreateUser(g_MariaDB ? "CREATE USER bench5_auth IDENTIFIED VIA mysql_native_password USING PASSWORD('pw5')" : "CREATE USER bench5_auth IDENTIFIED WITH mysql_native_password BY 'pw5'", "bench5_auth", error, charsmax(error))
	if (!g_MariaDB)
	{
		// MySQL 8.4 ships it disabled.
		ASSERT(NotLoaded(code, error, "mysql_native_password"))
		bench_pass()
		return
	}
	ASSERT_EQ(code, 0)
	ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error), who, charsmax(who)), 0)
	ASSERT_STR_EQ(who, "bench5_auth@%")
	ASSERT_EQ(Login("bench5_auth", "bad", error, charsmax(error)), 1045)
	ASSERT(Denied("bench5_auth", error))
	bench_pass()
}

public test_caching_sha2_password()
{
	new error[128], who[64]
	new code = CreateUser(g_MariaDB ? "CREATE USER bench5_auth IDENTIFIED VIA caching_sha2_password USING PASSWORD('pw5')" : "CREATE USER bench5_auth IDENTIFIED WITH caching_sha2_password BY 'pw5'", "bench5_auth", error, charsmax(error))
	ASSERT_EQ(code, 0)
	if (g_MariaDB)
	{
		// Without TLS the password goes RSA-encrypted; MariaDB made no RSA keys for a plugin
		// installed at run time, and the module has no TLS option, so no login works.
		ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error)), 2061)
		ASSERT_STR_EQ(error, "Couldn't read RSA public key from server")
		bench_pass()
		return
	}
	// The first login takes the full exchange (the server's RSA key, no TLS), the second the
	// cached fast one.
	ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error), who, charsmax(who)), 0)
	ASSERT_STR_EQ(who, "bench5_auth@%")
	ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error), who, charsmax(who)), 0)
	ASSERT_EQ(Login("bench5_auth", "bad", error, charsmax(error)), 1045)
	ASSERT(Denied("bench5_auth", error))
	bench_pass()
}

public test_sha256_password()
{
	new error[128], who[64]
	new code = CreateUser(g_MariaDB ? "CREATE USER bench5_auth IDENTIFIED VIA sha256_password USING PASSWORD('pw5')" : "CREATE USER bench5_auth IDENTIFIED WITH sha256_password BY 'pw5'", "bench5_auth", error, charsmax(error))
	if (g_MariaDB)
	{
		ASSERT(NotLoaded(code, error, "sha256_password"))
		bench_pass()
		return
	}
	ASSERT_EQ(code, 0)
	ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error), who, charsmax(who)), 0)
	ASSERT_STR_EQ(who, "bench5_auth@%")
	ASSERT_EQ(Login("bench5_auth", "bad", error, charsmax(error)), 1045)
	ASSERT(Denied("bench5_auth", error))
	bench_pass()
}

public test_ed25519()
{
	new error[128], who[64]
	new code = CreateUser(g_MariaDB ? "CREATE USER bench5_auth IDENTIFIED VIA ed25519 USING PASSWORD('pw5')" : "CREATE USER bench5_auth IDENTIFIED WITH ed25519 BY 'pw5'", "bench5_auth", error, charsmax(error))
	if (!g_MariaDB)
	{
		ASSERT(NotLoaded(code, error, "ed25519"))
		bench_pass()
		return
	}
	ASSERT_EQ(code, 0)
	ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error), who, charsmax(who)), 0)
	ASSERT_STR_EQ(who, "bench5_auth@%")
	ASSERT_EQ(Login("bench5_auth", "bad", error, charsmax(error)), 1045)
	ASSERT(Denied("bench5_auth", error))
	bench_pass()
}

public test_parsec()
{
	new error[160]
	new code = CreateUser(g_MariaDB ? "CREATE USER bench5_auth IDENTIFIED VIA parsec USING PASSWORD('pw5')" : "CREATE USER bench5_auth IDENTIFIED WITH parsec BY 'pw5'", "bench5_auth", error, charsmax(error))
	if (!g_MariaDB)
	{
		ASSERT(NotLoaded(code, error, "parsec"))
		bench_pass()
		return
	}
	ASSERT_EQ(code, 0)
	// MariaDB Connector/C 3.1 has no parsec client plugin; it looks for one in its build's plugin
	// directory and gives up.
	ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error)), 1045)
	ASSERT(contain(error, "Plugin parsec could not be loaded: ") == 0)
	bench_pass()
}

public test_mysql_old_password()
{
	new error[256]
	new code = CreateUser(g_MariaDB ? "CREATE USER bench5_auth IDENTIFIED VIA mysql_old_password USING '78a36efa267f0461'" : "CREATE USER bench5_auth IDENTIFIED WITH mysql_old_password BY 'pw5'", "bench5_auth", error, charsmax(error))
	if (!g_MariaDB)
	{
		ASSERT(NotLoaded(code, error, "mysql_old_password"))
		bench_pass()
		return
	}
	ASSERT_EQ(code, 0)
	// The client has the plugin, the server refuses old hashes (secure_auth).
	ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error)), 1275)
	ASSERT(contain(error, "Server is running in --secure-auth mode, but 'bench5_auth'@") == 0)
	bench_pass()
}

public test_empty_password()
{
	new error[128], who[64]
	ASSERT_EQ(CreateUser("CREATE USER bench5_auth IDENTIFIED BY ''", "bench5_auth"), 0)
	ASSERT_EQ(Login("bench5_auth", "", error, charsmax(error), who, charsmax(who)), 0)
	ASSERT_STR_EQ(who, "bench5_auth@%")
	ASSERT_EQ(Login("bench5_auth", "pw5", error, charsmax(error)), 1045)
	ASSERT(Denied("bench5_auth", error))
	bench_pass()
}

public test_no_database_privilege()
{
	new error[128], who[64]
	ASSERT(Exec("CREATE USER bench5_noprivs IDENTIFIED BY 'pw5'"))
	ASSERT_EQ(Login("bench5_noprivs", "pw5", error, charsmax(error)), 1044)
	ASSERT_STR_EQ(error, "Access denied for user 'bench5_noprivs'@'%' to database 'amxxbench5'")
	// Without a database the login itself works.
	ASSERT_EQ(Login("bench5_noprivs", "pw5", error, charsmax(error), who, charsmax(who), ""), 0)
	ASSERT_STR_EQ(who, "bench5_noprivs@%")
	bench_pass()
}
