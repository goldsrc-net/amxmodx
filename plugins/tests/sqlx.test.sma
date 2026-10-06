// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/sqlxtest.sma. The original runs against the database named by the
// amx_sql_* cvars (MySQL); this one uses SQLite, with a database built from
// tests/fixtures/sqlxtest.sql before each test and deleted after it.
//

#include <amxmodx>
#include <amxmisc>
#include <dbi>
#include <sqlx>
#include <amxxbench>

#define TEST_DB "amxxbench_sqlxtest"

new Handle:g_DbInfo
new g_QueryNum
new bool:g_ThreadDone

new g_Gaben[4] = {1, 2, 3, 4}
new g_Fat[4][] = {"what the", "Bee's Knees!", "newell", "CRAB CAKE."}

public plugin_init()
{
	register_plugin("SQLX Test", "1.0", "BAILOPAN")

	start_map()
}

DbPath(path[], len)
{
	new datadir[64]
	get_datadir(datadir, charsmax(datadir))
	formatex(path, len, "%s/sqlite3/%s.sq3", datadir, TEST_DB)
}

/**
 * Builds the test database from the fixture.
 */
public bench_setup()
{
	new path[128]
	DbPath(path, charsmax(path))
	if (file_exists(path))
		delete_file(path)

	new fixture[128], line[256], sql[1024]
	bench_fixture("sqlxtest.sql", fixture, charsmax(fixture))
	new fp = fopen(fixture, "rt")
	if (!bench_check(fp != 0, "fixture sqlxtest.sql opens"))
		return
	while (fgets(fp, line, charsmax(line)))
		add(sql, charsmax(sql), line)
	fclose(fp)

	new errnum, error[255]
	new Handle:db = SQL_Connect(g_DbInfo, errnum, error, charsmax(error))
	if (!bench_check(db != Empty_Handle, "test database connects"))
		return

	new Handle:query = SQL_PrepareQuery(db, "%s", sql)
	new bool:ok = SQL_Execute(query) != 0
	SQL_FreeHandle(query)
	SQL_FreeHandle(db)
	bench_check(ok, "fixture sqlxtest.sql executes")
}

public bench_teardown()
{
	new path[128]
	DbPath(path, charsmax(path))
	if (file_exists(path))
		delete_file(path)
}

bool:DoBasicInfo(affinities=0)
{
	new type[12]
	new affinity[12]

	dbi_type(type, 11)

	if (!bench_check(bool:equal(type, "sqlite"), "DBI type is sqlite"))
		return false

	if (!affinities)
		return true

	new res = SQL_SetAffinity("sqlite")
	if (!bench_check(res == 1, "setting affinity to sqlite succeeds"))
		return false

	SQL_GetAffinity(affinity, 11)
	return bench_check(bool:equal(affinity, "sqlite"), "SQLX affinity is sqlite")
}

public start_map()
{
	g_DbInfo = SQL_MakeDbTuple("", "", "", TEST_DB)
}

public test_bad_connection()
{
	new errnum, error[255]
	// "gaben" would simply be created by SQLite; a database in a directory that does not exist
	// cannot be opened, which is SQLite's form of an unreachable server.
	new Handle:tempinfo = SQL_MakeDbTuple("1.2.3.4", "asdf", "gasdf", "amxxbench_no_such_dir/gaben", 2)
	new Handle:db = SQL_Connect(tempinfo, errnum, error, 254)
	SQL_FreeHandle(tempinfo)

	if (db != Empty_Handle)
		SQL_FreeHandle(db)

	ASSERT_EQ(_:db, _:Empty_Handle)
	ASSERT(errnum != 0)
	ASSERT(error[0] != 0)
	bench_pass()
}

/**
 * Note that this function works for both threaded and non-threaded queries.
 */
