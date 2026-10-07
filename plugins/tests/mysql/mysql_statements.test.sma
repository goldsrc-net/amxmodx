// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the MySQL module with queries of several statements and long queries, against a live
// server (MariaDB 11 or MySQL 8.4, host amxxbench-db, database amxxbench5): statements without a
// result set before, between and after result sets, errors in later statements, executing such a
// query again, and queries longer than the 4 KB that formatting allows. After each, the connection
// must still answer the next query. Table bench5_st is dropped before and after each test.
//

#include <amxmodx>
#include <sqlx>
#include <amxxbench>

#pragma loadlib mysql

#define DB_HOST "amxxbench-db"
#define DB_NAME "amxxbench5"

new Handle:g_Tuple
new Handle:g_Db

public plugin_init()
{
	register_plugin("MySQL Multiple Statement Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	SQL_SetAffinity("mysql")
	g_Tuple = SQL_MakeDbTuple(DB_HOST, "bench5", "bench", DB_NAME)
}

public plugin_end()
{
	SQL_FreeHandle(g_Tuple)
}

public bench_setup()
{
	new errcode, error[128]
	g_Db = SQL_Connect(g_Tuple, errcode, error, charsmax(error))
	if (bench_check(g_Db != Empty_Handle, "bench5 connects"))
		Exec("DROP TABLE IF EXISTS bench5_st")
}

public bench_teardown()
{
	if (g_Db == Empty_Handle)
		return
	SQL_FreeHandle(g_Db)
	// From a fresh connection, in case a test left this one unusable.
	new errcode, error[128]
	g_Db = SQL_Connect(g_Tuple, errcode, error, charsmax(error))
	if (g_Db != Empty_Handle)
	{
		Exec("DROP TABLE IF EXISTS bench5_st")
		SQL_FreeHandle(g_Db)
	}
	g_Db = Empty_Handle
}

bool:Exec(const sql[])
{
	new error[128]
	new Handle:query = SQL_PrepareQuery(g_Db, "%s", sql)
	new bool:ok = SQL_Execute(query) != 0
	if (!ok)
	{
		new code = SQL_QueryError(query, error, charsmax(error))
		bench_fail("%s: [%d] %s", sql, code, error)
	}
	SQL_FreeHandle(query)
	return ok
}

// The connection still answers: SELECT n returns n.
bool:InSync(n)
{
	new error[128]
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT %d", n)
	new ok = SQL_Execute(query), value = -1
	new code = SQL_QueryError(query, error, charsmax(error))
	if (ok && SQL_MoreResults(query))
		value = SQL_ReadResult(query, 0)
	SQL_FreeHandle(query)
	if (value == n)
		return true
	bench_fail("SELECT %d on the same connection: [%d] %s", n, code, error)
	return false
}

public test_no_result_set_first()
{
	// Statements without a result set and nothing after them.
	ASSERT(Exec("CREATE TABLE bench5_st (id INT AUTO_INCREMENT PRIMARY KEY, v INT); DO 0"))
	ASSERT(InSync(1))
	ASSERT(Exec("DO 1; DO 2"))
	ASSERT(InSync(2))

	// The first result set after them is the query's; the insert id and affected rows are the
	// first statement's.
	new Handle:query = SQL_PrepareQuery(g_Db, "INSERT INTO bench5_st (v) VALUES (5), (6); DO 0; SELECT id, v FROM bench5_st ORDER BY id")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_GetInsertId(query), 1)
	ASSERT_EQ(SQL_AffectedRows(query), 2)
	ASSERT_EQ(SQL_NumResults(query), 2)
	ASSERT_EQ(SQL_NumColumns(query), 2)
	SQL_NextRow(query)
	ASSERT_EQ(SQL_ReadResult(query, 1), 6)
	ASSERT_EQ(SQL_NextResultSet(query), false)
	SQL_FreeHandle(query)
	ASSERT(InSync(3))

	// The usual INSERT, then its id.
	query = SQL_PrepareQuery(g_Db, "INSERT INTO bench5_st (v) VALUES (7); SELECT LAST_INSERT_ID()")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_GetInsertId(query), 3)
	ASSERT_EQ(SQL_ReadResult(query, 0), 3)
	SQL_FreeHandle(query)
	ASSERT(InSync(4))
	bench_pass()
}

