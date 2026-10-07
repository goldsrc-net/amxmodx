// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Tests for the MySQL module's SQLX natives against a live server (MariaDB 11 or MySQL 8.4, host
// amxxbench-db, database amxxbench5): connecting, failed logins, queries and their results, errors
// with their codes, multiple result sets, quoting, character sets and the driver affinity. Threaded
// queries, logins with each authentication plugin and lost connections have their own files.
// Every test works on table bench5_t, dropped before and after it.
//

#include <amxmodx>
#include <sqlx>
#include <amxxbench>

#pragma loadlib mysql

#define DB_HOST "amxxbench-db"
#define DB_USER "bench"
#define DB_PASS "bench"
#define DB_NAME "amxxbench5"

new Handle:g_Tuple
new Handle:g_Db

public plugin_init()
{
	register_plugin("MySQL Tests", AMXX_VERSION_STR, "AMXX Dev Team")

	// sqlite is loaded first on this server and serves the sqlx class; bind this plugin to mysql.
	SQL_SetAffinity("mysql")
	g_Tuple = SQL_MakeDbTuple(DB_HOST, DB_USER, DB_PASS, DB_NAME)
}

public plugin_end()
{
	SQL_FreeHandle(g_Tuple)
}

public bench_setup()
{
	new errcode, error[256]
	g_Db = SQL_Connect(g_Tuple, errcode, error, charsmax(error))
	if (!bench_check(g_Db != Empty_Handle, "the bench user connects"))
		return
	bench_check(Exec(g_Db, "DROP TABLE IF EXISTS bench5_t"), "leftover table dropped")
}

public bench_teardown()
{
	if (g_Db == Empty_Handle)
		return
	// A test may leave the connection out of sync; drop the table from a fresh one.
	SQL_FreeHandle(g_Db)
	new errcode, error[256]
	g_Db = SQL_Connect(g_Tuple, errcode, error, charsmax(error))
	if (g_Db != Empty_Handle)
	{
		Exec(g_Db, "DROP TABLE IF EXISTS bench5_t")
		SQL_FreeHandle(g_Db)
	}
	g_Db = Empty_Handle
}

// Runs a query that returns no rows. Fails the test with the server's error on failure.
bool:Exec(Handle:db, const fmt[], any:...)
{
	new sql[1024], error[256]
	vformat(sql, charsmax(sql), fmt, 3)
	new Handle:query = SQL_PrepareQuery(db, "%s", sql)
	if (!SQL_Execute(query))
	{
		new code = SQL_QueryError(query, error, charsmax(error))
		SQL_FreeHandle(query)
		bench_fail("%s: [%d] %s", sql, code, error)
		return false
	}
	SQL_FreeHandle(query)
	return true
}

// The first column of the first row as a number, or -1.
QueryInt(Handle:db, const fmt[], any:...)
{
	new sql[1024]
	vformat(sql, charsmax(sql), fmt, 3)
	new Handle:query = SQL_PrepareQuery(db, "%s", sql)
	new value = -1
	if (SQL_Execute(query) && SQL_MoreResults(query))
		value = SQL_ReadResult(query, 0)
	SQL_FreeHandle(query)
	return value
}

// The first column of the first row as text ("" if there is none).
QueryStr(Handle:db, out[], len, const fmt[], any:...)
{
	new sql[1024]
	vformat(sql, charsmax(sql), fmt, 5)
	out[0] = 0
	new Handle:query = SQL_PrepareQuery(db, "%s", sql)
	if (SQL_Execute(query) && SQL_MoreResults(query))
		SQL_ReadResult(query, 0, out, len)
	SQL_FreeHandle(query)
}

// Connects with the given login; returns the handle (Empty_Handle on failure) and the error.
Handle:TryConnect(const host[], const user[], const pass[], const db[], &errcode, error[], len)
{
	new Handle:tuple = SQL_MakeDbTuple(host, user, pass, db)
	errcode = 0
	error[0] = 0
	new Handle:db = SQL_Connect(tuple, errcode, error, len)
	SQL_FreeHandle(tuple)
	return db
}

MakeTable()
{
	return Exec(g_Db, "CREATE TABLE bench5_t (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(32) NOT NULL UNIQUE, score INT NULL, ratio DOUBLE NULL, txt TEXT CHARACTER SET utf8mb4 NULL) ENGINE=InnoDB")
}

