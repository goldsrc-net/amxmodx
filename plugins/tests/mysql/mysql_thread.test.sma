// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the MySQL module's SQL_ThreadQuery against a live server (MariaDB 11 or MySQL 8.4,
// host amxxbench-db, database amxxbench5): results and data handed to the handler, the failstates,
// the order of queued queries, the tuple's character set, and the errors the native raises. The
// handler copies what it reads into globals, and each test checks them once its queries are back.
//

#include <amxmodx>
#include <sqlx>
#include <amxxbench>

#pragma loadlib mysql

#define DB_HOST "amxxbench-db"
#define DB_USER "bench"
#define DB_PASS "bench"
#define DB_NAME "amxxbench5"

#define MAX_RESULTS 8

new Handle:g_Tuple

// What the handler saw, per query, in the order they came back.
new g_Done
new g_Fail[MAX_RESULTS]
new g_Errnum[MAX_RESULTS]
new g_Error[MAX_RESULTS][128]
new g_Size[MAX_RESULTS]
new g_Data[MAX_RESULTS][4]
new Float:g_QueueTime[MAX_RESULTS]
new g_QueryString[MAX_RESULTS][128]
new g_Rows[MAX_RESULTS]
new g_Columns[MAX_RESULTS]
new g_Names[MAX_RESULTS][64]
new g_Values[MAX_RESULTS][256]
new g_Rewound[MAX_RESULTS][32]
new g_NameToNum[MAX_RESULTS]
new g_InsertId[MAX_RESULTS]
new g_Affected[MAX_RESULTS]
new g_MoreSets[MAX_RESULTS]
new g_Nulls[MAX_RESULTS][16]

