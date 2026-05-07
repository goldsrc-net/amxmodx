// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X — Fakemeta module
//
// Shared cell↔native-pointer handle table for fakemeta. Required on
// 64-bit hosts where PAWN_CELL_SIZE=32 cannot hold a native pointer
// directly. Used wherever fakemeta exposes a native pointer to a
// plugin as a cell — engine forward args (TraceResult*, clientdata_s*,
// entity_state_s*, usercmd_s*, char* infobuffer, set_t* pSet, etc.),
// plus explicit allocations like create_tr2 / create_kvd.
//
// Single global table; every fakemeta-exposed pointer round-trips
// through it. find_or_alloc gives a stable handle for the same
// pointer across calls.

#ifndef _FM_HANDLES_H_
#define _FM_HANDLES_H_

#include "amxxmodule.h"
#include "AMXModulePtrHandle.h"

extern PtrHandleTable<void> g_fm_ptr_handles;

inline cell fm_ptr_to_cell(const void *p)
{
	return g_fm_ptr_handles.find_or_alloc(const_cast<void *>(p));
}

template <typename T>
inline T *fm_cell_to_ptr(cell h)
{
	return reinterpret_cast<T *>(g_fm_ptr_handles.get(h));
}

inline bool fm_release_handle(cell h)
{
	return g_fm_ptr_handles.free(h);
}

#endif // _FM_HANDLES_H_
