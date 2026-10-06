// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/fwdtest1.sma: the plugin that provides the natives. The tests are in
// forward.test.sma (fwdtest2.sma), which calls them. What the original printed about each call
// is kept in public variables that forward.test.sma reads as xvars, and the natives return their
// results.
//

#include <amxmodx>

new g_forward
new g_id

public g_FwdTestCreatePlugin = -1
public g_FwdTestCreateParams = -1
public g_FwdTestExecPlugin = -1
public g_FwdTestExecParams = -1

public plugin_init()
{
	g_id = register_plugin("Foward Test (Master)", "1.0", "Belsebub")
}

public plugin_natives()
{
	register_native("test_createforward", "_test_createforward_handler")
	register_native("test_executeforward", "_test_executeforward_handler")
}

//test_createforward(function[])
public _test_createforward_handler(pluginid, numparams)
{
	server_print("(test_createforward_handler: %d,%d)", pluginid, numparams)
	g_FwdTestCreatePlugin = pluginid
	g_FwdTestCreateParams = numparams

	new function[32]
	get_string(1, function, 31)

	if (g_forward > 0)
	{
		DestroyForward(g_forward)
	}

	g_forward = CreateOneForward(pluginid, function)
	if (g_forward < 0)
	{
		server_print("Failed to create forward!")
	}

	return g_forward
}

//test_executeforward()
public _test_executeforward_handler(pluginid, numparams)
{
	new retval

	server_print("(test_executeforward_handler: %d,%d)", pluginid, numparams)
	g_FwdTestExecPlugin = pluginid
	g_FwdTestExecParams = numparams

	new result = ExecuteForward(g_forward, retval)
	if (!result)
	{
		server_print("failed to execute forward (I'm %d)", g_id)
	}

	if (g_forward > 0)
	{
		DestroyForward(g_forward)
		g_forward = -1
	}

	return result
}
