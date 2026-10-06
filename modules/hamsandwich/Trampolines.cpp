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

// gamedata "vector_return" "registers" (config_parser.cpp, vector_return.h)
extern bool VectorReturnInRegisters;

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

	void *Install(CodeHolder& code, int *outSize)
	{
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

#if defined(__i386__)
	// i386 VectorSret: copy the incoming stack args (hidden pointer, this,
	// params) verbatim below the Hook*, call the dispatcher, then pop the
	// hidden pointer on return like the original virtual does.
	void *CreateSretTrampolineX86(CodeHolder& code, const HamSig::HookSignature& hs,
	                              void *extraptr, void *callee, int *outSize)
	{
		uint32_t bytes = 8;	// hidden pointer + this
		for (uint8_t i = 0; i < hs.paramCount; ++i)
			bytes += (hs.params[i] == HamSig::ParamKind::Vector) ? 12 : 4;

		x86::Assembler a(&code);
		a.push(x86::ebp);
		a.mov(x86::ebp, x86::esp);
		a.and_(x86::esp, -16);
		const uint32_t pushed = bytes + 4;	// args + Hook*
		const uint32_t pad = (16 - (pushed % 16)) % 16;
		if (pad)
			a.sub(x86::esp, pad);
		for (uint32_t off = bytes; off > 0; off -= 4)
			a.push(x86::dword_ptr(x86::ebp, int32_t(4 + off)));
		a.push(imm(uintptr_t(extraptr)));
		a.call(imm(uintptr_t(callee)));
		a.mov(x86::esp, x86::ebp);
		a.pop(x86::ebp);
		a.ret(4);

		return Install(code, outSize);
	}
#endif

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

	// How a by-value Vector param is laid out in a signature.
	//   Stack3:    i386: 3 Float stack slots copied verbatim (whatever the
	//              game put there, bit for bit).
	//   Registers: 64-bit game library whose Vector is trivially copyable
	//              ("vector_return" "registers"):
	//                amd64:   SysV splits the 12-byte struct in two
	//                         eightbytes, x/y packed in one XMM
	//                         (Float32x2) and z in the next (Float32).
	//                aarch64: HFA-3, one float each in three V registers.
	//   Pointer:   64-bit hidden pointer (the SDK Vector with its user-written
	//              copy constructor). Also how the C dispatchers take it.
	enum class VectorArg { Stack3, Registers, Pointer };

	// Append `this` then each named param to a FuncSignature being built.
	void append_args(FuncSignature& sig, const HamSig::HookSignature& hs, VectorArg vec)
	{
		sig.add_arg(TypeId::kIntPtr);	// 'this'
		for (uint8_t i = 0; i < hs.paramCount; ++i) {
			if (hs.params[i] != HamSig::ParamKind::Vector) {
				sig.add_arg(param_type_id(hs.params[i]));
			} else if (vec == VectorArg::Pointer) {
				sig.add_arg(TypeId::kIntPtr);
			} else {
#if defined(__x86_64__)
				sig.add_arg(TypeId::kFloat32x2);
				sig.add_arg(TypeId::kFloat32);
#else
				sig.add_arg(TypeId::kFloat32);
				sig.add_arg(TypeId::kFloat32);
				sig.add_arg(TypeId::kFloat32);
#endif
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

#if defined(__i386__)
	// i386 struct returns: the callee pops the hidden pointer (ret 4), which
	// a cdecl FuncSignature cannot describe.
	if (hs.ret == HamSig::ReturnKind::VectorSret)
		return CreateSretTrampolineX86(code, hs, extraptr, callee, outSize);
#endif

	NativeCompiler cc(&code);

	// By-value Vector params: verbatim stack slots on i386; on 64-bit the
	// game passes them as the gamedata says and the dispatchers take a pointer.
#if defined(__i386__)
	const VectorArg vec_in = VectorArg::Stack3;
	const VectorArg vec_out = VectorArg::Stack3;
#else
	const VectorArg vec_in = VectorReturnInRegisters ? VectorArg::Registers : VectorArg::Pointer;
	const VectorArg vec_out = VectorArg::Pointer;
#endif

	// Incoming signature: matches the original virtual method ABI.
	// VectorSret returns a hidden first-arg pointer (Linux/Mac sret style).
	FuncSignature incoming(CallConvId::kCDecl);
	incoming.set_ret(return_type_id(hs.ret));
	if (hs.ret == HamSig::ReturnKind::VectorSret)
		incoming.add_arg(TypeId::kIntPtr);
	append_args(incoming, hs, vec_in);

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
	append_args(outgoing, hs, vec_out);

	// Everything below up to invoke() runs before the call: the compiler
	// emits nodes in order, so code added after invoke() would run after it.
	Reg extra_reg = cc.new_gp_ptr();
	mov_imm_ptr(cc, extra_reg, uintptr_t(extraptr));

	// Outgoing args in order. A Vector that came in registers is stored to a
	// stack slot and passed by address, the way the dispatchers take it.
	std::vector<Reg> out_regs;
	out_regs.push_back(extra_reg);
	size_t in = 0;
	if (hs.ret == HamSig::ReturnKind::VectorSret)
		out_regs.push_back(arg_regs[in++]);
	out_regs.push_back(arg_regs[in++]);	// this
	for (uint8_t i = 0; i < hs.paramCount; ++i) {
		if (hs.params[i] != HamSig::ParamKind::Vector || vec_in == vec_out) {
			const size_t n = (hs.params[i] == HamSig::ParamKind::Vector && vec_in == VectorArg::Stack3) ? 3 : 1;
			for (size_t k = 0; k < n; ++k)
				out_regs.push_back(arg_regs[in++]);
			continue;
		}
#if defined(__x86_64__)
		x86::Mem slot = cc.new_stack(16, 16);
		cc.movq(slot, arg_regs[in++].as<x86::Vec>());
		cc.movss(slot.clone_adjusted(8), arg_regs[in++].as<x86::Vec>());
		x86::Gp addr = cc.new_gp_ptr();
		cc.lea(addr, slot);
		out_regs.push_back(addr);
#elif defined(__aarch64__)
		a64::Mem slot = cc.new_stack(16, 16);
		cc.str(arg_regs[in++].as<a64::Vec>(), slot);
		cc.str(arg_regs[in++].as<a64::Vec>(), slot.clone_adjusted(4));
		cc.str(arg_regs[in++].as<a64::Vec>(), slot.clone_adjusted(8));
		a64::Gp addr = cc.new_gp_ptr();
		cc.load_address_of(addr, slot);
		out_regs.push_back(addr);
#endif
	}

	InvokeNode *inv = invoke_target(cc, callee, outgoing);

	for (size_t i = 0; i < out_regs.size(); ++i)
		inv->set_arg(i, out_regs[i]);

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

	return Install(code, outSize);
}

#if defined(__x86_64__) || defined(__aarch64__)
void *CreateRegisterReturnTrampoline(const HamSig::HookSignature& hs,
                                     void *extraptr, void *callee,
                                     int *outSize)
{
	using namespace asmjit;

	// Integer-class args: 'this' plus every Int32/Pointer param. Floats and
	// Vectors travel in FP registers, which the inserted Hook* does not move.
	size_t gp = 1;
	for (uint8_t i = 0; i < hs.paramCount; ++i) {
		if (hs.params[i] == HamSig::ParamKind::Int32 ||
		    hs.params[i] == HamSig::ParamKind::Pointer)
			++gp;
	}

	CodeHolder code;
	if (code.init(jit_runtime().environment(), jit_runtime().cpu_features()) != kErrorOk)
		return nullptr;

	// Shift the integer args up one register, put extraptr first and tail-jump
	// to callee: its return registers reach the caller untouched.
#if defined(__x86_64__)
	static const x86::Gp args[] = { x86::rdi, x86::rsi, x86::rdx, x86::rcx, x86::r8, x86::r9 };
	if (gp + 1 > sizeof(args) / sizeof(args[0]))
		return nullptr;

	x86::Assembler a(&code);
	for (size_t i = gp; i > 0; --i)
		a.mov(args[i], args[i - 1]);
	a.mov(x86::rdi, imm(uintptr_t(extraptr)));
	a.mov(x86::rax, imm(uintptr_t(callee)));
	a.jmp(x86::rax);
#else
	if (gp + 1 > 8)
		return nullptr;

	a64::Assembler a(&code);
	for (size_t i = gp; i > 0; --i)
		a.mov(a64::x(uint32_t(i)), a64::x(uint32_t(i - 1)));
	a.mov(a64::x0, Imm(uintptr_t(extraptr)));
	a.mov(a64::x16, Imm(uintptr_t(callee)));
	a.br(a64::x16);
#endif

	return Install(code, outSize);
}
#endif

void FreeTrampoline(void *tramp, int size)
{
	if (tramp)
		FreeExec(tramp, size_t(size));
}

}	// namespace Trampolines

#endif	// !_WIN32
