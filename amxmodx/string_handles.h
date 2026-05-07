// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Cell-sized handle table for plugin-visible cell* string pointers.
// PAWN_CELL_SIZE=32 cannot hold a native pointer on 64-bit hosts;
// ArrayGetStringHandle (DoNotUse) returns one such handle, and the
// %a format specifier consumes them. Both ends round-trip through
// this single shared table so the cell value stays stable across
// natives.

#ifndef _AMXX_STRING_HANDLES_H
#define _AMXX_STRING_HANDLES_H

#include "amx.h"
#include "AMXModulePtrHandle.h"

inline PtrHandleTable<cell> &g_amxx_string_handles()
{
	static PtrHandleTable<cell> tbl;
	return tbl;
}

#endif // _AMXX_STRING_HANDLES_H