public plugin_init()
{
	register_plugin("MySQL Threaded Query Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	SQL_SetAffinity("mysql")
	g_Tuple = SQL_MakeDbTuple(DB_HOST, DB_USER, DB_PASS, DB_NAME)
}

public plugin_end()
{
	SQL_FreeHandle(g_Tuple)
}

public bench_setup()
{
	g_Done = 0
	DropTable()
}

public bench_teardown()
{
	DropTable()
}

DropTable()
{
	new errcode, error[128]
	new Handle:db = SQL_Connect(g_Tuple, errcode, error, charsmax(error))
	if (!bench_check(db != Empty_Handle, "the bench user connects"))
		return
	new Handle:query = SQL_PrepareQuery(db, "DROP TABLE IF EXISTS bench5_th")
	bench_check(SQL_Execute(query) != 0, "table bench5_th dropped")
	SQL_FreeHandle(query)
	SQL_FreeHandle(db)
}

// Handler for every query of this file: records what it was given and what it can read.
public OnQuery(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
	new n = g_Done++
	if (n >= MAX_RESULTS)
		return
	g_Fail[n] = failstate
	g_Errnum[n] = errnum
	copy(g_Error[n], charsmax(g_Error[]), error)
	g_Size[n] = size
	for (new i = 0; i < size && i < sizeof(g_Data[]); i++)
		g_Data[n][i] = data[i]
	g_QueueTime[n] = queuetime
	SQL_GetQueryString(query, g_QueryString[n], charsmax(g_QueryString[]))
	g_InsertId[n] = SQL_GetInsertId(query)
	g_Affected[n] = SQL_AffectedRows(query)
	g_Rows[n] = SQL_NumResults(query)
	g_Names[n][0] = 0
	g_Values[n][0] = 0
	g_Rewound[n][0] = 0
	g_NameToNum[n] = -2
	g_MoreSets[n] = -1
	g_Nulls[n][0] = 0
	g_Columns[n] = 0
	if (failstate != TQUERY_SUCCESS || !HasColumns(query))
		return

	g_Columns[n] = SQL_NumColumns(query)
	new name[32], value[64]
	for (new c = 0; c < g_Columns[n]; c++)
	{
		SQL_FieldNumToName(query, c, name, charsmax(name))
		format(g_Names[n], charsmax(g_Names[]), "%s%s%s", g_Names[n], c ? "|" : "", name)
	}
	g_NameToNum[n] = SQL_FieldNameToNum(query, "b")
	for (new c = 0; c < g_Columns[n] && SQL_MoreResults(query); c++)
		add(g_Nulls[n], charsmax(g_Nulls[]), SQL_IsNull(query, c) ? "1" : "0")
	while (SQL_MoreResults(query))
	{
		for (new c = 0; c < g_Columns[n]; c++)
		{
			SQL_ReadResult(query, c, value, charsmax(value))
			format(g_Values[n], charsmax(g_Values[]), "%s%s%s", g_Values[n], c ? "," : (g_Values[n][0] ? ";" : ""), value)
		}
		SQL_NextRow(query)
	}
	if (g_Rows[n])
	{
		SQL_Rewind(query)
		new Float:f
		SQL_ReadResult(query, 0, f)
		formatex(g_Rewound[n], charsmax(g_Rewound[]), "%d/%.2f", SQL_ReadResult(query, 0), f)
	}
	g_MoreSets[n] = SQL_NextResultSet(query)
}

// Whether a successful query returned a result set (an UPDATE does not).
bool:HasColumns(Handle:query)
{
	new sql[16]
	SQL_GetQueryString(query, sql, charsmax(sql))
	return equali(sql, "SELECT", 6) != 0
}

public bool:AllBack(count)
{
	return g_Done >= count
}

public test_thread_select_with_data()
{
	new data[3] = {7, 8, -9}
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT 1 AS a, 'x' AS b, 2.5 AS c UNION ALL SELECT 2, 'y', NULL", data, 3)
	bench_wait_until("AllBack", "thread_select_back", 10.0, 1)
}

public thread_select_back()
{
	ASSERT_EQ(g_Fail[0], TQUERY_SUCCESS)
	ASSERT_EQ(g_Errnum[0], 0)
	ASSERT_STR_EQ(g_Error[0], "")
	ASSERT_EQ(g_Size[0], 3)
	ASSERT_EQ(g_Data[0][0], 7)
	ASSERT_EQ(g_Data[0][1], 8)
	ASSERT_EQ(g_Data[0][2], -9)
	ASSERT(g_QueueTime[0] > 0.0)
	ASSERT_STR_EQ(g_QueryString[0], "SELECT 1 AS a, 'x' AS b, 2.5 AS c UNION ALL SELECT 2, 'y', NULL")
	ASSERT_EQ(g_Rows[0], 2)
	ASSERT_EQ(g_Affected[0], 2)
	ASSERT_EQ(g_Columns[0], 3)
	ASSERT_STR_EQ(g_Names[0], "a|b|c")
	ASSERT_EQ(g_NameToNum[0], 1)
	ASSERT_STR_EQ(g_Values[0], "1,x,2.5;2,y,")
	ASSERT_STR_EQ(g_Nulls[0], "000")
	ASSERT_STR_EQ(g_Rewound[0], "1/1.00")
	// A threaded result holds one result set.
	ASSERT_EQ(g_MoreSets[0], 0)
	bench_pass()
}

public test_thread_insert()
{
	SQL_ThreadQuery(g_Tuple, "OnQuery", "CREATE TABLE bench5_th (id INT AUTO_INCREMENT PRIMARY KEY, b VARCHAR(8))")
	SQL_ThreadQuery(g_Tuple, "OnQuery", "INSERT INTO bench5_th (b) VALUES ('p'), ('q'), ('r')")
	SQL_ThreadQuery(g_Tuple, "OnQuery", "UPDATE bench5_th SET b = 'z' WHERE id > 1")
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT id, b FROM bench5_th WHERE id > 5")
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT b, id FROM bench5_th ORDER BY id")
	bench_wait_until("AllBack", "thread_insert_back", 10.0, 5)
}

public thread_insert_back()
{
	for (new i = 0; i < 5; i++)
	{
		ASSERT_EQ(g_Fail[i], TQUERY_SUCCESS)
		// No data given: an empty array.
		ASSERT_EQ(g_Size[i], 0)
	}
	ASSERT_EQ(g_InsertId[1], 1)
	ASSERT_EQ(g_Affected[1], 3)
	ASSERT_EQ(g_Rows[1], 0)
	ASSERT_EQ(g_Affected[2], 2)
	// An empty result: columns, no rows.
	ASSERT_EQ(g_Rows[3], 0)
	ASSERT_EQ(g_Columns[3], 2)
	ASSERT_STR_EQ(g_Names[3], "id|b")
	ASSERT_STR_EQ(g_Values[3], "")
	ASSERT_STR_EQ(g_Values[4], "p,1;z,2;z,3")
	ASSERT_EQ(g_NameToNum[4], 0)
	bench_pass()
}

public test_thread_query_failed()
{
	new data[1] = {5}
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT * FROM bench5_nosuch", data, 1)
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELEC 1")
	bench_wait_until("AllBack", "thread_query_failed_back", 10.0, 2)
}

public thread_query_failed_back()
{
	ASSERT_EQ(g_Fail[0], TQUERY_QUERY_FAILED)
	ASSERT_EQ(g_Errnum[0], 1146)
	ASSERT_STR_EQ(g_Error[0], "Table 'amxxbench5.bench5_nosuch' doesn't exist")
	ASSERT_EQ(g_Size[0], 1)
	ASSERT_EQ(g_Data[0][0], 5)
	ASSERT_STR_EQ(g_QueryString[0], "SELECT * FROM bench5_nosuch")
	ASSERT_EQ(g_Rows[0], 0)
	ASSERT_EQ(g_Fail[1], TQUERY_QUERY_FAILED)
	ASSERT_EQ(g_Errnum[1], 1064)
	ASSERT(contain(g_Error[1], "You have an error in your SQL syntax") == 0)
	bench_pass()
}

new Handle:g_BadTuples[3]

public test_thread_connect_failed()
{
	g_BadTuples[0] = SQL_MakeDbTuple(DB_HOST, DB_USER, "wrong", DB_NAME)
	g_BadTuples[1] = SQL_MakeDbTuple(DB_HOST, DB_USER, DB_PASS, "amxxbench5_nosuch")
	g_BadTuples[2] = SQL_MakeDbTuple("bench5-nosuchhost.invalid", DB_USER, DB_PASS, DB_NAME)
	for (new i = 0; i < 3; i++)
		SQL_ThreadQuery(g_BadTuples[i], "OnQuery", "SELECT 1")
	bench_wait_until("AllBack", "thread_connect_failed_back", 10.0, 3)
}

public thread_connect_failed_back()
{
	for (new i = 0; i < 3; i++)
		SQL_FreeHandle(g_BadTuples[i])
	for (new i = 0; i < 3; i++)
	{
		ASSERT_EQ(g_Fail[i], TQUERY_CONNECT_FAILED)
		ASSERT_STR_EQ(g_QueryString[i], "SELECT 1")
		ASSERT_EQ(g_Rows[i], 0)
	}
	ASSERT_EQ(g_Errnum[0], 1045)
	ASSERT(contain(g_Error[0], "Access denied for user 'bench'@") == 0)
	ASSERT_EQ(g_Errnum[1], 1049)
	ASSERT_STR_EQ(g_Error[1], "Unknown database 'amxxbench5_nosuch'")
	ASSERT_EQ(g_Errnum[2], 2005)
	ASSERT(contain(g_Error[2], "Unknown MySQL server host 'bench5-nosuchhost.invalid'") == 0)
	bench_pass()
}

public test_thread_order()
{
	new query[32], data[1]
	for (new i = 0; i < 6; i++)
	{
		data[0] = i
		formatex(query, charsmax(query), "SELECT %d", i * 10)
		SQL_ThreadQuery(g_Tuple, "OnQuery", query, data, 1)
	}
	bench_wait_until("AllBack", "thread_order_back", 10.0, 6)
}

public thread_order_back()
{
	// One worker: they come back in the order they were queued.
	new expected[8]
	for (new i = 0; i < 6; i++)
	{
		ASSERT_EQ(g_Data[i][0], i)
		num_to_str(i * 10, expected, charsmax(expected))
		ASSERT_STR_EQ(g_Values[i], expected)
		if (i)
			ASSERT(g_QueueTime[i] >= g_QueueTime[i - 1])
	}
	bench_pass()
}

new Handle:g_CharsetTuple

public test_thread_charset()
{
	g_CharsetTuple = SQL_MakeDbTuple(DB_HOST, DB_USER, DB_PASS, DB_NAME)
	ASSERT(SQL_SetCharset(g_CharsetTuple, "utf8mb4"))
	SQL_ThreadQuery(g_CharsetTuple, "OnQuery", "SELECT @@character_set_client, CHAR_LENGTH('日本語😀'), '日本語😀'")
	// Without a character set: latin1, one character per byte.
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT @@character_set_client, CHAR_LENGTH('日本語😀'), '日本語😀'")
	bench_wait_until("AllBack", "thread_charset_back", 10.0, 2)
}

public thread_charset_back()
{
	SQL_FreeHandle(g_CharsetTuple)
	ASSERT_STR_EQ(g_Values[0], "utf8mb4,4,日本語😀")
	ASSERT_STR_EQ(g_Values[1], "latin1,13,日本語😀")
	bench_pass()
}

public test_thread_tuple_freed_while_queued()
{
	// The query keeps its own copy of the login: freeing the tuple at once is fine.
	new Handle:tuple = SQL_MakeDbTuple(DB_HOST, DB_USER, DB_PASS, DB_NAME)
	SQL_ThreadQuery(tuple, "OnQuery", "SELECT 'kept'")
	SQL_FreeHandle(tuple)
	bench_wait_until("AllBack", "thread_tuple_freed_back", 10.0, 1)
}

public thread_tuple_freed_back()
{
	ASSERT_EQ(g_Fail[0], TQUERY_SUCCESS)
	ASSERT_STR_EQ(g_Values[0], "kept")
	bench_pass()
}

public test_thread_multiple_result_sets()
{
	// Only the first set reaches the handler.
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT 1 AS a; SELECT 2 AS b, 3")
	bench_wait_until("AllBack", "thread_multiple_back", 10.0, 1)
}

public thread_multiple_back()
{
	ASSERT_EQ(g_Fail[0], TQUERY_SUCCESS)
	ASSERT_STR_EQ(g_Names[0], "a")
	ASSERT_STR_EQ(g_Values[0], "1")
	ASSERT_EQ(g_MoreSets[0], 0)
	bench_pass()
}

public test_thread_null()
{
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT NULL AS a, '' AS b, 0 AS c")
	bench_wait_until("AllBack", "thread_null_back", 10.0, 1)
}

public thread_null_back()
{
	ASSERT_EQ(g_Fail[0], TQUERY_SUCCESS)
	ASSERT_STR_EQ(g_Nulls[0], "100")
	ASSERT_STR_EQ(g_Values[0], ",,0")
	bench_pass()
}

public test_thread_data_not_kept()
{
	// A query given no data after one given some (the worker reuses its query objects).
	new data[2] = {41, 42}
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT 1", data, 2)
	bench_wait_until("AllBack", "thread_data_first_back", 10.0, 1)
}

public thread_data_first_back()
{
	ASSERT_EQ(g_Size[0], 2)
	ASSERT_EQ(g_Data[0][1], 42)
	SQL_ThreadQuery(g_Tuple, "OnQuery", "SELECT 2")
	bench_wait_until("AllBack", "thread_data_second_back", 10.0, 2)
}

public thread_data_second_back()
{
	ASSERT_EQ(g_Size[1], 0)
	ASSERT_STR_EQ(g_Values[1], "2")
	bench_pass()
}

public test_thread_unknown_handler()
{
	bench_expect_error("Function not found: bench5_nosuch")
	bench_next("thread_invalid_tuple")
	SQL_ThreadQuery(g_Tuple, "bench5_nosuch", "SELECT 1")
}

public thread_invalid_tuple()
{
	bench_expect_error("Invalid info tuple handle: 9999")
	bench_next("thread_no_query_ran", 2.0)
	SQL_ThreadQuery(Handle:9999, "OnQuery", "SELECT 1")
}

public thread_no_query_ran()
{
	ASSERT_EQ(g_Done, 0)
	bench_pass()
}
