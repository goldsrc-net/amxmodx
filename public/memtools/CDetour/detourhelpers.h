/**
 * vim: set ts=4 :
 * =============================================================================
 * SourceMod
 * Copyright (C) 2004-2010 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 */

#ifndef _INCLUDE_SOURCEMOD_DETOURHELPERS_H_
#define _INCLUDE_SOURCEMOD_DETOURHELPERS_H_

#include <stdint.h>
#include <string.h>

#if defined(__linux__) || defined(__APPLE__)
	#include <sys/mman.h>
	#include <unistd.h>
	#include <stdlib.h>
	#ifndef PAGE_SIZE
		#define	PAGE_SIZE	4096
	#endif
	#define ALIGN(ar) ((long)ar & ~(PAGE_SIZE-1))
	#define	PAGE_EXECUTE_READWRITE	PROT_READ|PROT_WRITE|PROT_EXEC
	#if defined(__linux)
		#include <malloc.h>
	#endif
#elif defined(WIN32)
	#include <windows.h>
#endif

/* Size of the gate-patch sequence written by DoGatePatch. patch_t::patch
 * must be at least this large (it is — 20 bytes). */
#if defined(__i386__) || (defined(_M_IX86) && !defined(_M_X64))
	#define DETOUR_GATE_SIZE 6
#elif defined(__x86_64__) || defined(_M_X64)
	#define DETOUR_GATE_SIZE 14
#elif defined(__aarch64__) || defined(_M_ARM64)
	#define DETOUR_GATE_SIZE 16
#else
	#error "Unsupported architecture for CDetour DoGatePatch"
#endif

struct patch_t
{
	patch_t()
	{
		patch[0] = 0;
		bytes = 0;
	}
	unsigned char patch[20];
	size_t bytes;
};

inline void ProtectMemory(void *addr, int length, int prot)
{
#if defined(__linux__) || defined(__APPLE__)
	void *addr2 = (void *)ALIGN(addr);
	mprotect(addr2, sysconf(_SC_PAGESIZE), prot);
#elif defined(WIN32)
	DWORD old_prot;
	VirtualProtect(addr, length, prot, &old_prot);
#endif
}

inline unsigned char *AllocatePageMemory(size_t size)
{
#if defined WIN32
	return (unsigned char *)VirtualAlloc(NULL, size, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
#elif defined __GNUC__
#if defined __APPLE__
	unsigned char *addr = (unsigned char *)valloc(size);
	mprotect(addr, size, PROT_READ | PROT_WRITE | PROT_EXEC);
#else
	unsigned char *addr = (unsigned char *)mmap(nullptr, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
#endif
	return addr;
#endif
}

inline void FreePageMemory(void *addr, size_t size)
{
#if defined(WIN32)
	VirtualFree(addr, 0, MEM_RELEASE);
#elif defined(__linux__)
	munmap(addr, size);
#else
	free(addr);
#endif
}

inline void SetMemPatchable(void *address, size_t size)
{
	ProtectMemory(address, (int)size, PAGE_EXECUTE_READWRITE);
}

/* DoGatePatch contract:
 *
 *   `target`   is the function entry being detoured. The first DETOUR_GATE_SIZE
 *              bytes are overwritten in place with an unconditional jump to
 *              the detour callback.
 *   `callback` is what DEREFERENCING will yield the actual function pointer.
 *              i.e. callers pass &someVoidStarField — the gate-patch reads
 *              the field's value at install time and embeds the function
 *              pointer in the gate sequence.
 *
 * On i386 the gate is `FF 25 [&storage]` — six bytes, indirect through the
 * storage cell so a runtime change to *storage automatically updates the
 * jump target. On amd64 / aarch64 we embed the function pointer's value
 * directly (the storage cell is read once at patch time); CDetour never
 * mutates detour_callback after CreateDetour() so this is equivalent in
 * behavior.
 */
inline void DoGatePatch(unsigned char *target, void *callback)
{
	SetMemPatchable(target, 20);

#if defined(__i386__) || (defined(_M_IX86) && !defined(_M_X64))
	/* FF 25 [imm32] — jmp [imm32] absolute indirect.
	 * imm32 = address of the storage cell (callback is &storage). */
	target[0] = 0xFF;
	target[1] = 0x25;
	*(uint32_t *)(target + 2) = (uint32_t)(uintptr_t)callback;

#elif defined(__x86_64__) || defined(_M_X64)
	/* FF 25 00 00 00 00 + 8-byte target = jmp qword ptr [rip+0]; .quad target.
	 * Read the function pointer once from *callback and inline it. */
	void *fnptr = *(void **)callback;
	target[0] = 0xFF;
	target[1] = 0x25;
	*(uint32_t *)(target + 2) = 0;
	*(uint64_t *)(target + 6) = (uint64_t)(uintptr_t)fnptr;

#elif defined(__aarch64__) || defined(_M_ARM64)
	/* LDR x16, [pc+8] ; BR x16 ; .quad target — 16 bytes.
	 * Read the function pointer once from *callback and inline it. */
	void *fnptr = *(void **)callback;
	uint32_t *t = (uint32_t *)target;
	t[0] = 0x58000050u;                 /* LDR  x16, [pc+8] */
	t[1] = 0xD61F0200u;                 /* BR   x16 */
	*(uint64_t *)(t + 2) = (uint64_t)(uintptr_t)fnptr;
#endif
}

inline void ApplyPatch(void *address, int offset, const patch_t *patch, patch_t *restore)
{
	ProtectMemory(address, 20, PAGE_EXECUTE_READWRITE);

	unsigned char *addr = (unsigned char *)address + offset;
	if (restore)
	{
		for (size_t i=0; i<patch->bytes; i++)
		{
			restore->patch[i] = addr[i];
		}
		restore->bytes = patch->bytes;
	}

	for (size_t i=0; i<patch->bytes; i++)
	{
		addr[i] = patch->patch[i];
	}
}

#endif //_INCLUDE_SOURCEMOD_DETOURHELPERS_H_
