// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/fwdreftest1.sma: executes forwards with FP_VAL_BYREF parameters into
// forward_ref_helper.test.sma (fwdreftest2.sma), which overwrites them with the values given to
// its fwdref_set_test_values command. The tests run the original server commands.
//

#include <amxmodx>
#include <amxxbench>

#define HELPER_FILE "tests/forward_ref_helper.test.amxx"

new g_hMultiForward;
new g_hOneForward;

new g_iEndValue1;
new Float:g_fEndValue2;
new bool:g_bExecuted;

public plugin_init()
{
	register_plugin("Forward Test (Reference) (1)", "1.0", "Ni3znajomy");

	g_hMultiForward = CreateMultiForward("multi_forward_reference", ET_IGNORE, FP_VAL_BYREF, FP_VAL_BYREF);
	g_hOneForward = CreateOneForward(find_plugin_byfile(HELPER_FILE), "one_forward_reference", FP_VAL_BYREF, FP_VAL_BYREF);

	register_srvcmd("fwdref_multi_test", "cmdForwardRefMultiTest");
	register_srvcmd("fwdref_one_test", "cmdForwardRefOneTest");
}

public bench_teardown()
{
	server_cmd("fwdref_set_test_values 0 0");
	server_exec();
}

public cmdForwardRefMultiTest()
{
	new sTestValue[10];

	read_argv(1, sTestValue, charsmax(sTestValue));
	new iTestValue1 = str_to_num(sTestValue);

	read_argv(2, sTestValue, charsmax(sTestValue));
	new Float:fTestValue2 = str_to_float(sTestValue);

	server_print("PLUGIN1: MULTI FORWARD START: val1 = %i | val2 = %f", iTestValue1, fTestValue2);
	new dump;
	g_bExecuted = ExecuteForward(g_hMultiForward, dump, iTestValue1, fTestValue2) != 0;
	server_print("PLUGIN1: MULTI FORWARD END: val1 = %i | val2 = %f", iTestValue1, fTestValue2);
	g_iEndValue1 = iTestValue1;
	g_fEndValue2 = fTestValue2;
}

public cmdForwardRefOneTest()
{
	new sTestValue[10];

	read_argv(1, sTestValue, charsmax(sTestValue));
	new iTestValue1 = str_to_num(sTestValue);

	read_argv(2, sTestValue, charsmax(sTestValue));
	new Float:fTestValue2 = str_to_float(sTestValue);

	server_print("PLUGIN1: ONE FORWARD START: val1 = %i | val2 = %f", iTestValue1, fTestValue2);
	new dump;
	g_bExecuted = ExecuteForward(g_hOneForward, dump, iTestValue1, fTestValue2) != 0;
	server_print("PLUGIN1: ONE FORWARD END: val1 = %i | val2 = %f", iTestValue1, fTestValue2);
	g_iEndValue1 = iTestValue1;
	g_fEndValue2 = fTestValue2;
}

// Runs "<command> 5 2.5" after the helper was told to answer with 1337 and 13.37, and checks both
// directions: what the helper's public received, and what came back by reference.
bool:CheckForwardReference(const command[])
{
	g_bExecuted = false;
	g_iEndValue1 = 0;
	g_fEndValue2 = 0.0;

	server_cmd("fwdref_set_test_values 1337 13.37");
	server_cmd("%s 5 2.5", command);
	server_exec();

	new received1 = get_xvar_num(get_xvar_id("g_iFwdRefReceived1"));
	new Float:received2 = get_xvar_float(get_xvar_id("g_fFwdRefReceived2"));

	if (!bench_check(g_bExecuted, "ExecuteForward succeeds"))
		return false;
	if (!bench_check(received1 == 5, "PLUGIN2 START: val1 = 5"))
		return false;
	if (!bench_check(received2 == 2.5, "PLUGIN2 START: val2 = 2.5"))
		return false;
	if (!bench_check(g_iEndValue1 == 1337, "PLUGIN1 END: val1 = 1337"))
		return false;
	return bench_check(floatabs(g_fEndValue2 - 13.37) < 0.0001, "PLUGIN1 END: val2 = 13.37");
}

public test_multi_forward_reference()
{
	ASSERT(g_hMultiForward >= 0);
	if (!CheckForwardReference("fwdref_multi_test"))
		return;
	bench_pass();
}

public test_one_forward_reference()
{
	ASSERT(find_plugin_byfile(HELPER_FILE) >= 0);
	ASSERT(g_hOneForward >= 0);
	if (!CheckForwardReference("fwdref_one_test"))
		return;
	bench_pass();
}