public test_affinity()
{
	new driver[16]
	SQL_GetAffinity(driver, charsmax(driver))
	ASSERT_STR_EQ(driver, "mysql")
	ASSERT_EQ(SQL_SetAffinity("mysql"), 1)
	ASSERT_EQ(SQL_SetAffinity("MySQL"), 1)
	ASSERT_EQ(SQL_SetAffinity(""), 1)
	// Another driver: sqlite is loaded, so the natives are bound to it, and back.
	ASSERT_EQ(SQL_SetAffinity("sqlite"), 1)
	SQL_GetAffinity(driver, charsmax(driver))
	ASSERT_STR_EQ(driver, "sqlite")
	ASSERT_EQ(SQL_SetAffinity("mysql"), 1)
	SQL_GetAffinity(driver, charsmax(driver))
	ASSERT_STR_EQ(driver, "mysql")
	// The driver list matches by the first five letters.
	ASSERT_EQ(SQL_SetAffinity("mysqlx"), 1)
	ASSERT_EQ(SQL_SetAffinity("oracle"), 0)
	SQL_GetAffinity(driver, charsmax(driver))
	ASSERT_STR_EQ(driver, "mysql")
	bench_pass()
}

public test_connect()
{
	new user[64], dbname[64]
	QueryStr(g_Db, user, charsmax(user), "SELECT CURRENT_USER()")
	QueryStr(g_Db, dbname, charsmax(dbname), "SELECT DATABASE()")
	ASSERT_STR_EQ(user, "bench@%")
	ASSERT_STR_EQ(dbname, DB_NAME)

	// host:port
	new errcode, error[256]
	new Handle:db = TryConnect("amxxbench-db:3306", DB_USER, DB_PASS, DB_NAME, errcode, error, charsmax(error))
	ASSERT(db != Empty_Handle)
	ASSERT_EQ(QueryInt(db, "SELECT @@port"), 3306)
	SQL_FreeHandle(db)

	// No database: connects, DATABASE() is NULL.
	db = TryConnect(DB_HOST, DB_USER, DB_PASS, "", errcode, error, charsmax(error))
	ASSERT(db != Empty_Handle)
	new Handle:query = SQL_PrepareQuery(db, "SELECT DATABASE()")
	ASSERT(SQL_Execute(query))
	new isnull = SQL_IsNull(query, 0)
	SQL_FreeHandle(query)
	SQL_FreeHandle(db)
	ASSERT_EQ(isnull, 1)
	bench_pass()
}

public test_wrong_password()
{
	new errcode, error[256]
	new Handle:db = TryConnect(DB_HOST, DB_USER, "wrong", DB_NAME, errcode, error, charsmax(error))
	ASSERT_EQ(_:db, _:Empty_Handle)
	ASSERT_EQ(errcode, 1045)
	ASSERT(contain(error, "Access denied for user 'bench'@") == 0)
	ASSERT(contain(error, "(using password: YES)") > 0)

	db = TryConnect(DB_HOST, "bench5_nosuchuser", "", DB_NAME, errcode, error, charsmax(error))
	ASSERT_EQ(_:db, _:Empty_Handle)
	ASSERT_EQ(errcode, 1045)
	ASSERT(contain(error, "(using password: NO)") > 0)
	bench_pass()
}

public test_wrong_database()
{
	new errcode, error[256]
	new Handle:db = TryConnect(DB_HOST, DB_USER, DB_PASS, "amxxbench5_nosuch", errcode, error, charsmax(error))
	ASSERT_EQ(_:db, _:Empty_Handle)
	ASSERT_EQ(errcode, 1049)
	ASSERT_STR_EQ(error, "Unknown database 'amxxbench5_nosuch'")
	bench_pass()
}

public test_wrong_host()
{
	new errcode, error[256]
	new Handle:db = TryConnect("bench5-nosuchhost.invalid", DB_USER, DB_PASS, DB_NAME, errcode, error, charsmax(error))
	ASSERT_EQ(_:db, _:Empty_Handle)
	ASSERT_EQ(errcode, 2005)
	ASSERT(contain(error, "Unknown MySQL server host 'bench5-nosuchhost.invalid'") == 0)

	// The right host, a port nothing listens on: connection refused (errno 111) or in progress (115).
	db = TryConnect("amxxbench-db:3307", DB_USER, DB_PASS, DB_NAME, errcode, error, charsmax(error))
	ASSERT_EQ(_:db, _:Empty_Handle)
	ASSERT_EQ(errcode, 2002)
	ASSERT(contain(error, "Can't connect to MySQL server on 'amxxbench-db'") == 0)
	bench_pass()
}

