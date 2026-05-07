// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X — register_native gateway, aarch64.
//
// Mirrors natives-x86.asm / natives-amd64.asm: provides amxx_DynaInit,
// amxx_DynaMake, amxx_DynaCodesize so that register_native() in
// natives.cpp can synthesize a per-native AArch64 trampoline that
// forwards (AMX*, cell*) calls to amxx_DynaCallback(idx, AMX*, cell*).
//
// The trampoline is 8 fixed-shape A64 instructions (32 bytes) — no
// literal pool, addresses materialized via MOVZ/MOVK chain to avoid
// alignment constraints. amxx_DynaFunc has no aarch64 analogue (the
// asm-template-copy idiom does not apply here); the symbol is declared
// in natives.h but never referenced from C++.

#include <stdint.h>
#include "amx.h"

extern "C" {

static void* g_dyna_global_gate = nullptr;

void amxx_DynaInit(void* ptr) {
	g_dyna_global_gate = ptr;
}

int amxx_DynaCodesize(void) {
	return 32;
}

void amxx_DynaMake(char* buffer, int id) {
	uint32_t* code = reinterpret_cast<uint32_t*>(buffer);
	uintptr_t gw = reinterpret_cast<uintptr_t>(g_dyna_global_gate);

	// mov x2, x1               ; orr x2, xzr, x1
	code[0] = 0xAA0103E2u;
	// mov x1, x0               ; orr x1, xzr, x0
	code[1] = 0xAA0003E1u;
	// movz x0, #(id & 0xFFFF)  ; assumes id < 65536 (registry is per-AMX, well below)
	code[2] = 0xD2800000u | ((static_cast<uint32_t>(id) & 0xFFFFu) << 5);
	// movz/movk x16, gw — 4 instructions, 16-bit at a time
	code[3] = 0xD2800010u | (static_cast<uint32_t>((gw >>  0) & 0xFFFFu) << 5);                   // movz x16, #gw[15:0]
	code[4] = 0xF2A00010u | (static_cast<uint32_t>((gw >> 16) & 0xFFFFu) << 5);                   // movk x16, #gw[31:16], lsl #16
	code[5] = 0xF2C00010u | (static_cast<uint32_t>((gw >> 32) & 0xFFFFu) << 5);                   // movk x16, #gw[47:32], lsl #32
	code[6] = 0xF2E00010u | (static_cast<uint32_t>((gw >> 48) & 0xFFFFu) << 5);                   // movk x16, #gw[63:48], lsl #48
	// br x16
	code[7] = 0xD61F0200u;

	// I-cache invalidation for the freshly-emitted trampoline. Without
	// this, on AArch64 the CPU may execute stale I-cache entries since
	// data and instruction caches are not coherent.
	__builtin___clear_cache(reinterpret_cast<char*>(code),
	                        reinterpret_cast<char*>(code) + 32);
}

}  // extern "C"
