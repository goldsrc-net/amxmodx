// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

// Ported from plugins/testsuite/datapack_test.sma (datapacktest).

#include <amxmodx>
#include <amxxbench>

new DataPack:g_Pack;
new DataPack:g_NewPack;

public plugin_init()
{
	register_plugin("Datapack Test", AMXX_VERSION_STR, "AMXX Dev Team");
}

public bench_teardown()
{
	DestroyDataPack(g_Pack);
	DestroyDataPack(g_NewPack);
}

public test_write_read()
{
	g_Pack = CreateDataPack();

	new refCell = 23;
	new Float:refFloat = 42.42;
	new refString[] = "I'm a little teapot.";

	// Write
	new DataPackPos:cellPos = GetPackPosition(g_Pack);
	WritePackCell(g_Pack, refCell);
	new DataPackPos:floatPos = GetPackPosition(g_Pack);
	WritePackFloat(g_Pack, refFloat);
	new DataPackPos:strPos = GetPackPosition(g_Pack);
	WritePackString(g_Pack, refString);
	new DataPackPos:endPos = GetPackPosition(g_Pack);

	if (!bench_check(cellPos != floatPos && cellPos != strPos && cellPos != endPos
				&& floatPos != strPos && floatPos != endPos && strPos != endPos,
				"Write position test")) return;

	//resets the index to the beginning, necessary for read.
	ResetPack(g_Pack);

	if (!bench_check(GetPackPosition(g_Pack) == cellPos, "Position #1 test")) return;
	if (!bench_check(!IsPackEnded(g_Pack), "Readable #1 test")) return;

	new cellValue = ReadPackCell(g_Pack);
	if (!bench_check(cellValue == refCell, "Cell test")) return;

	if (!bench_check(GetPackPosition(g_Pack) == floatPos, "Position #2 test")) return;
	if (!bench_check(!IsPackEnded(g_Pack), "Readable #2 test")) return;

	new Float:floatValue = ReadPackFloat(g_Pack);
	if (!bench_check(floatValue == refFloat, "Float test")) return;

	if (!bench_check(GetPackPosition(g_Pack) == strPos, "Position #3 test")) return;
	if (!bench_check(!IsPackEnded(g_Pack), "Readable #3 test")) return;

	new buffer[1024];
	ReadPackString(g_Pack, buffer, 1024);
	if (!bench_check(bool:equal(buffer, refString), "String test #1")) return;

	if (!bench_check(IsPackEnded(g_Pack), "End test")) return;

	ResetPack(g_Pack, .clear = true);
	if (!bench_check(IsPackEnded(g_Pack), "Clear test")) return;

	DestroyDataPack(g_Pack);

	bench_pass();
}

// Makes sure that the datapack handle system recycles old handles
public test_recycle_handles()
{
	g_Pack = CreateDataPack();
	new DataPack:oldPack = g_Pack;

	DestroyDataPack(g_Pack);

	g_NewPack = CreateDataPack();
	if (!bench_check(g_NewPack == oldPack, "Recycle handles")) return;

	DestroyDataPack(g_NewPack);

	bench_pass();
}