public test_insert_and_select()
{
	ASSERT(MakeTable())

	new Handle:query = SQL_PrepareQuery(g_Db, "INSERT INTO bench5_t (name, score, ratio) VALUES ('%s', %d, %f), ('b', NULL, 0.5), ('c', -7, NULL)", "a", 10, 2.25)
	ASSERT(SQL_Execute(query))
	// A multi-row insert: every row counts, the id is the first row's.
	ASSERT_EQ(SQL_AffectedRows(query), 3)
	ASSERT_EQ(SQL_GetInsertId(query), 1)
	ASSERT_EQ(SQL_NumResults(query), 0)
	ASSERT_EQ(SQL_MoreResults(query), 0)
	new sql[128], len = SQL_GetQueryString(query, sql, charsmax(sql))
	ASSERT_EQ(len, strlen(sql))
	ASSERT(contain(sql, "VALUES ('a', 10, 2.25") > 0)
	SQL_FreeHandle(query)

	query = SQL_PrepareQuery(g_Db, "INSERT INTO bench5_t (name) VALUES ('d')")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_GetInsertId(query), 4)
	ASSERT_EQ(SQL_AffectedRows(query), 1)
	SQL_FreeHandle(query)

	query = SQL_PrepareQuery(g_Db, "SELECT id, name, score, ratio AS r FROM bench5_t ORDER BY id")
	ASSERT(SQL_Execute(query))
	// For a SELECT the affected rows are the rows returned, and the insert id is still the last
	// one on the connection (a result set carries none).
	ASSERT_EQ(SQL_AffectedRows(query), 4)
	ASSERT_EQ(SQL_GetInsertId(query), 4)
	ASSERT_EQ(SQL_NumResults(query), 4)
	ASSERT_EQ(SQL_NumRows(query), 4)
	ASSERT_EQ(SQL_NumColumns(query), 4)

	new name[32]
	ASSERT_EQ(SQL_FieldNumToName(query, 0, name, charsmax(name)), 1)
	ASSERT_STR_EQ(name, "id")
	SQL_FieldNumToName(query, 3, name, charsmax(name))
	ASSERT_STR_EQ(name, "r")
	ASSERT_EQ(SQL_FieldNameToNum(query, "score"), 2)
	ASSERT_EQ(SQL_FieldNameToNum(query, "r"), 3)
	ASSERT_EQ(SQL_FieldNameToNum(query, "ratio"), -1)
	ASSERT_EQ(SQL_FieldNameToNum(query, "SCORE"), -1)

	new Float:ratio
	ASSERT(SQL_MoreResults(query))
	ASSERT_EQ(SQL_ReadResult(query, 0), 1)
	ASSERT_EQ(SQL_ReadResult(query, 1, name, charsmax(name)), 1)
	ASSERT_STR_EQ(name, "a")
	ASSERT_EQ(SQL_ReadResult(query, 2), 10)
	ASSERT_EQ(SQL_ReadResult(query, 3, ratio), 1)
	ASSERT(ratio == 2.25)
	ASSERT_EQ(SQL_IsNull(query, 2), 0)

	ASSERT_EQ(SQL_NextRow(query), 1)
	ASSERT_EQ(SQL_IsNull(query, 2), 1)
	ASSERT_EQ(SQL_IsNull(query, 3), 0)
	// NULL reads as 0 and "".
	ASSERT_EQ(SQL_ReadResult(query, 2), 0)
	name = "x"
	SQL_ReadResult(query, 2, name, charsmax(name))
	ASSERT_STR_EQ(name, "")

	SQL_NextRow(query)
	ASSERT_EQ(SQL_ReadResult(query, 2), -7)
	ASSERT_EQ(SQL_IsNull(query, 3), 1)
	SQL_ReadResult(query, 3, ratio)
	ASSERT(ratio == 0.0)

	SQL_NextRow(query)
	ASSERT(SQL_MoreResults(query))
	SQL_ReadResult(query, 1, name, charsmax(name))
	ASSERT_STR_EQ(name, "d")
	SQL_NextRow(query)
	ASSERT_EQ(SQL_MoreResults(query), 0)

	// Back to the first row.
	ASSERT_EQ(SQL_Rewind(query), 1)
	ASSERT(SQL_MoreResults(query))
	ASSERT_EQ(SQL_ReadResult(query, 0), 1)
	SQL_FreeHandle(query)
	bench_pass()
}

