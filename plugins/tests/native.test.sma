// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/native_test.sma: a plugin calling its own dynamic native,
// recursively.
//

#include <amxmodx>
#include <amxxbench>

native Factorial(num)

public __Factorial(plugin, params)
{
	new num = get_param(1)
	if (num == 0)
	{
		return 1
	}

	return num * Factorial(num - 1)
}

public plugin_natives()
{
	register_native("Factorial", "__Factorial")
}

public plugin_init()
{
	register_plugin("Native Test", "1.0", "BAILOPAN")
}

public test_native_factorial()
{
	new num = Factorial(6)
	ASSERT_EQ(num, 720)
	bench_pass()
}