bool:CheckQueryData(Handle:query)
{
	new columns = SQL_NumColumns(query)
	new rows = SQL_NumResults(query)
	static querystring[2048]

	SQL_GetQueryString(query, querystring, 2047)

	if (!bench_check(bool:equal(querystring, "SELECT * FROM gaben"), "original query string"))
		return false
	if (!bench_check(columns == 2, "query columns: 2"))
		return false
	if (!bench_check(rows == 4, "query rows: 4"))
		return false

	new num
	new row
	new str[32]
	new cols[2][32]
	SQL_FieldNumToName(query, 0, cols[0], 31)
	SQL_FieldNumToName(query, 1, cols[1], 31)
	if (!bench_check(bool:(equal(cols[0], "gaben") && equal(cols[1], "fat")), "column names gaben, fat"))
		return false
	while (SQL_MoreResults(query))
	{
		if (!bench_check(row < 4, "no more than 4 rows"))
			return false
		num = SQL_ReadResult(query, 0)
		SQL_ReadResult(query, 1, str, 31)
		if (!bench_check(bool:(num == g_Gaben[row] && equal(str, g_Fat[row])), "row values"))
			return false
		SQL_NextRow(query)
		row++
	}

	return bench_check(row == 4, "4 rows read")
}

/**
 * Handler for when a threaded query is resolved.
 */
public GetMyStuff(failstate, Handle:query, error[], errnum, data[], size, Float:queuetime)
{
	if (failstate)
	{
		bench_fail("%s! Error code: %d (Message: ^"%s^")",
			failstate == TQUERY_CONNECT_FAILED ? "Connection failed" : "Query failed",
			errnum, error)
		return
	}
	if (!bench_check(data[0] == g_QueryNum - 1, "resolved query number"))
		return
	if (!bench_check(queuetime >= 0.0, "queue time"))
		return
	if (!CheckQueryData(query))
		return

	g_ThreadDone = true
}

public test_affinity()
{
	// SQL_SetAffinity() succeeds only for a driver whose module is loaded.
	new bool:mysql = LibraryExists("mysql", LibType_Library) != 0
	new res

	res = SQL_SetAffinity("sqlite")
	ASSERT_EQ(res, 1)
	res = SQL_SetAffinity("mysql")
	ASSERT_EQ(res, mysql ? 1 : 0)
	res = SQL_SetAffinity("sqlite")
	ASSERT_EQ(res, 1)

	new affinity[12]
	SQL_GetAffinity(affinity, 11)
	ASSERT_STR_EQ(affinity, "sqlite")
	bench_pass()
}

/**
 * Starts a threaded query.
 */
public test_thread()
{
	new query[512]
	new data[1]

	data[0] = g_QueryNum
	format(query, 511, "SELECT * FROM gaben")

	if (!DoBasicInfo(1))
		return

	g_ThreadDone = false
	SQL_ThreadQuery(g_DbInfo, "GetMyStuff", query, data, 1)

	g_QueryNum++

	bench_wait_until("ThreadDone", "ThreadResolved", 10.0)
}

public ThreadDone(data)
{
	return g_ThreadDone
}

public ThreadResolved(data)
{
	bench_pass()
}

/**
 * Tests string quoting
 */
public test_quote()
{
	if (!DoBasicInfo(1))
		return

	new errno, error[255]

	new Handle:db = SQL_Connect(g_DbInfo, errno, error, sizeof(error)-1)
	ASSERT(db != Empty_Handle)

	new buffer[500], num
	num = SQL_QuoteString(db, buffer, sizeof(buffer)-1, "Hi y'all! C\lam")

	SQL_FreeHandle(db)

	ASSERT_EQ(num, 16)
	ASSERT_STR_EQ(buffer, "Hi y''all! C\lam")
	bench_pass()
}

/**
 * Does a normal query.
 */
