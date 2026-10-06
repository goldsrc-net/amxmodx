// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

// Ported from plugins/testsuite/stacktest.sma (test_stack).

#include <amxmodx>
#include <amxxbench>

new Stack:g_Stack;

public plugin_init()
{
	register_plugin("Stack Tests", AMXX_VERSION_STR, "AMXX Dev Team");
}

public bench_teardown()
{
	DestroyStack(g_Stack);
}

public test_push_pop()
{
	new test[20];
	new buffer[42];

	test[0] = 5;
	test[1] = 7;

	g_Stack = CreateStack(30);
	{
		PushStackCell(g_Stack, 50);
		PushStackArray(g_Stack, test, 2);
		PushStackArray(g_Stack, test, 2);
		PushStackString(g_Stack, "space craaab");
		PushStackCell(g_Stack, 12);
	}

	if (!bench_check(IsStackEmpty(g_Stack) == false, "Size test #1")) return;

	PopStack(g_Stack);
	PopStackString(g_Stack, buffer, charsmax(buffer));
	if (!bench_check(bool:equal(buffer, "space craaab"), "String test")) return;

	test[0] = 0;
	test[1] = 0;
	if (!bench_check(test[0] == 0 && test[1] == 0, "Array test #1")) return;

	PopStackArray(g_Stack, test, 2);
	if (!bench_check(test[0] == 5 && test[1] == 7, "Array test #1")) return;

	PopStackCell(g_Stack, test[0], 1);
	if (!bench_check(test[0] == 7, "Value test #1")) return;

	PopStackCell(g_Stack, test[0]);
	if (!bench_check(test[0] == 50, "Value test #2")) return;

	if (!bench_check(IsStackEmpty(g_Stack) == true, "Size test #2")) return;

	DestroyStack(g_Stack);

	bench_pass();
}
