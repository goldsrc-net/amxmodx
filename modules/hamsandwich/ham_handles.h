// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X — Ham Sandwich module
//
// Cell↔native-pointer handle table. Required on 64-bit hosts where
// PAWN_CELL_SIZE=32 cannot hold a native pointer directly. Used wherever
// hamsandwich exposes a native pointer to a plugin as a cell — Forward*
// returned by RegisterHam / RegisterHamFromEntity, ItemInfo* returned
// by CreateHamItemInfo, etc. Round-trips are stable: find_or_alloc
// gives the same handle for the same pointer across calls.

#ifndef _HAM_HANDLES_H_
#define _HAM_HANDLES_H_

#include "amxxmodule.h"
#include "AMXModulePtrHandle.h"

extern PtrHandleTable<void> g_ham_ptr_handles;

inline cell ham_ptr_to_cell(const void *p)
{
	return g_ham_ptr_handles.find_or_alloc(const_cast<void *>(p));
}

template <typename T>
inline T *ham_cell_to_ptr(cell h)
{
	return reinterpret_cast<T *>(g_ham_ptr_handles.get(h));
}

inline bool ham_release_handle(cell h)
{
	return g_ham_ptr_handles.free(h);
}

#endif // _HAM_HANDLES_H_
