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
// Trampoline emitter. Builds an executable thunk for each hooked virtual
// method that prepends the hook's `Hook*` pointer and forwards to a
// per-signature C dispatcher (Hook_<TAG>) declared in hook_callbacks.h.
//
// Win32: header-only legacy x86 byte-table implementation, kept because
// the msvc12 project doesn't build any .cpp files added under AMBuild.
// Linux/Mac (every arch): AsmJit-based emitter in Trampolines.cpp.

#ifndef TRAMPOLINES_H
#define TRAMPOLINES_H

#include "HookSignature.h"

namespace Trampolines
{
	// Build an executable trampoline matching `sig`'s incoming ABI; on
	// invocation it forwards to `callee` with `extraptr` as the first arg
	// (typically the owning Hook*), then the original this/args (with
	// the hidden sret pointer re-positioned for VectorSret returns to
	// match Linux/Mac sret-style Hook_Vector_<TAG> signatures).
	//
	// outSize receives the byte size of the emitted code; required by
	// FreeTrampoline on Linux (munmap needs the original length).
	void *CreateGenericTrampoline(const HamSig::HookSignature& sig,
	                              void *extraptr, void *callee,
	                              int *outSize);

	// Release a trampoline buffer previously returned by CreateGenericTrampoline.
	void FreeTrampoline(void *tramp, int size);
}

#if defined(_WIN32)
// ---------------------------------------------------------------------------
// Win32 inline implementation: legacy x86 byte-table emitter wrapped behind
// the new HookSignature-based API. Preserves the msvc12 build verbatim.
// ---------------------------------------------------------------------------

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#if _MSC_VER >= 1400
#ifdef offsetof
#undef offsetof
#endif
#endif
#include <windows.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <amtl/am-bits.h>

namespace Trampolines
{
namespace WinLegacy
{
	namespace Bytecode
	{
		const unsigned char codePrologue[]      = { 0x55, 0x89, 0xE5 };
		const unsigned char codeAlignStack16[]  = { 0x83, 0xE4, 0xF0 };
		const unsigned char codeAllocStack[]    = { 0x83, 0xEC, 0xFF };
		const unsigned int  codeAllocStackReplace = 2;
		const unsigned char codePushParam[]     = { 0xFF, 0x75, 0xFF };
		const unsigned int  codePushParamReplace = 2;
		const unsigned char codePushThis[]      = { 0x51 };       // push ecx
		const unsigned char codePushID[]        = { 0x68, 0xDE, 0xFA, 0xAD, 0xDE };
		const unsigned int  codePushIDReplace   = 1;
		const unsigned char codeCall[]          = { 0xB8, 0xDE, 0xFA, 0xAD, 0xDE, 0xFF, 0xD0 };
		const unsigned int  codeCallReplace     = 1;
		const unsigned char codeFreeStack[]     = { 0x81, 0xC4, 0xFF, 0xFF, 0xFF, 0xFF };
		const unsigned int  codeFreeStackReplace = 2;
		const unsigned char codeEpilogueN[]     = { 0x89, 0xEC, 0x5D, 0xC2, 0xCD, 0xAB };
		const int           codeEpilogueNReplace = 4;
	}

	class TrampolineMaker
	{
	private:
		unsigned char *m_buffer;
		int            m_size;
		int            m_mystack;
		int            m_calledstack;
		int            m_paramstart;
		int            m_maxsize;

		void Append(const unsigned char *src, size_t size)
		{
			int orig = m_size;
			m_size += int(size);

			if (m_buffer == NULL) {
				m_maxsize = 512;
				m_buffer = (unsigned char *)malloc(m_maxsize);
			} else if (m_size > m_maxsize) {
				m_maxsize = m_size + 512;
				m_buffer = (unsigned char *)realloc(m_buffer, m_maxsize);
			}

			unsigned char *dat = m_buffer + orig;
			while (orig < m_size) {
				*dat++ = *src++;
				orig++;
			}
		}
	public:
		TrampolineMaker()
			: m_buffer(NULL), m_size(0), m_mystack(0), m_calledstack(0),
			  m_paramstart(0), m_maxsize(0)
		{}

		void Prologue()
		{
			Append(Bytecode::codePrologue, sizeof(Bytecode::codePrologue));
			m_paramstart = 0;
		}

		void Epilogue(int howmuch)
		{
			unsigned char code[sizeof(Bytecode::codeEpilogueN)];
			memcpy(code, Bytecode::codeEpilogueN, sizeof(code));
			unsigned char *c = code + Bytecode::codeEpilogueNReplace;
			union { int i; unsigned char b[4]; } bi;
			bi.i = howmuch;
			*c++ = bi.b[0];
			*c++ = bi.b[1];
			Append(code, sizeof(code));
		}

