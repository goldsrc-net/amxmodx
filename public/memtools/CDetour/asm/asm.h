#ifndef __ASM_H__
#define __ASM_H__

/*
 * Per-arch instruction-prologue walker + gate helpers used by CDetour.
 *
 * Public API (same on every arch):
 *   copy_bytes(func, dest, required_len)
 *     Walks instructions starting at func, copying them into dest if dest!=NULL,
 *     until at least required_len bytes have been consumed. Fixes up PC-relative
 *     references that move (CALL/JMP imm32 on x86/x86_64; B/BL/ADR/ADRP on
 *     aarch64) so the copy in dest behaves identically to the original at func.
 *     Returns the number of bytes consumed from func.
 *
 *   inject_jmp(src, dest)
 *     Writes an unconditional jump from src to dest. Length depends on arch
 *     (use OP_JMP_SIZE).
 *
 *   fill_nop(src, len)
 *     Fills [src, src+len) with NOP / no-op padding. On aarch64 this is
 *     0x1F2003D5 (NOP) per 4-byte slot; on x86 / x86_64 it is single-byte 0x90.
 *
 *   eval_jump(src)
 *     Follows a single hop of unconditional jumps starting at src. Used by
 *     callers that want to skip over PLT/import-table thunks.
 *
 *   check_thunks(dest, pc)
 *     i386 GCC fPIC thunk fixup. No-op on every other arch.
 *
 * OP_JMP_SIZE is the length of the unconditional jump produced by inject_jmp.
 *   i386:    5  (E9 [rel32])
 *   amd64:  14  (FF 25 00 00 00 00 + 8-byte target)
 *   aarch64:16  (LDR x16, [pc+8]; BR x16; .quad target)
 *
 * Sized so patch_t::patch[20] in detourhelpers.h has room for any of them.
 */

#if defined(__i386__) || (defined(_M_IX86) && !defined(_M_X64))
	#define OP_JMP                  0xE9
	#define OP_JMP_SIZE             5
	#define OP_NOP                  0x90
	#define OP_NOP_SIZE             1
	#define OP_PREFIX               0xFF
	#define OP_JMP_SEG              0x25
	#define OP_JMP_BYTE             0xEB
	#define OP_JMP_BYTE_SIZE        2
#elif defined(__x86_64__) || defined(_M_X64)
	#define OP_JMP_SIZE             14    /* FF 25 00 00 00 00 + 8 bytes target */
	#define OP_NOP                  0x90
	#define OP_NOP_SIZE             1
	#define OP_PREFIX               0xFF
	#define OP_JMP_SEG              0x25
	#define OP_JMP_BYTE             0xEB
	#define OP_JMP_BYTE_SIZE        2
#elif defined(__aarch64__) || defined(_M_ARM64)
	#define OP_JMP_SIZE             16    /* LDR x16, [pc+8] ; BR x16 ; .quad target */
	#define OP_NOP_SIZE             4     /* aarch64 NOP is 4 bytes (0xD503201F) */
#else
	#error "Unsupported architecture for CDetour/asm"
#endif

#ifdef __cplusplus
extern "C" {
#endif

void check_thunks(unsigned char *dest, unsigned char *pc);

int copy_bytes(unsigned char *func, unsigned char *dest, int required_len);

void inject_jmp(void *src, void *dest);

void fill_nop(void *src, unsigned int len);

void *eval_jump(void *src);

#ifdef __cplusplus
}
#endif

#endif /* __ASM_H__ */
