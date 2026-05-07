// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X — generic native-pointer-to-cell handle table.
//
// PAWN_CELL_SIZE=32 is fixed by the Pawn ABI and does not widen on
// 64-bit hosts. Modules that historically returned a native pointer
// to plugins via reinterpret_cast<cell>(ptr) silently truncate on
// amd64/aarch64. This template wraps the pattern in a 1-based index
// table: cell handles stay 32-bit, pointers stay native-sized.
//
// Usage:
//   static PtrHandleTable<TraceResult> g_tr_handles;
//   ...
//   cell h  = g_tr_handles.alloc(tr);          // create handle
//   TraceResult *tr = g_tr_handles.get(h);     // round-trip
//   bool   wasFreed = g_tr_handles.free(h);    // optional release
//
// Notes:
//  - Handle 0 is reserved for nullptr / "invalid".
//  - Handles are per-table; two tables of different types use
//    independent index spaces.
//  - free(h) releases the slot; alloc() may reuse freed slots.
//  - Not thread-safe; HL is single-threaded.
//  - Lifetime is the module's lifetime by default; clear() on plugin
//    unload if the module wants tighter scoping.

#ifndef _AMXMODX_PTR_HANDLE_H_
#define _AMXMODX_PTR_HANDLE_H_

#include <stddef.h>
#include <amtl/am-vector.h>
#include "amxxmodule.h"

template <typename T>
class PtrHandleTable
{
public:
	PtrHandleTable() : m_freelist() {}

	// Allocate a new handle for ptr. nullptr maps to handle 0.
	cell alloc(T *ptr)
	{
		if (!ptr)
			return 0;

		if (!m_freelist.empty())
		{
			size_t idx = m_freelist.back();
			m_freelist.pop();
			m_entries[idx] = ptr;
			return static_cast<cell>(idx + 1);
		}

		m_entries.append(ptr);
		return static_cast<cell>(m_entries.length());
	}

	// Resolve a handle. Returns nullptr for handle 0, out-of-range,
	// or freed slots.
	T *get(cell handle) const
	{
		if (handle <= 0)
			return nullptr;
		size_t idx = static_cast<size_t>(handle) - 1;
		if (idx >= m_entries.length())
			return nullptr;
		return m_entries[idx];
	}

	// Release a handle. Returns true if the handle was live.
	bool free(cell handle)
	{
		if (handle <= 0)
			return false;
		size_t idx = static_cast<size_t>(handle) - 1;
		if (idx >= m_entries.length() || m_entries[idx] == nullptr)
			return false;
		m_entries[idx] = nullptr;
		m_freelist.append(idx);
		return true;
	}

	// Find an existing handle for ptr (linear scan), or allocate one.
	// Useful for consistency: same pointer always maps to same cell.
	cell find_or_alloc(T *ptr)
	{
		if (!ptr)
			return 0;
		for (size_t i = 0; i < m_entries.length(); ++i)
		{
			if (m_entries[i] == ptr)
				return static_cast<cell>(i + 1);
		}
		return alloc(ptr);
	}

	// Drop everything. Use on plugin unload if tighter scoping wanted.
	void clear()
	{
		m_entries.clear();
		m_freelist.clear();
	}

	size_t live_count() const
	{
		return m_entries.length() - m_freelist.length();
	}

private:
	ke::Vector<T *>     m_entries;
	ke::Vector<size_t>  m_freelist;
};

#endif // _AMXMODX_PTR_HANDLE_H_