public test_normal()
{
	new errnum, error[255]

	if (!DoBasicInfo(1))
		return

	new Handle:db = SQL_Connect(g_DbInfo, errnum, error, 254)
	ASSERT(db != Empty_Handle)

	new Handle:query = SQL_PrepareQuery(db, "SELECT * FROM gaben")
	if (!SQL_Execute(query))
	{
		errnum = SQL_QueryError(query, error, 254)
		SQL_FreeHandle(query)
		SQL_FreeHandle(db)
		bench_fail("Query failure: [%d] %s", errnum, error)
		return
	}

	new bool:ok = CheckQueryData(query)
	new next = SQL_NextResultSet(query)

	SQL_FreeHandle(query)
	SQL_FreeHandle(db)

	if (!ok)
		return
	ASSERT_EQ(next, 0)
	bench_pass()
}

/**
 * Wrapper for an old-style connection.
 */
Sql:OldInitDatabase()
{
	new error[255]
	new Sql:sql = dbi_connect("", "", "", TEST_DB, error, 254)
	if (sql < SQL_OK)
	{
		bench_fail("Connection failure: %s", error)
		return SQL_FAILED
	}

	return sql
}

/**
 * Tests index-based lookup
 */
public test_old_index_lookup()
{
	if (!DoBasicInfo())
		return
	new Sql:sql = OldInitDatabase()
	if (sql < SQL_OK)
		return

	new Result:res = dbi_query(sql, "SELECT * FROM gaben")

	if (res == RESULT_FAILED)
	{
		new error[255]
		new code = dbi_error(sql, error, 254)
		dbi_close(sql)
		bench_fail("Result failed! [%d]: %s", code, error)
		return
	} else if (res == RESULT_NONE) {
		dbi_close(sql)
		bench_fail("No result set returned.")
		return
	}

	new cols[2][32]
	new str[32]
	new row, num
	new rows = dbi_num_rows(res)
	new columns = dbi_num_fields(res)
	new bool:ok = true

	dbi_field_name(res, 1, cols[0], 31)
	dbi_field_name(res, 2, cols[1], 31)
	while (dbi_nextrow(res) > 0)
	{
		num = dbi_field(res, 1)
		dbi_field(res, 2, str, 31)
		if (row >= 4 || num != g_Gaben[row] || !equal(str, g_Fat[row]))
			ok = false
		row++
	}
	dbi_free_result(res)
	dbi_close(sql)

	ASSERT_EQ(columns, 2)
	ASSERT_EQ(rows, 4)
	ASSERT_STR_EQ(cols[0], "gaben")
	ASSERT_STR_EQ(cols[1], "fat")
	if (!bench_check(ok, "row values"))
		return
	ASSERT_EQ(row, 4)
	bench_pass()
}


/**
 * Tests name-based lookup
 */
public test_old_name_lookup()
{
	if (!DoBasicInfo())
		return
	new Sql:sql = OldInitDatabase()
	if (sql < SQL_OK)
		return

	new Result:res = dbi_query(sql, "SELECT * FROM gaben")

	if (res == RESULT_FAILED)
	{
		new error[255]
		new code = dbi_error(sql, error, 254)
		dbi_close(sql)
		bench_fail("Result failed! [%d]: %s", code, error)
		return
	} else if (res == RESULT_NONE) {
		dbi_close(sql)
		bench_fail("No result set returned.")
		return
	}

	new cols[2][32]
	new str[32]
	new row, num
	new rows = dbi_num_rows(res)
	new columns = dbi_num_fields(res)
	new bool:ok = true

	dbi_field_name(res, 1, cols[0], 31)
	dbi_field_name(res, 2, cols[1], 31)
	while (dbi_nextrow(res) > 0)
	{
		num = dbi_result(res, cols[0])
		dbi_result(res, cols[1], str, 31)
		if (row >= 4 || num != g_Gaben[row] || !equal(str, g_Fat[row]))
			ok = false
		row++
	}
	dbi_free_result(res)
	dbi_close(sql)

	ASSERT_EQ(columns, 2)
	ASSERT_EQ(rows, 4)
	ASSERT_STR_EQ(cols[0], "gaben")
	ASSERT_STR_EQ(cols[1], "fat")
	if (!bench_check(ok, "row values"))
		return
	ASSERT_EQ(row, 4)
	bench_pass()
}

public plugin_end()
{
	SQL_FreeHandle(g_DbInfo)
}