public test_read_types()
{
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT CAST(-5 AS SIGNED), CAST(4294967297 AS UNSIGNED), CAST(3.25 AS DECIMAL(6,2)), 1.5e3, DATE '2026-10-07', TIMESTAMP '2026-10-07 13:14:15', 'text', X'414243', 0x7A, b'1000001', '12abc', 'abc'")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_NumColumns(query), 12)
	new s[32], Float:f
	ASSERT_EQ(SQL_ReadResult(query, 0), -5)
	SQL_ReadResult(query, 1, s, charsmax(s))
	ASSERT_STR_EQ(s, "4294967297")
	SQL_ReadResult(query, 2, s, charsmax(s))
	ASSERT_STR_EQ(s, "3.25")
	SQL_ReadResult(query, 2, f)
	ASSERT(f == 3.25)
	ASSERT_EQ(SQL_ReadResult(query, 2), 3)
	SQL_ReadResult(query, 3, f)
	ASSERT(f == 1500.0)
	SQL_ReadResult(query, 4, s, charsmax(s))
	ASSERT_STR_EQ(s, "2026-10-07")
	ASSERT_EQ(SQL_ReadResult(query, 4), 2026)
	SQL_ReadResult(query, 5, s, charsmax(s))
	ASSERT_STR_EQ(s, "2026-10-07 13:14:15")
	SQL_ReadResult(query, 6, s, charsmax(s))
	ASSERT_STR_EQ(s, "text")
	// Binary strings come back as their bytes.
	SQL_ReadResult(query, 7, s, charsmax(s))
	ASSERT_STR_EQ(s, "ABC")
	SQL_ReadResult(query, 8, s, charsmax(s))
	ASSERT_STR_EQ(s, "z")
	SQL_ReadResult(query, 9, s, charsmax(s))
	ASSERT_STR_EQ(s, "A")
	// Numbers are read with atoi/atof: leading digits, else 0.
	ASSERT_EQ(SQL_ReadResult(query, 10), 12)
	ASSERT_EQ(SQL_ReadResult(query, 11), 0)
	SQL_ReadResult(query, 11, f)
	ASSERT(f == 0.0)
	// A short buffer is cut.
	SQL_ReadResult(query, 6, s, 2)
	ASSERT_STR_EQ(s, "te")
	SQL_FreeHandle(query)
	bench_pass()
}

public test_update_and_delete()
{
	ASSERT(MakeTable())
	ASSERT(Exec(g_Db, "INSERT INTO bench5_t (name, score) VALUES ('a', 1), ('b', 1), ('c', 2)"))

	new Handle:query = SQL_PrepareQuery(g_Db, "UPDATE bench5_t SET score = 5 WHERE score = 1")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_AffectedRows(query), 2)
	SQL_FreeHandle(query)
	// The rows match but none changes, and changed rows are what is counted.
	query = SQL_PrepareQuery(g_Db, "UPDATE bench5_t SET score = 5 WHERE score = 5")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_AffectedRows(query), 0)
	SQL_FreeHandle(query)

	// ON DUPLICATE KEY UPDATE counts an updated row as 2.
	query = SQL_PrepareQuery(g_Db, "INSERT INTO bench5_t (name, score) VALUES ('c', 9) ON DUPLICATE KEY UPDATE score = VALUES(score)")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_AffectedRows(query), 2)
	SQL_FreeHandle(query)

	query = SQL_PrepareQuery(g_Db, "DELETE FROM bench5_t WHERE score >= 5")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_AffectedRows(query), 3)
	SQL_FreeHandle(query)
	ASSERT_EQ(QueryInt(g_Db, "SELECT COUNT(*) FROM bench5_t"), 0)
	bench_pass()
}

public test_execute_twice()
{
	ASSERT(MakeTable())
	new Handle:insert = SQL_PrepareQuery(g_Db, "INSERT INTO bench5_t (name) SELECT CONCAT('n', COUNT(*)) FROM bench5_t")
	new Handle:select = SQL_PrepareQuery(g_Db, "SELECT name FROM bench5_t ORDER BY id")
	ASSERT(SQL_Execute(insert))
	ASSERT_EQ(SQL_GetInsertId(insert), 1)
	ASSERT(SQL_Execute(select))
	ASSERT_EQ(SQL_NumResults(select), 1)
	ASSERT(SQL_Execute(insert))
	ASSERT_EQ(SQL_GetInsertId(insert), 2)
	// Executing again replaces the earlier result set.
	ASSERT(SQL_Execute(select))
	ASSERT_EQ(SQL_NumResults(select), 2)
	new name[8]
	SQL_NextRow(select)
	SQL_ReadResult(select, 0, name, charsmax(name))
	ASSERT_STR_EQ(name, "n1")
	SQL_FreeHandle(insert)
	SQL_FreeHandle(select)
	bench_pass()
}

public test_empty_result()
{
	ASSERT(MakeTable())
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT id, name FROM bench5_t")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_NumResults(query), 0)
	ASSERT_EQ(SQL_MoreResults(query), 0)
	ASSERT_EQ(SQL_NumColumns(query), 2)
	new name[16]
	SQL_FieldNumToName(query, 1, name, charsmax(name))
	ASSERT_STR_EQ(name, "name")
	ASSERT_EQ(SQL_Rewind(query), 1)
	ASSERT_EQ(SQL_MoreResults(query), 0)
	ASSERT_EQ(SQL_NextResultSet(query), false)
	SQL_FreeHandle(query)
	bench_pass()
}

