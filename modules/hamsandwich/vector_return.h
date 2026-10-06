// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Ham Sandwich Module
//
// How the game library returns a Vector from a virtual. The SDK Vector this
// module is built with has a user-written copy constructor, so it is returned
// through a hidden pointer. A game library whose Vector is trivially copyable
// (halflife-updated: "= default") returns it in registers on 64-bit targets
// (x86-64: xmm0/xmm1, AArch64: s0-s2). The gamedata key "vector_return"
// "registers" selects that; anything else keeps the hidden pointer. On i386
// every struct comes back through memory, so the key changes nothing there.

#ifndef VECTOR_RETURN_H
#define VECTOR_RETURN_H

#include "amxxmodule.h"

extern bool VectorReturnInRegisters;

// Trivially copyable, so the compiler returns it the way such a game library does.
struct VectorReturn
{
	float x, y, z;
};

#if !defined(_WIN32)
template <typename... Args>
inline Vector CallVectorReturn(void *func, void *pthis, Args... args)
{
#if !defined(__i386__)
	if (VectorReturnInRegisters)
	{
		VectorReturn ret = reinterpret_cast<VectorReturn (*)(void *, Args...)>(func)(pthis, args...);
		return Vector(ret.x, ret.y, ret.z);
	}
#endif
	return reinterpret_cast<Vector (*)(void *, Args...)>(func)(pthis, args...);
}
#endif

// The register-returning counterpart of a Hook_Vector_* dispatcher, or NULL.
void *GetRegisterReturnDispatcher(void *target);

#endif // VECTOR_RETURN_H
