// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the MySQL module when the server drops a connection (MariaDB 11 or MySQL 8.4, host
// amxxbench-db, database amxxbench5): a connection from SQL_Connect killed from another one, timed
// out by wait_timeout or by the tuple's read timeout, and used again; a threaded query killed while
// it runs or timed out; a user whose account is locked and then unlocked, with a threaded query and
// with a connection that was open before the lock. The module turns on MYSQL_OPT_RECONNECT: these
// show what the query that finds the connection gone returns, and that the next one reconnects.
// The account is bench5_lock, made in setup and dropped in teardown.
//

#include <amxmodx>
#include <sqlx>
#include <amxxbench>

#pragma loadlib mysql

#define DB_HOST "amxxbench-db"
#define DB_NAME "amxxbench5"
#define LOST_TEXT "Lost connection to MySQL server during query"

new Handle:g_Tuple
new Handle:g_LockTuple
new Handle:g_Admin
new Handle:g_Db
new bool:g_MariaDB
new g_ConnId
new g_Cycle

// The last threaded query's outcome.
new g_ThreadDone
new g_ThreadFail
new g_ThreadErrnum
new g_ThreadError[128]
new g_ThreadValue[64]

public plugin_init()
{
	register_plugin("MySQL Lost Connection Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	SQL_SetAffinity("mysql")
	g_Tuple = SQL_MakeDbTuple(DB_HOST, "bench5", "bench", DB_NAME)
	g_LockTuple = SQL_MakeDbTuple(DB_HOST, "bench5_lock", "pw5", DB_NAME)
}

public plugin_end()
{
	SQL_FreeHandle(g_Tuple)
	SQL_FreeHandle(g_LockTuple)
}

public bench_setup()
{
	new errcode, error[128]
	new Handle:admin = SQL_MakeDbTuple(DB_HOST, "bench", "bench", DB_NAME)
	g_Admin = SQL_Connect(admin, errcode, error, charsmax(error))
	SQL_FreeHandle(admin)
	if (!bench_check(g_Admin != Empty_Handle, "the bench user connects"))
		return
	g_MariaDB = Int(g_Admin, "SELECT VERSION() LIKE '%%MariaDB%%'") == 1
	g_Db = Empty_Handle
	g_ThreadDone = 0
	// A user left by a run that stopped before teardown is dropped first.
	Exec(g_Admin, "DROP USER IF EXISTS bench5_lock")
	Exec(g_Admin, "CREATE USER bench5_lock IDENTIFIED BY 'pw5'")
	Exec(g_Admin, "GRANT SELECT ON amxxbench5.* TO bench5_lock")
}

public bench_teardown()
{
	if (g_Db != Empty_Handle)
		SQL_FreeHandle(g_Db)
	g_Db = Empty_Handle
	if (g_Admin == Empty_Handle)
		return
	Exec(g_Admin, "DROP USER IF EXISTS bench5_lock")
	SQL_FreeHandle(g_Admin)
	g_Admin = Empty_Handle
}

bool:Exec(Handle:db, const fmt[], any:...)
{
	new sql[256], error[128]
	vformat(sql, charsmax(sql), fmt, 3)
	new Handle:query = SQL_PrepareQuery(db, "%s", sql)
	new bool:ok = SQL_Execute(query) != 0
	if (!ok)
	{
		new code = SQL_QueryError(query, error, charsmax(error))
		bench_fail("%s: [%d] %s", sql, code, error)
	}
	SQL_FreeHandle(query)
	return ok
}

Int(Handle:db, const sql[])
{
	new Handle:query = SQL_PrepareQuery(db, "%s", sql)
	new value = -1
	if (SQL_Execute(query) && SQL_MoreResults(query))
		value = SQL_ReadResult(query, 0)
	SQL_FreeHandle(query)
	return value
}

// Runs sql on db: returns whether it worked, the error code and text, and the first row's columns
// joined with '|'.
bool:Try(Handle:db, const sql[], &code, error[], errlen, row[] = "", rowlen = 0)
{
	new Handle:query = SQL_PrepareQuery(db, "%s", sql)
	new bool:ok = SQL_Execute(query) != 0
	code = SQL_QueryError(query, error, errlen)
	if (rowlen)
		row[0] = 0
	if (ok && rowlen && SQL_MoreResults(query))
	{
		new value[64]
		for (new c = 0; c < SQL_NumColumns(query); c++)
		{
			if (SQL_IsNull(query, c))
				copy(value, charsmax(value), "NULL")
			else
				SQL_ReadResult(query, c, value, charsmax(value))
			format(row, rowlen, "%s%s%s", row, c ? "|" : "", value)
		}
	}
	SQL_FreeHandle(query)
	return ok
}

KillConnection(id)
{
	return Exec(g_Admin, "KILL %d", id)
}

// The error a locked account gets.
LockedCode()
{
	return g_MariaDB ? 4151 : 3118
}

bool:IsLockedText(const error[])
{
	if (g_MariaDB)
		return equal(error, "Access denied, this account is locked") != 0
	return contain(error, "Access denied for user 'bench5_lock'@") == 0 && contain(error, ". Account is locked.") > 0
}

public test_kill_then_reuse()
{
	new errcode, error[128], row[128]
	g_Db = SQL_Connect(g_Tuple, errcode, error, charsmax(error))
	ASSERT(g_Db != Empty_Handle)
	ASSERT(SQL_SetCharset(g_Db, "utf8mb4"))
	ASSERT(Exec(g_Db, "SET @bench5_var = 7"))

	// Three times over: the same handle keeps working.
	for (g_Cycle = 0; g_Cycle < 3; g_Cycle++)
	{
		g_ConnId = Int(g_Db, "SELECT CONNECTION_ID()")
		ASSERT(g_ConnId > 0)
		ASSERT(KillConnection(g_ConnId))

		// The first query finds the connection gone and fails; it is not retried.
		ASSERT_FALSE(Try(g_Db, "SELECT 1", errcode, error, charsmax(error)))
		ASSERT_EQ(errcode, 2013)
		ASSERT_STR_EQ(error, LOST_TEXT)

		// The next one reconnects: a new session, the character set set through the module
		// restored, the database kept, session variables gone.
		ASSERT(Try(g_Db, "SELECT CONNECTION_ID() <> 0, @@character_set_client, DATABASE(), @bench5_var", errcode, error, charsmax(error), row, charsmax(row)))
		ASSERT_EQ(errcode, 0)
		ASSERT_STR_EQ(row, "1|utf8mb4|amxxbench5|NULL")
		ASSERT(Int(g_Db, "SELECT CONNECTION_ID()") != g_ConnId)
	}
	bench_pass()
}

public test_kill_then_wait()
{
	new errcode, error[128]
	g_Db = SQL_Connect(g_Tuple, errcode, error, charsmax(error))
	ASSERT(g_Db != Empty_Handle)
	g_ConnId = Int(g_Db, "SELECT CONNECTION_ID()")
	ASSERT(KillConnection(g_ConnId))
	bench_next("kill_wait_reuse", 20.0)
}

public kill_wait_reuse()
{
	// Two real seconds later the first query still fails the same way.
	new errcode, error[128]
	ASSERT_FALSE(Try(g_Db, "SELECT 1", errcode, error, charsmax(error)))
	ASSERT_EQ(errcode, 2013)
	ASSERT_STR_EQ(error, LOST_TEXT)
	ASSERT(Try(g_Db, "SELECT 1", errcode, error, charsmax(error)))
	ASSERT(Int(g_Db, "SELECT CONNECTION_ID()") != g_ConnId)
	bench_pass()
}

public test_wait_timeout()
{
	new errcode, error[128]
	g_Db = SQL_Connect(g_Tuple, errcode, error, charsmax(error))
	ASSERT(g_Db != Empty_Handle)
	g_ConnId = Int(g_Db, "SELECT CONNECTION_ID()")
	ASSERT(Exec(g_Db, "SET SESSION wait_timeout = 1"))
	bench_next("wait_timeout_reuse", 25.0)
}

public wait_timeout_reuse()
{
	new errcode, error[256], row[64]
	new bool:ok = Try(g_Db, "SELECT CONNECTION_ID() <> 0, @@wait_timeout > 1", errcode, error, charsmax(error), row, charsmax(row))
	if (g_MariaDB)
	{
		// MariaDB closes the socket: the client sees it when it writes, reconnects and runs the
		// query.
		ASSERT(ok)
		ASSERT_STR_EQ(row, "1|1")
	}
	else
	{
		// MySQL 8 first sends an error packet, which the next query reads as its answer.
		ASSERT_FALSE(ok)
		ASSERT_EQ(errcode, 4031)
		ASSERT_STR_EQ(error, "The client was disconnected by the server because of inactivity. See wait_timeout and interactive_timeout for configuring this behavior.")
		ASSERT(Try(g_Db, "SELECT CONNECTION_ID() <> 0, @@wait_timeout > 1", errcode, error, charsmax(error), row, charsmax(row)))
		ASSERT_STR_EQ(row, "1|1")
	}
	ASSERT(Int(g_Db, "SELECT CONNECTION_ID()") != g_ConnId)
	bench_pass()
}

public test_read_timeout()
{
	// The tuple's timeout is also the read timeout: a query that takes longer is cut off.
	new Handle:tuple = SQL_MakeDbTuple(DB_HOST, "bench5", "bench", DB_NAME, 1)
	new errcode, error[128]
	g_Db = SQL_Connect(tuple, errcode, error, charsmax(error))
	SQL_FreeHandle(tuple)
	ASSERT(g_Db != Empty_Handle)
	g_ConnId = Int(g_Db, "SELECT CONNECTION_ID()")
	ASSERT_FALSE(Try(g_Db, "SELECT SLEEP(3)", errcode, error, charsmax(error)))
	ASSERT_EQ(errcode, 2013)
	ASSERT_STR_EQ(error, LOST_TEXT)
	// The next query reconnects.
	ASSERT_EQ(Int(g_Db, "SELECT 5"), 5)
	ASSERT(Int(g_Db, "SELECT CONNECTION_ID()") != g_ConnId)
	bench_pass()
}

public OnThread(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
	g_ThreadFail = failstate
	g_ThreadErrnum = errnum
	copy(g_ThreadError, charsmax(g_ThreadError), error)
	g_ThreadValue[0] = 0
	if (failstate == TQUERY_SUCCESS && SQL_MoreResults(query))
		SQL_ReadResult(query, 0, g_ThreadValue, charsmax(g_ThreadValue))
	g_ThreadDone++
}

public bool:ThreadBack(count)
{
	return g_ThreadDone >= count
}

new Handle:g_ShortTuple

public test_thread_read_timeout()
{
	g_ShortTuple = SQL_MakeDbTuple(DB_HOST, "bench5", "bench", DB_NAME, 1)
	SQL_ThreadQuery(g_ShortTuple, "OnThread", "SELECT SLEEP(3)")
	bench_wait_until("ThreadBack", "thread_read_timeout_back", 50.0, 1)
}

public thread_read_timeout_back()
{
	ASSERT_EQ(g_ThreadFail, TQUERY_QUERY_FAILED)
	ASSERT_EQ(g_ThreadErrnum, 2013)
	ASSERT_STR_EQ(g_ThreadError, LOST_TEXT)
	// A threaded query has a connection of its own: the next one is unaffected.
	SQL_ThreadQuery(g_ShortTuple, "OnThread", "SELECT 'after'")
	bench_wait_until("ThreadBack", "thread_read_timeout_after", 10.0, 2)
}

public thread_read_timeout_after()
{
	SQL_FreeHandle(g_ShortTuple)
	ASSERT_EQ(g_ThreadFail, TQUERY_SUCCESS)
	ASSERT_STR_EQ(g_ThreadValue, "after")
	bench_pass()
}

public test_thread_killed()
{
	SQL_ThreadQuery(g_Tuple, "OnThread", "SELECT SLEEP(5), 'bench5-killed-thread'")
	bench_set_timeout(120.0)
	bench_wait_until("ThreadRunning", "thread_kill", 30.0)
}

// The worker's connection, found by the query it runs.
public ThreadRunning()
{
	g_ConnId = Int(g_Admin, "SELECT id FROM information_schema.processlist WHERE info LIKE 'SELECT SLEEP(5), ''bench5-killed-thread''%'")
	return g_ConnId > 0
}

public thread_kill()
{
	ASSERT(KillConnection(g_ConnId))
	bench_wait_until("ThreadBack", "thread_killed_back", 30.0, 1)
}

public thread_killed_back()
{
	ASSERT_EQ(g_ThreadFail, TQUERY_QUERY_FAILED)
	ASSERT_EQ(g_ThreadErrnum, 2013)
	ASSERT_STR_EQ(g_ThreadError, LOST_TEXT)
	SQL_ThreadQuery(g_Tuple, "OnThread", "SELECT 'after'")
	bench_wait_until("ThreadBack", "thread_killed_after", 10.0, 2)
}

public thread_killed_after()
{
	ASSERT_EQ(g_ThreadFail, TQUERY_SUCCESS)
	ASSERT_STR_EQ(g_ThreadValue, "after")
	bench_pass()
}

public test_locked_account_thread()
{
	ASSERT(Exec(g_Admin, "ALTER USER bench5_lock ACCOUNT LOCK"))
	SQL_ThreadQuery(g_LockTuple, "OnThread", "SELECT 'locked'")
	bench_wait_until("ThreadBack", "locked_thread_back", 10.0, 1)
}

public locked_thread_back()
{
	ASSERT_EQ(g_ThreadFail, TQUERY_CONNECT_FAILED)
	ASSERT_EQ(g_ThreadErrnum, LockedCode())
	if (!IsLockedText(g_ThreadError))
	{
		bench_fail("unexpected error text ^"%s^"", g_ThreadError)
		return
	}
	ASSERT(Exec(g_Admin, "ALTER USER bench5_lock ACCOUNT UNLOCK"))
	SQL_ThreadQuery(g_LockTuple, "OnThread", "SELECT 'unlocked'")
	bench_wait_until("ThreadBack", "unlocked_thread_back", 10.0, 2)
}

public unlocked_thread_back()
{
	ASSERT_EQ(g_ThreadFail, TQUERY_SUCCESS)
	ASSERT_EQ(g_ThreadErrnum, 0)
	ASSERT_STR_EQ(g_ThreadValue, "unlocked")
	bench_pass()
}

public test_locked_account_connection()
{
	new errcode, error[128], row[64]
	g_Db = SQL_Connect(g_LockTuple, errcode, error, charsmax(error))
	ASSERT(g_Db != Empty_Handle)
	g_ConnId = Int(g_Db, "SELECT CONNECTION_ID()")
	ASSERT(Exec(g_Admin, "ALTER USER bench5_lock ACCOUNT LOCK"))

	// A session open before the lock goes on.
	ASSERT(Try(g_Db, "SELECT CONNECTION_ID()", errcode, error, charsmax(error), row, charsmax(row)))
	ASSERT_EQ(str_to_num(row), g_ConnId)

	// Killed: the first query is lost, every reconnect after it is refused.
	ASSERT(KillConnection(g_ConnId))
	ASSERT_FALSE(Try(g_Db, "SELECT 1", errcode, error, charsmax(error)))
	ASSERT_EQ(errcode, 2013)
	ASSERT_STR_EQ(error, LOST_TEXT)
	for (new i = 0; i < 2; i++)
	{
		ASSERT_FALSE(Try(g_Db, "SELECT 1", errcode, error, charsmax(error)))
		ASSERT_EQ(errcode, LockedCode())
		ASSERT(IsLockedText(error))
	}

	// Unlocked: the next query reconnects on the same handle.
	ASSERT(Exec(g_Admin, "ALTER USER bench5_lock ACCOUNT UNLOCK"))
	ASSERT(Try(g_Db, "SELECT CURRENT_USER(), DATABASE()", errcode, error, charsmax(error), row, charsmax(row)))
	ASSERT_EQ(errcode, 0)
	ASSERT_STR_EQ(row, "bench5_lock@%|amxxbench5")
	ASSERT(Int(g_Db, "SELECT CONNECTION_ID()") != g_ConnId)
	bench_pass()
}
