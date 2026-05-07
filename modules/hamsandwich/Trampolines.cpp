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
// AsmJit-based trampoline emitter (Linux/Mac, every supported arch).
// The Win32 path keeps a header-only x86 byte-table emitter inside
// Trampolines.h for compatibility with the msvc12 build.

#include "Trampolines.h"

#if !defined(_WIN32)

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <vector>

#if defined(__APPLE__) || defined(__linux__)
#include <sys/mman.h>
#endif
#if defined(__APPLE__)
#include <stdlib.h>		// valloc
#endif

#include <asmjit/core.h>
#if defined(__i386__) || defined(__x86_64__)
#  include <asmjit/x86.h>
#elif defined(__aarch64__)
#  include <asmjit/a64.h>
#else
#  error "Unsupported architecture for hamsandwich AsmJit trampolines"
#endif

namespace Trampolines
{

namespace
{
	using namespace asmjit;

	JitRuntime& jit_runtime()
	{
		static JitRuntime rt;
		return rt;
	}

	void *AllocExec(size_t size)
	{
#if defined(__APPLE__)
		void *p = valloc(size);
		if (!p) return nullptr;
		mprotect(p, size, PROT_READ | PROT_WRITE | PROT_EXEC);
		return p;
#else
		void *p = mmap(nullptr, size, PROT_READ | PROT_WRITE | PROT_EXEC,
		               MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		return (p == MAP_FAILED) ? nullptr : p;
#endif
	}

	void FreeExec(void *p, size_t size)
	{
#if defined(__APPLE__)
		(void)size;
		free(p);
#else
		munmap(p, size);
#endif
	}

	void FlushICache(void *p, size_t size)
	{
#if defined(__GNUC__) || defined(__clang__)
		__builtin___clear_cache(reinterpret_cast<char *>(p),
		                        reinterpret_cast<char *>(p) + size);
#else
		(void)p; (void)size;
#endif
	}

	TypeId param_type_id(HamSig::ParamKind k)
	{
		using HamSig::ParamKind;
		switch (k) {
		case ParamKind::Int32:		return TypeId::kInt32;
		case ParamKind::Float:		return TypeId::kFloat32;
		case ParamKind::Pointer:	return TypeId::kIntPtr;
		case ParamKind::Vector:		return TypeId::kFloat32;	// expanded externally
		}
		return TypeId::kIntPtr;
	}

	TypeId return_type_id(HamSig::ReturnKind r)
	{
		using HamSig::ReturnKind;
		switch (r) {
		case ReturnKind::Void:		return TypeId::kVoid;
		case ReturnKind::Int32:		return TypeId::kInt32;
		case ReturnKind::Float:		return TypeId::kFloat32;
		case ReturnKind::Pointer:	return TypeId::kIntPtr;
		case ReturnKind::VectorSret:	return TypeId::kVoid;	// becomes void+ptr-arg
		}
		return TypeId::kVoid;
	}

	// Append `this` then each named param to a FuncSignature being built.
	//
	// Vector (HL SDK 3-float struct) classification per arch:
	//   i386:    3 packed Float stack slots (everything is 4-byte stack on
	//            x86 cdecl/thiscall; the compiler lays them out adjacent).
	//   aarch64: HFA-3 → V0..V2 each holding one float. Expanding as 3
	//            successive Float args lands in V0/V1/V2 exactly per AAPCS64.
	//   amd64:   SysV classifies the 12-byte struct as two eightbytes —
	//            bytes 0-7 (two floats) → XMM-N as packed Float32x2;
	//            bytes 8-11 (one float) → XMM-(N+1) as Float32. AsmJit's
	//            TypeId::kFloat32x2 occupies the low 64 bits of an XMM
	//            register, matching what the C compiler emits for `Vector`
	//            by value.
	void append_args(FuncSignature& sig, const HamSig::HookSignature& hs)
	{
		sig.add_arg(TypeId::kIntPtr);	// 'this'
		for (uint8_t i = 0; i < hs.paramCount; ++i) {
			if (hs.params[i] == HamSig::ParamKind::Vector) {
#if defined(__x86_64__)
				sig.add_arg(TypeId::kFloat32x2);
				sig.add_arg(TypeId::kFloat32);
#else
				sig.add_arg(TypeId::kFloat32);
				sig.add_arg(TypeId::kFloat32);
				sig.add_arg(TypeId::kFloat32);
#endif
			} else {
				sig.add_arg(param_type_id(hs.params[i]));
			}
		}
	}

#if defined(__i386__) || defined(__x86_64__)
	using NativeCompiler = x86::Compiler;

	Reg new_float_vreg(NativeCompiler& cc) { return cc.new_xmm_ss(); }

	InvokeNode *invoke_target(NativeCompiler& cc, void *callee,
	                          const FuncSignature& sig)
	{
		InvokeNode *inv;
		cc.invoke(Out(inv), imm(uintptr_t(callee)), sig);
		return inv;
	}

	void mov_imm_ptr(NativeCompiler& cc, const Reg& dst, uintptr_t val)
	{
		cc.mov(dst.as<x86::Gp>(), imm(val));
	}
#elif defined(__aarch64__)
	using NativeCompiler = a64::Compiler;

	Reg new_float_vreg(NativeCompiler& cc) { return cc.new_vec_s(); }

	InvokeNode *invoke_target(NativeCompiler& cc, void *callee,
	                          const FuncSignature& sig)
	{
		// AArch64 BL is ±128 MB; materialize the target into a Gp first.
		a64::Gp target_reg = cc.new_gp_ptr();
		cc.mov(target_reg, Imm(uintptr_t(callee)));
		InvokeNode *inv;
		cc.invoke(Out(inv), target_reg, sig);
		return inv;
	}

	void mov_imm_ptr(NativeCompiler& cc, const Reg& dst, uintptr_t val)
	{
		cc.mov(dst.as<a64::Gp>(), Imm(val));
	}
#endif

	// Allocate a vreg appropriate for the given TypeId.
	Reg new_arg_vreg(NativeCompiler& cc, TypeId tid)
	{
		if (tid == TypeId::kFloat32 || tid == TypeId::kFloat64)
			return new_float_vreg(cc);
#if defined(__x86_64__)
		if (tid == TypeId::kFloat32x2) {
			// 2-float packed vector — full XMM (low 64 bits used by SysV).
			return cc.new_xmm();
		}
#endif
		return cc.new_gp_ptr();
	}
}	// namespace

void *CreateGenericTrampoline(const HamSig::HookSignature& hs,
                              void *extraptr, void *callee,
                              int *outSize)
{
	using namespace asmjit;

	CodeHolder code;
	if (code.init(jit_runtime().environment(), jit_runtime().cpu_features()) != kErrorOk)
		return nullptr;

	NativeCompiler cc(&code);

	// Incoming signature: matches the original virtual method ABI.
	// VectorSret returns a hidden first-arg pointer (Linux/Mac sret style).
	FuncSignature incoming(CallConvId::kCDecl);
	incoming.set_ret(return_type_id(hs.ret));
	if (hs.ret == HamSig::ReturnKind::VectorSret)
		incoming.add_arg(TypeId::kIntPtr);
	append_args(incoming, hs);

	FuncNode *fn = cc.add_func(incoming);

	const size_t arg_count = incoming.arg_count();
	std::vector<Reg> arg_regs;
	arg_regs.reserve(arg_count);
	for (size_t i = 0; i < arg_count; ++i) {
		Reg r = new_arg_vreg(cc, incoming.arg(i));
		fn->set_arg(i, r);
		arg_regs.push_back(r);
	}

	// Outgoing: prepend Hook* extraptr, keep VectorSret slot in same
	// position relative to the rest, then this + named args. Matches the
	// existing Linux/Mac Hook_<TAG> C signatures in hook_callbacks.h.
	FuncSignature outgoing(CallConvId::kCDecl);
	outgoing.set_ret(return_type_id(hs.ret));
	outgoing.add_arg(TypeId::kIntPtr);	// extraptr (Hook*)
	if (hs.ret == HamSig::ReturnKind::VectorSret)
		outgoing.add_arg(TypeId::kIntPtr);
	append_args(outgoing, hs);

	InvokeNode *inv = invoke_target(cc, callee, outgoing);

	// Materialize extraptr as the outgoing call's first arg.
	Reg extra_reg = cc.new_gp_ptr();
	mov_imm_ptr(cc, extra_reg, uintptr_t(extraptr));
	inv->set_arg(0, extra_reg);

	// Forward each incoming arg, shifted by +1 for the prepended extraptr.
	for (size_t i = 0; i < arg_count; ++i)
		inv->set_arg(i + 1, arg_regs[i]);

	if (hs.ret == HamSig::ReturnKind::Void ||
	    hs.ret == HamSig::ReturnKind::VectorSret) {
		cc.ret();
	} else if (hs.ret == HamSig::ReturnKind::Float) {
		Reg r = new_float_vreg(cc);
		inv->set_ret(0, r);
		cc.ret(r);
	} else {
		Reg r = cc.new_gp_ptr();
		inv->set_ret(0, r);
		cc.ret(r);
	}

	cc.end_func();
	if (cc.finalize() != kErrorOk)
		return nullptr;

	const size_t code_size = code.code_size();
	void *buf = AllocExec(code_size);
	if (!buf)
		return nullptr;

	if (code.relocate_to_base(uintptr_t(buf)) != kErrorOk) {
		FreeExec(buf, code_size);
		return nullptr;
	}
	code.copy_flattened_data(buf, code_size, CopySectionFlags::kPadSectionBuffer);
	FlushICache(buf, code_size);

	if (outSize)
		*outSize = int(code_size);
	return buf;
}

void FreeTrampoline(void *tramp, int size)
{
	if (tramp)
		FreeExec(tramp, size_t(size));
}

}	// namespace Trampolines

#endif	// !_WIN32