		void EpilogueAndFree() { Epilogue(m_mystack); }

		void AlignStack16(int slots)
		{
			const size_t need     = slots * sizeof(void *);
			const size_t reserve  = ke::Align(need, 16);
			const size_t extra    = reserve - need;

			Append(Bytecode::codeAlignStack16, sizeof(Bytecode::codeAlignStack16));
			if (extra > 0) {
				unsigned char code[sizeof(Bytecode::codeAllocStack)];
				memcpy(code, Bytecode::codeAllocStack, sizeof(code));
				code[Bytecode::codeAllocStackReplace] = (unsigned char)extra;
				Append(code, sizeof(code));
			}
		}

		void PushThis()
		{
			Append(Bytecode::codePushThis, sizeof(Bytecode::codePushThis));
			m_calledstack += 4;
		}

		void PushNum(int Number)
		{
			unsigned char code[sizeof(Bytecode::codePushID)];
			memcpy(code, Bytecode::codePushID, sizeof(code));
			unsigned char *c = code + Bytecode::codePushIDReplace;
			union { int i; unsigned char b[4]; } bi;
			bi.i = Number;
			c[0] = bi.b[0]; c[1] = bi.b[1]; c[2] = bi.b[2]; c[3] = bi.b[3];
			Append(code, sizeof(code));
			m_calledstack += 4;
		}

		void PushParam(int which)
		{
			which = which * 4;
			which += m_paramstart + 4;

			unsigned char code[sizeof(Bytecode::codePushParam)];
			memcpy(code, Bytecode::codePushParam, sizeof(code));
			code[Bytecode::codePushParamReplace] = (unsigned char)which;
			Append(code, sizeof(code));

			m_calledstack += 4;
			m_mystack     += 4;
		}

		void Call(void *ptr)
		{
			unsigned char code[sizeof(Bytecode::codeCall)];
			memcpy(code, Bytecode::codeCall, sizeof(code));
			unsigned char *c = code + Bytecode::codeCallReplace;
			union { void *p; unsigned char b[4]; } bp;
			bp.p = ptr;
			c[0] = bp.b[0]; c[1] = bp.b[1]; c[2] = bp.b[2]; c[3] = bp.b[3];
			Append(code, sizeof(code));
		}

		void FreeStack(int howmuch)
		{
			unsigned char code[sizeof(Bytecode::codeFreeStack)];
			memcpy(code, Bytecode::codeFreeStack, sizeof(code));
			unsigned char *c = code + Bytecode::codeFreeStackReplace;
			union { int i; unsigned char b[4]; } bi;
			bi.i = howmuch;
			c[0] = bi.b[0]; c[1] = bi.b[1]; c[2] = bi.b[2]; c[3] = bi.b[3];
			Append(code, sizeof(code));
		}

		void FreeTargetStack() { FreeStack(m_calledstack); }

		void *Finish(int *size)
		{
			if (size) *size = m_size;
			void *ret = VirtualAlloc(NULL, m_size, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
			memcpy(ret, m_buffer, m_size);
			free(m_buffer);
			m_buffer = NULL;
			m_size = 0;
			m_mystack = 0;
			m_calledstack = 0;
			m_maxsize = 512;
			return ret;
		}
	};

	inline int CountStackSlots(const HamSig::HookSignature& sig)
	{
		int n = 0;
		if (sig.ret == HamSig::ReturnKind::VectorSret)
			n++;	// hidden sret slot occupies one stack dword
		for (uint8_t i = 0; i < sig.paramCount; ++i) {
			n += (sig.params[i] == HamSig::ParamKind::Vector) ? 3 : 1;
		}
		return n;
	}
}	// namespace WinLegacy

inline void *CreateGenericTrampoline(const HamSig::HookSignature& sig,
                                     void *extraptr, void *callee,
                                     int *outSize)
{
	using namespace WinLegacy;
	TrampolineMaker tramp;

	int paramcount = CountStackSlots(sig);

	tramp.Prologue();
	tramp.AlignStack16(paramcount + 2);	// stack args + this + extraptr

	while (paramcount) {
		tramp.PushParam(paramcount--);
	}
	tramp.PushThis();
	tramp.PushNum(int(reinterpret_cast<uintptr_t>(extraptr)));
	tramp.Call(callee);
	tramp.FreeTargetStack();
	tramp.EpilogueAndFree();

	return tramp.Finish(outSize);
}

inline void FreeTrampoline(void *tramp, int /*size*/)
{
	if (tramp) VirtualFree(tramp, 0, MEM_RELEASE);
}

}	// namespace Trampolines

#endif	// _WIN32

#endif	// TRAMPOLINES_H
