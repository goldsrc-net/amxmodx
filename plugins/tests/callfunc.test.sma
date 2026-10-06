// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/callfunc_test.sma.
//

#include <amxmodx>
#include <amxxbench>

new bool:g_Received

public plugin_init()
{
	register_plugin("callfunc test", "1.0", "BAILOPAN")
}

public OnCallfuncReceived(num, str[], &val, array[], array2[], size, hello2[1])
{
	g_Received = true

	ASSERT_EQ(num, 5)
	ASSERT_STR_EQ(str, "Gaben")

	ASSERT_EQ(val, 62)
	val = 15
	ASSERT_EQ(size, 6)
	for (new i=0; i<size; i++)
	{
		if (!bench_check(array[i] == i, "array[i] == i"))
			return
	}
	for (new i=0; i<size; i++)
	{
		if (!bench_check(array2[i] == i, "array2[i] == i"))
			return
	}
	array[0] = 5
	array2[1] = 6
	hello2[0] = 25
}

public test_callfunc()
{
	new a = 62
	new hello[] = {0,1,2,3,4,5}
	new hello2[] = {9}
	new pm = 6
	new err

	g_Received = false

	if ((err=callfunc_begin("OnCallfuncReceived")) < 1)
	{
		bench_fail("Failed to call callfunc_begin()! Error: %d", err)

		return
	}
	callfunc_push_int(5)
	callfunc_push_str("Gaben")
	callfunc_push_intrf(a)
	callfunc_push_array(hello, pm)
	callfunc_push_array(hello, pm)
	callfunc_push_int(pm)
	callfunc_push_array(hello2, 1, false)
	callfunc_end()

	ASSERT(g_Received)
	ASSERT_EQ(a, 15)
	ASSERT_EQ(hello[0], 5)
	ASSERT_EQ(hello[1], 6)
	ASSERT_EQ(hello2[0], 9)

	bench_pass()
}
