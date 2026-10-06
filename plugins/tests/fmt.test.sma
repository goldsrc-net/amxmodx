// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

#include <amxmodx>
#include <amxxbench>

public plugin_init()
{
	register_plugin("Format Test", "1.0", "BAILOPAN")
}

public test_format()
{
	new buffer[64]

	formatex(buffer, charsmax(buffer), "Printing -1 with d: %d", -1)
	ASSERT_STR_EQ(buffer, "Printing -1 with d: -1")
	formatex(buffer, charsmax(buffer), "Printing -1 with u: %u", -1)
	ASSERT_STR_EQ(buffer, "Printing -1 with u: 4294967295")
	formatex(buffer, charsmax(buffer), "Printing (1<<31) with d: %d", (1<<31))
	ASSERT_STR_EQ(buffer, "Printing (1<<31) with d: -2147483648")
	formatex(buffer, charsmax(buffer), "Printing (1<<31) with u: %u", (1<<31))
	ASSERT_STR_EQ(buffer, "Printing (1<<31) with u: 2147483648")
	formatex(buffer, charsmax(buffer), "Printing 1 with d: %d", 1)
	ASSERT_STR_EQ(buffer, "Printing 1 with d: 1")
	formatex(buffer, charsmax(buffer), "Printing 1 with u: %u", 1)
	ASSERT_STR_EQ(buffer, "Printing 1 with u: 1")

	bench_pass()
}

public test_replace()
{
	new message[192] = "^"@test^""

	replace_all(message, 191, "^"", "")
	ASSERT_STR_EQ(message, "@test")

	copy(message, 191, "test")
	replace_all(message, 191, "t", "tt")
	ASSERT_STR_EQ(message, "ttestt")

	replace_all(message, 191, "tt", "")
	ASSERT_STR_EQ(message, "es")

	copy(message, 191, "good boys do fine always")
	replace_all(message, 191, " ", "-----")
	ASSERT_STR_EQ(message, "good-----boys-----do-----fine-----always")

	copy(message, 191, "-----")
	replace_all(message, 191, "-", "")
	ASSERT_STR_EQ(message, "")

	copy(message, 191, "-----")
	replace_all(message, 191, "--", "")
	ASSERT_STR_EQ(message, "-")

	copy(message, 191, "aaaa")
	replace_all(message, 191, "a", "Aaa")
	ASSERT_STR_EQ(message, "AaaAaaAaaAaa")

	bench_pass()
}