public test_query_errors()
{
	ASSERT(MakeTable())
	ASSERT(Exec(g_Db, "INSERT INTO bench5_t (name) VALUES ('a')"))
	ASSERT(CheckError("SELEC 1", 1064, "You have an error in your SQL syntax"))
	ASSERT(CheckError("SELECT * FROM bench5_nosuch", 1146, "Table 'amxxbench5.bench5_nosuch' doesn't exist"))
	ASSERT(CheckError("SELECT nosuch FROM bench5_t", 1054, "Unknown column 'nosuch' in "))
	ASSERT(CheckError("INSERT INTO bench5_t (name) VALUES ('a')", 1062, "Duplicate entry 'a' for key "))
	ASSERT(CheckError("INSERT INTO bench5_t (name) VALUES (REPEAT('x', 40))", 1406, "Data too long for column 'name' at row 1"))
	ASSERT(CheckError("INSERT INTO bench5_t (name) VALUES (NULL)", 1048, "Column 'name' cannot be null"))
	// After a success, no error.
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT 1")
	ASSERT(SQL_Execute(query))
	new error[64] = "x"
	ASSERT_EQ(SQL_QueryError(query, error, charsmax(error)), 0)
	ASSERT_STR_EQ(error, "")
	SQL_FreeHandle(query)
	bench_pass()
}

bool:CheckError(const sql[], code, const text[])
{
	new Handle:query = SQL_PrepareQuery(g_Db, "%s", sql)
	new error[256], ok = SQL_Execute(query)
	new got = SQL_QueryError(query, error, charsmax(error))
	new rows = SQL_NumResults(query), affected = SQL_AffectedRows(query), id = SQL_GetInsertId(query)
	SQL_FreeHandle(query)
	if (!bench_check(rows == 0 && affected == 0 && id == 0, "a failed query has no rows, affected rows or insert id"))
		return false
	if (ok || got != code || contain(error, text) < 0)
	{
		bench_fail("%s: expected [%d] ^"%s^", received %d [%d] ^"%s^"", sql, code, text, ok, got, error)
		return false
	}
	return true
}

public test_multiple_result_sets()
{
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT 1 AS a, 2 AS b; SELECT 'three' AS c")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_NumColumns(query), 2)
	ASSERT_EQ(SQL_ReadResult(query, 1), 2)
	ASSERT_EQ(SQL_NextResultSet(query), true)
	ASSERT_EQ(SQL_NumColumns(query), 1)
	ASSERT_EQ(SQL_NumResults(query), 1)
	new s[16]
	SQL_FieldNumToName(query, 0, s, charsmax(s))
	ASSERT_STR_EQ(s, "c")
	SQL_ReadResult(query, 0, s, charsmax(s))
	ASSERT_STR_EQ(s, "three")
	ASSERT_EQ(SQL_NextResultSet(query), false)
	// The last set is gone with it.
	ASSERT_EQ(SQL_MoreResults(query), 0)
	ASSERT_EQ(SQL_NumResults(query), 0)
	SQL_FreeHandle(query)
	// The connection is still in sync.
	ASSERT_EQ(QueryInt(g_Db, "SELECT 42"), 42)

	// Freed before the second set is read: the rest is drained.
	query = SQL_PrepareQuery(g_Db, "SELECT 1; SELECT 2; SELECT 3")
	ASSERT(SQL_Execute(query))
	SQL_FreeHandle(query)
	ASSERT_EQ(QueryInt(g_Db, "SELECT 43"), 43)

	// A stored procedure: its two result sets, then its status.
	ASSERT(Exec(g_Db, "DROP PROCEDURE IF EXISTS bench5_p"))
	ASSERT(Exec(g_Db, "CREATE PROCEDURE bench5_p() BEGIN SELECT 1; SELECT 2, 3; END"))
	query = SQL_PrepareQuery(g_Db, "CALL bench5_p()")
	ASSERT(SQL_Execute(query))
	ASSERT_EQ(SQL_ReadResult(query, 0), 1)
	ASSERT_EQ(SQL_NextResultSet(query), true)
	ASSERT_EQ(SQL_ReadResult(query, 1), 3)
	ASSERT_EQ(SQL_NextResultSet(query), false)
	SQL_FreeHandle(query)
	ASSERT_EQ(QueryInt(g_Db, "SELECT 44"), 44)
	ASSERT(Exec(g_Db, "DROP PROCEDURE bench5_p"))
	bench_pass()
}