public test_error_after_no_result_set()
{
	// The statements before the error ran; the query fails with the error.
	ASSERT(Exec("CREATE TABLE bench5_st (v INT)"))
	new Handle:query = SQL_PrepareQuery(g_Db, "INSERT INTO bench5_st VALUES (1); SELEC 2")
	ASSERT_EQ(SQL_Execute(query), 0)
	new error[128]
	ASSERT_EQ(SQL_QueryError(query, error, charsmax(error)), 1064)
	ASSERT(contain(error, "You have an error in your SQL syntax") == 0)
	ASSERT_EQ(SQL_NumResults(query), 0)
	ASSERT_EQ(SQL_AffectedRows(query), 0)
	SQL_FreeHandle(query)
	ASSERT(InSync(1))
	new Handle:count = SQL_PrepareQuery(g_Db, "SELECT COUNT(*) FROM bench5_st")
	ASSERT(SQL_Execute(count))
	ASSERT_EQ(SQL_ReadResult(count, 0), 1)
	SQL_FreeHandle(count)
	bench_pass()
}

public test_next_result_set_past_no_result_set()
{
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT 1; DO 0; DO 1; SELECT 3, 4; DO 2")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_ReadResult(query, 0), 1)
	ASSERT_EQ(SQL_NextResultSet(query), true)
	ASSERT_EQ(SQL_NumColumns(query), 2)
	ASSERT_EQ(SQL_ReadResult(query, 1), 4)
	ASSERT_EQ(SQL_NextResultSet(query), false)
	new error[16] = "x"
	ASSERT_EQ(SQL_QueryError(query, error, charsmax(error)), 0)
	ASSERT_STR_EQ(error, "")
	SQL_FreeHandle(query)
	ASSERT(InSync(5))
	bench_pass()
}

public test_error_in_later_statement()
{
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT 1; DO 0; SELEC 2")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_NextResultSet(query), false)
	new error[128]
	new code = SQL_QueryError(query, error, charsmax(error))
	SQL_FreeHandle(query)
	ASSERT_EQ(code, 1064)
	ASSERT(contain(error, "You have an error in your SQL syntax") == 0)
	ASSERT(InSync(6))
	bench_pass()
}

public test_execute_again_with_results_left()
{
	// Executed again before its second result set was read.
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT 1; SELECT 2")
	ASSERT(SQL_Execute(query))
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_ReadResult(query, 0), 1)
	ASSERT_EQ(SQL_NextResultSet(query), true)
	ASSERT_EQ(SQL_ReadResult(query, 0), 2)
	SQL_FreeHandle(query)
	ASSERT(InSync(7))
	bench_pass()
}

public test_long_query()
{
	static sql[16001], text[15001], back[16001]
	for (new i = 0; i < 15000; i++)
		text[i] = 'a' + i % 26
	text[15000] = 0
	formatex(sql, charsmax(sql), "SELECT LENGTH('%s')", text)

	// Given as "%s", or with no format specifier, the query is read as it is.
	new Handle:query = SQL_PrepareQuery(g_Db, "%s", sql)
	SQL_GetQueryString(query, back, charsmax(back))
	ASSERT_EQ(strlen(back), strlen(sql))
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_ReadResult(query, 0), 15000)
	SQL_FreeHandle(query)

	query = SQL_PrepareQuery(g_Db, sql)
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_ReadResult(query, 0), 15000)
	SQL_FreeHandle(query)

	// Formatted with other arguments, it still goes through AMX Mod X's 4 KB format buffer.
	query = SQL_PrepareQuery(g_Db, "SELECT %d, LENGTH('%s')", 1, text)
	SQL_GetQueryString(query, back, charsmax(back))
	SQL_FreeHandle(query)
	ASSERT_EQ(strlen(back), 4095)
	bench_pass()
}
