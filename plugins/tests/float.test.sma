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

// With the optimizer on (core.ini's default), the core turns calls to float, floatmul, floatdiv,
// floatadd, floatsub, floatround and floatcmp into opcodes, so these run the JIT or interpreter's
// versions of them, not the natives in float.cpp.

new const Float:g_roundValues[] = { 239.63, -239.63, 2.5, -2.5, 0.25, -0.25, 7.0, -7.0, 0.0 };

// floatround_round, floatround_floor, floatround_ceil, floatround_tozero for each of g_roundValues.
new const g_roundExpected[sizeof g_roundValues][floatround_method] =
{
	{  240,  239,  240,  239 },
	{ -240, -240, -239, -239 },
	{    3,    2,    3,    2 },
	{   -2,   -3,   -2,   -2 },
	{    0,    0,    1,    0 },
	{    0,   -1,    0,    0 },
	{    7,    7,    7,    7 },
	{   -7,   -7,   -7,   -7 },
	{    0,    0,    0,    0 }
};

new const g_methodNames[floatround_method][] = { "round", "floor", "ceil", "tozero" };

public plugin_init()
{
	register_plugin("Float tests", "1.0", "AMX Mod X Dev Team");
}

public test_floatround_methods()
{
	new report[512], len;

	for (new i = 0; i < sizeof g_roundValues; i++)
	{
		for (new floatround_method:m = floatround_round; m <= floatround_tozero; m++)
		{
			new got = floatround(g_roundValues[i], m);

			if (got != g_roundExpected[i][m])
			{
				len += formatex(report[len], charsmax(report) - len, "%s%f %s: %d, expected %d",
					len ? "; " : "", g_roundValues[i], g_methodNames[m], got, g_roundExpected[i][m]);
			}
		}
	}

	if (len)
	{
		bench_fail("floatround gave %s", report);
		return;
	}

	bench_pass();
}

public test_float_arithmetic()
{
	new Float:a = 1.5, Float:b = -2.25;

	ASSERT_EQ(_:(a * b), _:-3.375);
	ASSERT_EQ(_:(b / a), _:-1.5);
	ASSERT_EQ(_:(a + b), _:-0.75);
	ASSERT_EQ(_:(a - b), _:3.75);
	ASSERT_EQ(_:(1.0 / 3.0 * 3.0), _:1.0);
	ASSERT_EQ(_:float(-7), _:-7.0);
	ASSERT_EQ(_:float(16777217), _:16777216.0);

	ASSERT_EQ(floatcmp(a, b), 1);
	ASSERT_EQ(floatcmp(b, a), -1);
	ASSERT_EQ(floatcmp(a, 1.5), 0);

	bench_pass();
}

public test_float_natives()
{
	ASSERT_EQ(_:floatfract(-1.25), _:0.75);
	ASSERT_EQ(_:floatfract(2.75), _:0.75);
	ASSERT_EQ(_:floatabs(-2.5), _:2.5);
	ASSERT_EQ(_:floatsqroot(6.25), _:2.5);
	ASSERT_EQ(_:floatpower(2.0, 10.0), _:1024.0);
	ASSERT_EQ(_:floatlog(1000.0, 10.0), _:3.0);
	ASSERT_EQ(_:floatstr("-2.5"), _:-2.5);
	ASSERT_EQ(_:floatsin(90.0, degrees), _:1.0);
	ASSERT_EQ(_:floatcos(0.0, degrees), _:1.0);
	ASSERT_EQ(_:floatatan2(1.0, 1.0, degrees), _:45.0);

	bench_pass();
}