public test_quote_string()
{
	// Every character mysql_real_escape_string escapes (NUL cannot be in a Pawn string), and some
	// it leaves alone.
	new const input[] = "a'b^"c\d^ne^rf^x1a;g%h`i;j_k"
	new const quoted[] = "a\'b\^"c\\d\ne\rf\Zg%h`i;j_k"
	new buffer[64]
	ASSERT_EQ(SQL_QuoteString(g_Db, buffer, charsmax(buffer), input), strlen(quoted))
	ASSERT_STR_EQ(buffer, quoted)
	// No connection: the same, without the connection's character set.
	buffer[0] = 0
	ASSERT_EQ(SQL_QuoteString(Empty_Handle, buffer, charsmax(buffer), input), strlen(quoted))
	ASSERT_STR_EQ(buffer, quoted)

	// Through the table and back unchanged.
	ASSERT(MakeTable())
	SQL_QuoteString(g_Db, buffer, charsmax(buffer), input)
	ASSERT(Exec(g_Db, "INSERT INTO bench5_t (name, txt) VALUES ('q', '%s')", buffer))
	new back[64]
	QueryStr(g_Db, back, charsmax(back), "SELECT txt FROM bench5_t WHERE name = 'q'")
	ASSERT_STR_EQ(back, input)
	QueryStr(g_Db, back, charsmax(back), "SELECT HEX(txt) FROM bench5_t WHERE name = 'q'")
	ASSERT_STR_EQ(back, "61276222635C640A650D661A67256860693B6A5F6B")
	bench_pass()
}

public test_quote_string_fmt()
{
	new buffer[64]
	ASSERT_EQ(SQL_QuoteStringFmt(g_Db, buffer, charsmax(buffer), "%s's %d%% ^"%s^"", "Bob", 5, "x\y"), 18)
	ASSERT_STR_EQ(buffer, "Bob\'s 5% \^"x\\y\^"")
	ASSERT_EQ(SQL_QuoteStringFmt(Empty_Handle, buffer, charsmax(buffer), "%s", "it's"), 5)
	ASSERT_STR_EQ(buffer, "it\'s")
	bench_pass()
}

public test_quote_string_limits()
{
	// The return value is the quoted length, even when the buffer cuts it.
	new small[4]
	ASSERT_EQ(SQL_QuoteString(g_Db, small, charsmax(small), "a'b'c"), 7)
	ASSERT_STR_EQ(small, "a\'")

	// Escaping happens in an 8 KB buffer: 4096 characters may double to more, and fail.
	static big[4097], out[16]
	for (new i = 0; i < 4096; i++)
		big[i] = 'a'
	big[4096] = 0
	ASSERT_EQ(SQL_QuoteString(g_Db, out, charsmax(out), big), -1)
	ASSERT_EQ(SQL_QuoteString(Empty_Handle, out, charsmax(out), big), -1)
	ASSERT_EQ(SQL_QuoteStringFmt(g_Db, out, charsmax(out), "%s", big), -1)
	ASSERT_EQ(SQL_QuoteStringFmt(Empty_Handle, out, charsmax(out), "%s", big), -1)
	// With other arguments the text goes through AMX Mod X's 4 KB format buffer first, which cuts
	// it at 4095 characters.
	ASSERT_EQ(SQL_QuoteStringFmt(g_Db, out, charsmax(out), "%s%d", big, 1), 4095)
	big[4095] = 0
	ASSERT_EQ(SQL_QuoteString(g_Db, out, charsmax(out), big), 4095)
	bench_pass()
}

public test_quote_string_no_backslash_escapes()
{
	// With NO_BACKSLASH_ESCAPES the server takes backslashes literally: the connection's quoting
	// doubles quotes instead; the connectionless one does not know.
	ASSERT(Exec(g_Db, "SET SESSION sql_mode = CONCAT(@@sql_mode, ',NO_BACKSLASH_ESCAPES')"))
	new buffer[32]
	ASSERT_EQ(SQL_QuoteString(g_Db, buffer, charsmax(buffer), "it's a\b"), 9)
	ASSERT_STR_EQ(buffer, "it''s a\b")
	SQL_QuoteString(Empty_Handle, buffer, charsmax(buffer), "it's a\b")
	ASSERT_STR_EQ(buffer, "it\'s a\\b")
	ASSERT(MakeTable())
	SQL_QuoteString(g_Db, buffer, charsmax(buffer), "it's a\b")
	ASSERT(Exec(g_Db, "INSERT INTO bench5_t (name) VALUES ('%s')", buffer))
	new back[32]
	QueryStr(g_Db, back, charsmax(back), "SELECT name FROM bench5_t")
	ASSERT_STR_EQ(back, "it's a\b")
	bench_pass()
}

