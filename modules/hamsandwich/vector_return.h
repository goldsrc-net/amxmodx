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
// How the game library passes Vector by value: as a return value and as a
// parameter. The SDK Vector this module is built with has a user-written copy
// constructor, which makes it non-trivial for calls: it is returned through a
// hidden pointer and passed as a pointer. A game library whose Vector is
// trivially copyable (halflife-updated: "= default") passes it in registers
// both ways on 64-bit targets (x86-64: x/y in one XMM, z in the next;
// AArch64: s0-s2 style HFA). The same property of the type decides both, so
// one gamedata key covers both: "vector_return" "registers". Anything else
// keeps the pointer convention. On i386 nothing changes: struct returns go
// through memory either way and by-value params are copied as stack slots.

#ifndef VECTOR_RETURN_H
#define VECTOR_RETURN_H

#include "amxxmodule.h"
#include <type_traits>

extern bool VectorReturnInRegisters;

// Trivially copyable, so the compiler passes and returns it the way such a game library does.
struct GameVector
{
	float x, y, z;
};

#if !defined(_WIN32)
// The type a game library using registers sees for T, and the conversions.
template <typename T> struct GameType
{
	typedef T type;
	static T to(T v) { return v; }
	static T from(T v) { return v; }
};

template <> struct GameType<void>
{
	typedef void type;
};

template <> struct GameType<Vector>
{
	typedef GameVector type;
	static GameVector to(const Vector &v) { GameVector g = { v.x, v.y, v.z }; return g; }
	static Vector from(const GameVector &g) { return Vector(g.x, g.y, g.z); }
};

// Call a game virtual of type F (written with the SDK Vector) the way the game
// library expects Vector returns and by-value Vector params.
template <typename F> struct GameCall;

template <typename R, typename... P> struct GameCall<R (*)(P...)>
{
	template <typename... A>
	static R call(void *func, A... args)
	{
#if !defined(__i386__)
		if (VectorReturnInRegisters)
		{
			typedef typename GameType<R>::type (*GameFunc)(typename GameType<P>::type...);

			if constexpr (std::is_void<R>::value)
			{
				reinterpret_cast<GameFunc>(func)(GameType<P>::to(static_cast<P>(args))...);
				return;
			}
			else
			{
				return GameType<R>::from(reinterpret_cast<GameFunc>(func)(GameType<P>::to(static_cast<P>(args))...));
			}
		}
#endif
		return reinterpret_cast<R (*)(P...)>(func)(static_cast<P>(args)...);
	}
};

template <typename... Args>
inline Vector CallVectorReturn(void *func, void *pthis, Args... args)
{
	return GameCall<Vector (*)(void *, Args...)>::call(func, pthis, args...);
}
#endif

// The register-returning counterpart of a Hook_Vector_* dispatcher, or NULL.
void *GetRegisterReturnDispatcher(void *target);

#endif // VECTOR_RETURN_H
