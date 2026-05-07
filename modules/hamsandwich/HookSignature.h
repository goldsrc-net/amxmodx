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
// Per-hook ABI descriptor. AsmJit's FuncSignature needs the type of every
// parameter to pick GPR vs FP register vs stack on amd64/aarch64. The
// existing PC_*_* paramcount-only descriptor only worked for x86 where
// every named param is a 4-byte stack slot.

#ifndef HOOK_SIGNATURE_H
#define HOOK_SIGNATURE_H

#include <stdint.h>

namespace HamSig {

enum class ParamKind : uint8_t {
	Int32,		// int, bool, short, etc. — passes in GPR / 32-bit-promoted stack slot
	Float,		// float — passes in XMM/V register on amd64/aarch64
	Pointer,	// any pointer / Cbase / entvars_t* / edict_t* / const char* etc.
	Vector,		// HL SDK Vector by value (3 floats); see emitter for ABI handling
};

enum class ReturnKind : uint8_t {
	Void,
	Int32,
	Float,
	Pointer,
	VectorSret,	// Returned via hidden first-arg pointer (Linux/Mac sret style)
};

struct HookSignature
{
	ReturnKind	ret;
	uint8_t		paramCount;	// count of named params after 'this'
	ParamKind	params[16];
};

} // namespace HamSig

#endif // HOOK_SIGNATURE_H
