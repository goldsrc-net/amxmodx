// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Port of plugins/testsuite/fwdtest2.sma: calls natives that forward_provider.test.sma
// (fwdtest1.sma) provides, which create and execute a forward to a public of this plugin.
//

#include <amxmodx>
#include <amxxbench>

new g_id
new g_GabenCalls

native test_createforward(function[])
native test_executeforward()

public plugin_init()
{
	g_id = register_plugin("Forward Test (Client)", "1.0", "Belsebub")
}

XvarNum(const name[])
{
	new id = get_xvar_id(name)
	if (id < 0)
		return -2
	return get_xvar_num(id)
}

public test_forward_to_caller()
{
	g_GabenCalls = 0

	new fwd = test_createforward("gaben")
	new pluginid = XvarNum("g_FwdTestCreatePlugin")
	new numparams = XvarNum("g_FwdTestCreateParams")
	ASSERT(fwd >= 0)
	ASSERT_EQ(pluginid, g_id)
	ASSERT_EQ(numparams, 1)

	new executed = test_executeforward()
	pluginid = XvarNum("g_FwdTestExecPlugin")
	numparams = XvarNum("g_FwdTestExecParams")
	ASSERT_EQ(pluginid, g_id)
	ASSERT_EQ(numparams, 0)
	ASSERT_EQ(executed, 1)
	ASSERT_EQ(g_GabenCalls, 1)
	bench_pass()
}

public gaben()
{
	server_print("gaben executed (I'm %d)", g_id)
	g_GabenCalls++
}