public test_default_charset()
{
	// The module sets no character set: the client's default, latin1, on both servers. UTF-8
	// sent then is stored as latin1 characters (one per byte) and still reads back the same.
	new cs[32]
	QueryStr(g_Db, cs, charsmax(cs), "SELECT @@character_set_client")
	ASSERT_STR_EQ(cs, "latin1")
	QueryStr(g_Db, cs, charsmax(cs), "SELECT @@character_set_results")
	ASSERT_STR_EQ(cs, "latin1")
	ASSERT(MakeTable())
	ASSERT(Exec(g_Db, "INSERT INTO bench5_t (name, txt) VALUES ('u', '日本')"))
	ASSERT_EQ(QueryInt(g_Db, "SELECT CHAR_LENGTH(txt) FROM bench5_t"), 6)
	new back[32]
	QueryStr(g_Db, back, charsmax(back), "SELECT txt FROM bench5_t")
	ASSERT_STR_EQ(back, "日本")
	bench_pass()
}

public test_utf8_round_trip()
{
	ASSERT_EQ(SQL_SetCharset(g_Db, "utf8mb4"), true)
	new cs[32]
	QueryStr(g_Db, cs, charsmax(cs), "SELECT @@character_set_client")
	ASSERT_STR_EQ(cs, "utf8mb4")
	ASSERT(MakeTable())

	new const text[] = "héllo ✓ 日本語 😀"
	new quoted[64]
	SQL_QuoteString(g_Db, quoted, charsmax(quoted), text)
	ASSERT_STR_EQ(quoted, text)
	ASSERT(Exec(g_Db, "INSERT INTO bench5_t (name, txt) VALUES ('u', '%s')", quoted))
	ASSERT_EQ(QueryInt(g_Db, "SELECT CHAR_LENGTH(txt) FROM bench5_t"), 13)
	ASSERT_EQ(QueryInt(g_Db, "SELECT LENGTH(txt) FROM bench5_t"), strlen(text))
	new back[64]
	QueryStr(g_Db, back, charsmax(back), "SELECT txt FROM bench5_t")
	ASSERT_STR_EQ(back, text)
	QueryStr(g_Db, back, charsmax(back), "SELECT HEX(SUBSTRING(txt, 13, 1)) FROM bench5_t")
	ASSERT_STR_EQ(back, "F09F9880")

	// Field names in UTF-8.
	new Handle:query = SQL_PrepareQuery(g_Db, "SELECT 1 AS `größe`")
	ASSERT(SQL_Execute(query))
	new name[32]
	SQL_FieldNumToName(query, 0, name, charsmax(name))
	ASSERT_STR_EQ(name, "größe")
	ASSERT_EQ(SQL_FieldNameToNum(query, "größe"), 0)
	SQL_FreeHandle(query)

	// utf8mb3 has no four-byte characters: strict mode refuses the emoji.
	ASSERT_EQ(SQL_SetCharset(g_Db, "utf8"), true)
	query = SQL_PrepareQuery(g_Db, "INSERT INTO bench5_t (name, txt) VALUES ('e', '😀')")
	new ok = SQL_Execute(query), error[128]
	new code = SQL_QueryError(query, error, charsmax(error))
	SQL_FreeHandle(query)
	ASSERT_EQ(ok, 0)
	ASSERT_EQ(code, 1366)
	ASSERT(contain(error, "Incorrect string value") == 0)
	bench_pass()
}

public test_set_charset_on_tuple()
{
	new Handle:tuple = SQL_MakeDbTuple(DB_HOST, DB_USER, DB_PASS, DB_NAME)
	ASSERT_EQ(SQL_SetCharset(tuple, "utf8mb4"), true)
	// The same again is kept as it is.
	ASSERT_EQ(SQL_SetCharset(tuple, "UTF8MB4"), true)
	new errcode, error[128], cs[32]
	new Handle:db = SQL_Connect(tuple, errcode, error, charsmax(error))
	ASSERT(db != Empty_Handle)
	QueryStr(db, cs, charsmax(cs), "SELECT @@character_set_client")
	SQL_FreeHandle(db)
	ASSERT_STR_EQ(cs, "utf8mb4")

	ASSERT_EQ(SQL_SetCharset(tuple, "cp1250"), true)
	db = SQL_Connect(tuple, errcode, error, charsmax(error))
	QueryStr(db, cs, charsmax(cs), "SELECT @@character_set_results")
	SQL_FreeHandle(db)
	ASSERT_STR_EQ(cs, "cp1250")

	// A tuple takes any name; a connection it cannot be set on keeps the default and still connects.
	ASSERT_EQ(SQL_SetCharset(tuple, "bench5_nosuchcharset"), true)
	db = SQL_Connect(tuple, errcode, error, charsmax(error))
	ASSERT(db != Empty_Handle)
	QueryStr(db, cs, charsmax(cs), "SELECT @@character_set_client")
	SQL_FreeHandle(db)
	SQL_FreeHandle(tuple)
	ASSERT_STR_EQ(cs, "latin1")
	bench_pass()
}

