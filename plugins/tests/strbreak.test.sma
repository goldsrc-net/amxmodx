// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

#include <amxmodx>
#include <amxmisc>
#include <amxxbench>

#pragma ctrlchar '\'

// strbreak() in string_stocks.inc has been a stock that calls argbreak() since a86ca149 (2014). These
// checks were written for the native, which is still registered for plugins compiled before
// then, so bind to it directly.
native strbreak_native(const text[], Left[], leftLen, Right[], rightLen) = strbreak;

public plugin_init()
{
	register_plugin("strbreak tests", "1.0", "BAILOPAN");
}

public test_strbreak()
{
	new left[8], right[8];

	// Test sort of normal behavior for strbreak().
	strbreak_native("a b c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "b c");

	strbreak_native("a", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "");

	strbreak_native("a\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a\"");
	ASSERT_STR_EQ(right, "");

	strbreak_native("\"a\" yy", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "yy");

	strbreak_native("\"a x", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "\"a x");
	ASSERT_STR_EQ(right, "");

	strbreak_native("a  b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "b  c");

	strbreak_native("\"a\"  b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "b  c");

	strbreak_native("a  \"b  c\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "\"b  c\"");

	strbreak_native("a  q\"b  c\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "q\"b  c\"");

	strbreak_native("q \"b  c\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "q");
	ASSERT_STR_EQ(right, "\"b  c\"");

	strbreak_native("q \"b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "q");
	ASSERT_STR_EQ(right, "\"b  c");

	// strbreak() functionality starts degrading here, but we test this to
	// preserve bug-for-bug compatibility.
	strbreak_native("q\"b  c\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "\"b  c");
	ASSERT_STR_EQ(right, "\"");

	strbreak_native("\"a  \"a  \"b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a  \"");
	ASSERT_STR_EQ(right, "\"b  c");

	strbreak_native("\"a  \"a  b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a  \"");
	ASSERT_STR_EQ(right, "b  c");

	strbreak_native("\"a\"a  b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a\"");
	ASSERT_STR_EQ(right, "b  c");

	strbreak_native("\"a\" x", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a\"");
	ASSERT_STR_EQ(right, "x");

	strbreak_native("\"a\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "\"");

	strbreak_native("\"a\"b", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "\"a\"b");
	ASSERT_STR_EQ(right, "");

	strbreak_native("q\" b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "q\" b  c");
	ASSERT_STR_EQ(right, "");

	// Test truncation.
	strbreak_native("123456789A 123456789ABCDE", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234567");

	strbreak_native("12345 123456789ABCDE", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "12345");
	ASSERT_STR_EQ(right, "1234567");

	strbreak_native("\"12345\" 123456789ABCDE", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "12345");
	ASSERT_STR_EQ(right, "1234567");

	strbreak_native("\"123456789A\" 123456789ABCDE", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234567");

	strbreak_native("\"123456789A\" 1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234");

	strbreak_native("\"123456789A\"               1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234");

	strbreak_native("123456789A               1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234");

	strbreak_native("123456789A               123456778923", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234567");

	// Bonkers - left-hand makes no sense. Does whitespace count toward the buffer?!
	strbreak_native("  123456789A               123456778923", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "12345");
	ASSERT_STR_EQ(right, "1234567");

	strbreak_native("        \"123456789A\" 1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "");
	ASSERT_STR_EQ(right, "1234");

	strbreak_native("     \"123456789A\" 1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "12");
	ASSERT_STR_EQ(right, "1234");

	new text_cmd[7], cheater[64];
	strbreak_native("  a ", text_cmd, 1, cheater, 31);
	ASSERT_STR_EQ(text_cmd, "");
	ASSERT_STR_EQ(cheater, "");

	bench_pass();
}

public test_argbreak()
{
	new left[8], right[8];

	// Tests for behavior that we expect to work.
	argbreak("a b c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "b c");

	argbreak("a", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "");

	argbreak("a\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "");

	argbreak("\"a\" yy", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "yy");

	argbreak("\"a x", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a x");
	ASSERT_STR_EQ(right, "");

	argbreak("a  b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "b  c");

	argbreak("\"a\"  b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "b  c");

	argbreak("a  \"b  c\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "\"b  c\"");

	argbreak("a  q\"b  c\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "q\"b  c\"");

	argbreak("q \"b  c\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "q");
	ASSERT_STR_EQ(right, "\"b  c\"");

	argbreak("q \"b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "q");
	ASSERT_STR_EQ(right, "\"b  c");

	argbreak("q\"b  c\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "qb  c");
	ASSERT_STR_EQ(right, "");

	argbreak("\"a  \"a  \"b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a  a");
	ASSERT_STR_EQ(right, "\"b  c");

	argbreak("\"a  \"a  b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a  a");
	ASSERT_STR_EQ(right, "b  c");

	argbreak("\"a\"a  b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "aa");
	ASSERT_STR_EQ(right, "b  c");

	argbreak("\"a\" x", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "x");

	argbreak("\"a\"", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "a");
	ASSERT_STR_EQ(right, "");

	argbreak("\"a\"b", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "ab");
	ASSERT_STR_EQ(right, "");

	argbreak("q\" b  c", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "q b  c");
	ASSERT_STR_EQ(right, "");

	// Test truncation.
	argbreak("123456789A 123456789ABCDE", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234567");

	argbreak("12345 123456789ABCDE", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "12345");
	ASSERT_STR_EQ(right, "1234567");

	argbreak("\"12345\" 123456789ABCDE", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "12345");
	ASSERT_STR_EQ(right, "1234567");

	argbreak("\"123456789A\" 123456789ABCDE", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234567");

	argbreak("\"123456789A\" 1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234");

	argbreak("\"123456789A\"               1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234");

	argbreak("123456789A               1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234");

	argbreak("123456789A               123456778923", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234567");

	argbreak("  123456789A               123456778923", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234567");

	argbreak("        \"123456789A\" 1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234");

	argbreak("     \"123456789A\" 1234", left, sizeof(left) - 1, right, sizeof(right) - 1);
	ASSERT_STR_EQ(left, "1234567");
	ASSERT_STR_EQ(right, "1234");

	new text_cmd[7], cheater[64];
	argbreak("  a ", text_cmd, 1, cheater, 31);
	ASSERT_STR_EQ(text_cmd, "a");
	ASSERT_STR_EQ(cheater, "");

	bench_pass();
}

public test_argparse()
{
	// Upstream ran this after the argbreak() tests, which left "1234567" here.
	new left[8] = "1234567";

	// Test no-finds.
	new pos = argparse("   \t\n \t", 0, left, sizeof(left));
	ASSERT_EQ(pos, -1);
	ASSERT_STR_EQ(left, "");

	// Loop for good measure.
	new argv[4][10], argc = 0;
	new text[] = "a \"b\" cd\"e\" \t f\"     ";
	pos = 0;
	while (argc < 4) {
		pos = argparse(text, pos, argv[argc++], 10 - 1);
		if (pos == -1)
			break;
	}
	ASSERT_EQ(argc, 4);
	ASSERT_STR_EQ(argv[0], "a");
	ASSERT_STR_EQ(argv[1], "b");
	ASSERT_STR_EQ(argv[2], "cde");
	ASSERT_STR_EQ(argv[3], "f     ");

	bench_pass();
}