public test_set_charset_invalid()
{
	ASSERT_EQ(SQL_SetCharset(g_Db, "bench5_nosuchcharset"), false)
	new cs[32]
	QueryStr(g_Db, cs, charsmax(cs), "SELECT @@character_set_client")
	ASSERT_STR_EQ(cs, "latin1")
	bench_pass()
}

// Run time errors, one per step: each native given a bad handle or a query without rows.
new const g_ErrorTexts[][] =
{
	"Invalid handle: 9999",
	"Invalid info tuple handle: 9999",
	"Invalid database handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid query handle: 9999",
	"Invalid database handle: 9999",
	"Invalid database handle: 9999",
	"Invalid info tuple or database handle: 9999",
	"Invalid handle: ",
	"No result set in this query!",
	"No result set in this query!",
	"No result set in this query!",
	"No result set in this query!",
	"No result set in this query!",
	"No result set in this query!",
	"No result set in this query!",
	"No result set in this query!",
	"Invalid column: 5",
	"Invalid column: 5",
	"Invalid column: 5",
	"Bad number of arguments passed.",
	"No result set in this query!",
	"Invalid database handle: "
}

new Handle:g_ErrQuery
new Handle:g_ErrRows

public test_native_errors()
{
	g_ErrQuery = SQL_PrepareQuery(g_Db, "DO 0")
	ASSERT(SQL_Execute(g_ErrQuery))
	g_ErrRows = SQL_PrepareQuery(g_Db, "SELECT 1, 2")
	ASSERT(SQL_Execute(g_ErrRows))
	native_error_step(0)
}

public native_error_step(n)
{
	if (n == sizeof(g_ErrorTexts))
	{
		SQL_FreeHandle(g_ErrQuery)
		SQL_FreeHandle(g_ErrRows)
		bench_pass()
		return
	}
	bench_expect_error(g_ErrorTexts[n])
	bench_next("native_error_step", 0.0, n + 1)

	new Handle:bad = Handle:9999, s[8], Float:f, code
	switch (n)
	{
		case 0: SQL_FreeHandle(bad)
		case 1: SQL_Connect(bad, code, s, charsmax(s))
		case 2: SQL_PrepareQuery(bad, "SELECT 1")
		case 3: SQL_Execute(bad)
		case 4: SQL_QueryError(bad, s, charsmax(s))
		case 5: SQL_MoreResults(bad)
		case 6: SQL_IsNull(bad, 0)
		case 7: SQL_ReadResult(bad, 0)
		case 8: SQL_NextRow(bad)
		case 9: SQL_AffectedRows(bad)
		case 10: SQL_NumResults(bad)
		case 11: SQL_NumColumns(bad)
		case 12: SQL_FieldNumToName(bad, 0, s, charsmax(s))
		case 13: SQL_FieldNameToNum(bad, "a")
		case 14: SQL_Rewind(bad)
		case 15: SQL_GetInsertId(bad)
		case 16: SQL_GetQueryString(bad, s, charsmax(s))
		case 17: SQL_NextResultSet(bad)
		case 18: SQL_QuoteString(bad, s, charsmax(s), "a")
		case 19: SQL_QuoteStringFmt(bad, s, charsmax(s), "a")
		case 20: SQL_SetCharset(bad, "utf8")
		case 21: SQL_FreeHandle(Empty_Handle)
		// A statement without a result set.
		case 22: SQL_NumColumns(g_ErrQuery)
		case 23: SQL_FieldNumToName(g_ErrQuery, 0, s, charsmax(s))
		case 24: SQL_FieldNameToNum(g_ErrQuery, "a")
		case 25: SQL_Rewind(g_ErrQuery)
		case 26: SQL_NextResultSet(g_ErrQuery)
		case 27: SQL_IsNull(g_ErrQuery, 0)
		case 28: SQL_ReadResult(g_ErrQuery, 0)
		case 29: SQL_NextRow(g_ErrQuery)
		// Columns out of range.
		case 30: SQL_ReadResult(g_ErrRows, 5)
		case 31: SQL_IsNull(g_ErrRows, 5)
		case 32: SQL_FieldNumToName(g_ErrRows, 5, s, charsmax(s))
		case 33: SQL_ReadResult(g_ErrRows, 0, f, s, 1)
		// Past the last row.
		case 34:
		{
			SQL_NextRow(g_ErrRows)
			SQL_ReadResult(g_ErrRows, 0)
		}
		// A handle of the wrong kind: a query handle given as a database.
		case 35: SQL_PrepareQuery(g_ErrRows, "SELECT 1")
	}
}
