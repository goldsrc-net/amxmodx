#include "asm.h"

#include <stdint.h>
#include <string.h>

/* ===========================================================================
 * Common helpers
 * =========================================================================*/

void fill_nop(void *src, unsigned int len)
{
	unsigned char *s = (unsigned char *)src;
#if defined(__aarch64__) || defined(_M_ARM64)
	/* aarch64 NOP is the 4-byte instruction 0xD503201F. Pad in 4-byte units;
	 * len is expected to be a multiple of 4 on this arch. */
	uint32_t *t = (uint32_t *)src;
	unsigned int n = len / 4;
	while (n--) {
		*t++ = 0xD503201Fu;
	}
	(void)s;
#else
	while (len) {
		*s++ = 0x90; /* x86 NOP */
		--len;
	}
#endif
}

void *eval_jump(void *src)
{
	unsigned char *addr = (unsigned char *)src;
	if (!addr) return 0;

#if defined(__i386__) || defined(__x86_64__) || defined(_M_IX86) || defined(_M_X64)
	/* PLT-style indirect import: FF 25 [...] */
	if (addr[0] == 0xFF && addr[1] == 0x25) {
		addr += 2;
		#if defined(__x86_64__) || defined(_M_X64)
			/* RIP-relative on amd64 */
			int32_t rel = *(int32_t *)addr;
			void **slot = (void **)(addr + 4 + rel);
			return *slot;
		#else
			/* Absolute on i386 */
			addr = *(unsigned char **)addr;
			return *(void **)addr;
		#endif
	}
	/* 8-bit relative jmp */
	if (addr[0] == 0xEB) {
		addr = &addr[2] + *(char *)&addr[1];
		if (addr[0] == 0xE9) {
			addr = addr + 5 + *(int *)&addr[1];
		}
		return addr;
	}
	/* 32-bit relative jmp */
	if (addr[0] == 0xE9) {
		addr = addr + 5 + *(int *)&addr[1];
	}
#elif defined(__aarch64__) || defined(_M_ARM64)
	/* Unconditional B (imm26): bits 31-26 = 000101 */
	uint32_t insn = *(uint32_t *)addr;
	if ((insn & 0xFC000000u) == 0x14000000u) {
		int32_t imm26 = (int32_t)(insn & 0x03FFFFFFu);
		if (imm26 & 0x02000000) imm26 |= 0xFC000000; /* sign-extend */
		return (void *)(addr + (intptr_t)imm26 * 4);
	}
#endif
	return addr;
}

/* ===========================================================================
 * i386 specific (legacy x86 fPIC thunk fixup + classic length decoder)
 * =========================================================================*/

#if defined(__i386__) || (defined(_M_IX86) && !defined(_M_X64))

#define REG_EAX 0
#define REG_ECX 1
#define REG_EDX 2
#define REG_EBX 3
#define IA32_MOV_REG_IMM 0xB8

void check_thunks(unsigned char *dest, unsigned char *pc)
{
	/* Step write address back 4 to the start of the function address */
	unsigned char *writeaddr = dest - 4;
	unsigned char *calloffset = *(unsigned char **)writeaddr;
	unsigned char *calladdr = (unsigned char *)(dest + (intptr_t)calloffset);

	/* Lookup name of function being called */
	if ((*calladdr == 0x8B) && (*(calladdr+2) == 0x24) && (*(calladdr+3) == 0xC3)) {
		char movByte = IA32_MOV_REG_IMM;
		switch (*(calladdr+1)) {
		case 0x04: movByte += REG_EAX; break;
		case 0x1C: movByte += REG_EBX; break;
		case 0x0C: movByte += REG_ECX; break;
		case 0x14: movByte += REG_EDX; break;
		default: break;
		}
		writeaddr--;
		*writeaddr = movByte;
		writeaddr++;
		*(void **)writeaddr = (void *)pc;
	}
}

/* if dest is NULL, returns minimum number of bytes needed to be copied
 * if dest is not NULL, copies bytes to dest as well as fixes CALLs and JMPs */
int copy_bytes(unsigned char *func, unsigned char *dest, int required_len)
{
	int bytecount = 0;

	while (bytecount < required_len && *func != 0xCC) {
		int operandSize = 4;
		int FPU = 0;
		int twoByte = 0;
		unsigned char opcode = 0x90;
		unsigned char modRM = 0xFF;

		while (*func == 0xF0 || *func == 0xF2 || *func == 0xF3 ||
		       (*func & 0xFC) == 0x64 || (*func & 0xF8) == 0xD8 ||
		       (*func & 0x7E) == 0x62) {
			if (*func == 0x66) {
				operandSize = 2;
			} else if ((*func & 0xF8) == 0xD8) {
				FPU = *func;
				if (dest) *dest++ = *func++; else func++;
				bytecount++;
				break;
			}
			if (dest) *dest++ = *func++; else func++;
			bytecount++;
		}

		if (*func == 0x0F) {
			twoByte = 1;
			if (dest) *dest++ = *func++; else func++;
			bytecount++;
		}

		opcode = *func++;
		if (dest) *dest++ = opcode;
		bytecount++;

		modRM = 0xFF;
		if (FPU) {
			if ((opcode & 0xC0) != 0xC0) modRM = opcode;
		} else if (!twoByte) {
			if ((opcode & 0xC4) == 0x00 ||
			    ((opcode & 0xF4) == 0x60 && ((opcode & 0x0A) == 0x02 || (opcode & 0x09) == 0x09)) ||
			    (opcode & 0xF0) == 0x80 ||
			    ((opcode & 0xF8) == 0xC0 && (opcode & 0x0E) != 0x02) ||
			    (opcode & 0xFC) == 0xD0 ||
			    (opcode & 0xF6) == 0xF6) {
				modRM = *func++;
				if (dest) *dest++ = modRM;
				bytecount++;
			}
		} else {
			if (((opcode & 0xF0) == 0x00 && (opcode & 0x0F) >= 0x04 && (opcode & 0x0D) != 0x0D) ||
			    (opcode & 0xF0) == 0x30 || opcode == 0x77 ||
			    (opcode & 0xF0) == 0x80 ||
			    ((opcode & 0xF0) == 0xA0 && (opcode & 0x07) <= 0x02) ||
			    (opcode & 0xF8) == 0xC8) {
				/* No mod R/M byte */
			} else {
				modRM = *func++;
				if (dest) *dest++ = modRM;
				bytecount++;
			}
		}

		if ((modRM & 0x07) == 0x04 && (modRM & 0xC0) != 0xC0) {
			if (dest) *dest++ = *func++; else func++;
			bytecount++;
		}

		if ((modRM & 0xC5) == 0x05) {
			if (dest) { *(unsigned int *)dest = *(unsigned int *)func; dest += 4; }
			func += 4; bytecount += 4;
		}
		if ((modRM & 0xC0) == 0x40) {
			if (dest) *dest++ = *func++; else func++;
			bytecount++;
		}
		if ((modRM & 0xC0) == 0x80) {
			if (dest) { *(unsigned int *)dest = *(unsigned int *)func; dest += 4; }
			func += 4; bytecount += 4;
		}

		if (FPU) {
			/* No immediate operand */
		} else if (!twoByte) {
			if ((opcode & 0xC7) == 0x04 ||
			    (opcode & 0xFE) == 0x6A || (opcode & 0xF0) == 0x70 ||
			    opcode == 0x80 || opcode == 0x83 ||
			    (opcode & 0xFD) == 0xA0 || opcode == 0xA8 ||
			    (opcode & 0xF8) == 0xB0 || (opcode & 0xFE) == 0xC0 ||
			    opcode == 0xC6 || opcode == 0xCD ||
			    (opcode & 0xFE) == 0xD4 || (opcode & 0xF8) == 0xE0 ||
			    opcode == 0xEB ||
			    (opcode == 0xF6 && (modRM & 0x30) == 0x00)) {
				if (dest) *dest++ = *func++; else func++;
				bytecount++;
			} else if ((opcode & 0xF7) == 0xC2) {
				if (dest) { *(unsigned short *)dest = *(unsigned short *)func; dest += 2; }
				func += 2; bytecount += 2;
			} else if ((opcode & 0xFC) == 0x80 || (opcode & 0xC7) == 0x05 ||
			           (opcode & 0xF8) == 0xB8 || (opcode & 0xFE) == 0xE8 ||
			           (opcode & 0xFE) == 0x68 || (opcode & 0xFC) == 0xA0 ||
			           (opcode & 0xEE) == 0xA8 || opcode == 0xC7 ||
			           (opcode == 0xF7 && (modRM & 0x30) == 0x00)) {
				if (dest) {
					if ((opcode & 0xFE) == 0xE8) {
						if (operandSize == 4) {
							*(long *)dest = ((func + *(long *)func) - dest);
							check_thunks(dest+4, func+4);
						} else {
							*(short *)dest = ((func + *(short *)func) - dest);
						}
					} else {
						if (operandSize == 4)
							*(unsigned long *)dest = *(unsigned long *)func;
						else
							*(unsigned short *)dest = *(unsigned short *)func;
					}
					dest += operandSize;
				}
				func += operandSize; bytecount += operandSize;
			}
		} else {
			if (opcode == 0xBA || opcode == 0x0F ||
			    (opcode & 0xFC) == 0x70 || (opcode & 0xF7) == 0xA4 ||
			    opcode == 0xC2 || opcode == 0xC4 ||
			    opcode == 0xC5 || opcode == 0xC6) {
				if (dest) *dest++ = *func++; else func++;
			} else if ((opcode & 0xF0) == 0x80) {
				if (dest) {
					if (operandSize == 4)
						*(unsigned long *)dest = *(unsigned long *)func;
					else
						*(unsigned short *)dest = *(unsigned short *)func;
					dest += operandSize;
				}
				func += operandSize; bytecount += operandSize;
			}
		}
	}

	return bytecount;
}

void inject_jmp(void *src, void *dest)
{
	*(unsigned char *)src = 0xE9;
	*(int32_t *)((unsigned char *)src + 1) =
		(int32_t)((unsigned char *)dest - ((unsigned char *)src + 5));
}

#endif /* __i386__ */

/* ===========================================================================
 * x86_64 specific
 *
 * Length-decoder + per-instruction copy with PC-relative fixup. Handles the
 * common GCC-emitted prologue/body patterns: REX-prefixed MOV / PUSH / POP /
 * SUB / ADD / LEA / TEST, SIB+disp addressing, RIP-relative loads, JMP/CALL
 * imm32 (rewritten to point to the original target, or absolute via FF 25
 * literal-pool when range exceeds rel32). Bails (returns bytecount so far)
 * on any unrecognized opcode rather than guessing.
 * =========================================================================*/

#if defined(__x86_64__) || defined(_M_X64)

void check_thunks(unsigned char *dest, unsigned char *pc)
{
	/* GCC i386 fPIC thunk pattern doesn't exist in x86_64 PIC code (RIP-relative
	 * addressing replaced it). Nothing to fix up. */
	(void)dest; (void)pc;
}

void inject_jmp(void *src, void *dest)
{
	unsigned char *s = (unsigned char *)src;
	/* FF 25 00 00 00 00 + 8-byte target = 14-byte indirect jump.
	 * jmp qword ptr [rip+0]; .quad dest */
	s[0] = 0xFF;
	s[1] = 0x25;
	s[2] = 0x00; s[3] = 0x00; s[4] = 0x00; s[5] = 0x00;
	*(uint64_t *)(s + 6) = (uint64_t)(uintptr_t)dest;
}

/* Decode one x86_64 instruction starting at `func`. Returns its length in
 * bytes. If `dest` is non-NULL, copies the instruction bytes to dest with
 * PC-relative imm32s rewritten so the copy targets the same absolute
 * address (CALL/JMP rel32, Jcc rel32, RIP-relative ModRM disp32 loads).
 *
 * Returns 0 on unrecognized opcode (caller should stop walking). */
static int decode_one_x64(unsigned char *func, unsigned char *dest, intptr_t copy_delta)
{
	unsigned char *p = func;
	unsigned char *out = dest;
	int op_size = 4;     /* default operand size; 0x66 → 2, REX.W → 8 */
	int addr_size = 8;   /* default address size in 64-bit mode; 0x67 → 4 */
	int twoByte = 0;
	int threeByte = 0;
	unsigned char rex = 0;
	unsigned char op = 0;
	unsigned char modrm = 0;
	int has_modrm = 0;
	int imm_size = 0;
	int rip_relative = 0;
	int is_branch_imm32 = 0;   /* call/jmp/Jcc with rel32; needs fixup on copy */
	int is_jcc_short = 0;      /* jmp short / Jcc short with rel8; not patched (in-bound) */

	/* Legacy prefixes (group 1-4). Multiple allowed in any order. */
	for (;;) {
		unsigned char c = *p;
		if (c == 0xF0 || c == 0xF2 || c == 0xF3 ||
		    c == 0x2E || c == 0x36 || c == 0x3E || c == 0x26 ||
		    c == 0x64 || c == 0x65) {
			p++;
			continue;
		}
		if (c == 0x66) { op_size = 2; p++; continue; }
		if (c == 0x67) { addr_size = 4; p++; continue; }
		break;
	}

	/* REX prefix (0x40-0x4F). */
	if ((*p & 0xF0) == 0x40) {
		rex = *p++;
		if (rex & 0x08) op_size = 8; /* REX.W */
	}

	/* Opcode (1, 2, or 3 bytes). */
	op = *p++;
	if (op == 0x0F) {
		twoByte = 1;
		op = *p++;
		if (op == 0x38 || op == 0x3A) {
			threeByte = 1;
			op = *p++;
		}
	}

	/* Decode based on opcode. We recognize the patterns used in compiler-emitted
	 * function prologues and the few that appear inside copy ranges. The big
	 * categories: */
	if (!twoByte && !threeByte) {
		/* one-byte opcodes */
		switch (op & 0xF8) {
		case 0x00: case 0x08: case 0x10: case 0x18: case 0x20: case 0x28: case 0x30: case 0x38:
			/* arithmetic Eb/Ev,Gb/Gv etc. */
			if ((op & 0x06) <= 0x03) { has_modrm = 1; }
			else if (op & 0x04) { imm_size = (op & 0x01) ? op_size : 1; }
			break;
		case 0x40: /* 0x40-0x47 INC reg in 32-bit, REX-handled above in 64-bit */
		case 0x48: /* 0x48-0x4F DEC/REX */
			/* should have been consumed as REX */
			return 0;
		case 0x50: /* PUSH r64 */
		case 0x58: /* POP r64 */
			break;
		case 0x68:
			if (op == 0x68) imm_size = 4; /* PUSH imm32 */
			else if (op == 0x6A) imm_size = 1; /* PUSH imm8 */
			else if (op == 0x69) { has_modrm = 1; imm_size = op_size; } /* IMUL r,rm,imm */
			else if (op == 0x6B) { has_modrm = 1; imm_size = 1; }       /* IMUL r,rm,imm8 */
			break;
		case 0x70: case 0x78: /* Jcc rel8 */
			imm_size = 1;
			is_jcc_short = 1;
			break;
		case 0x80:
			if ((op & 0x07) <= 1) { has_modrm = 1; imm_size = (op & 0x01) ? op_size : 1; }
			else if (op == 0x83) { has_modrm = 1; imm_size = 1; }
			else if (op == 0x84 || op == 0x85 || op == 0x86 || op == 0x87) { has_modrm = 1; }
			else if (op == 0x88 || op == 0x89 || op == 0x8A || op == 0x8B) { has_modrm = 1; } /* MOV */
			else if (op == 0x8C || op == 0x8E) { has_modrm = 1; }
			else if (op == 0x8D) { has_modrm = 1; } /* LEA */
			else if (op == 0x8F) { has_modrm = 1; } /* POP rm */
			break;
		case 0x90: /* NOP-ish, XCHG eax,r */
			break;
		case 0x98: /* CWDE/CDQE etc. */
			break;
		case 0xA0: /* MOV AL,moffs */
			if ((op & 0x07) <= 0x03) imm_size = addr_size; /* moffs */
			else if (op == 0xA8) imm_size = 1;
			else if (op == 0xA9) imm_size = op_size;
			break;
		case 0xB0: /* MOV r8, imm8 */
			imm_size = 1;
			break;
		case 0xB8: /* MOV r32/r64, imm32/imm64 */
			imm_size = op_size; /* with REX.W → 8 */
			break;
		case 0xC0:
			if (op == 0xC0 || op == 0xC1) { has_modrm = 1; imm_size = 1; }
			else if (op == 0xC2) imm_size = 2; /* RET imm16 */
			else if (op == 0xC3) {}            /* RET */
			else if (op == 0xC6) { has_modrm = 1; imm_size = 1; }
			else if (op == 0xC7) { has_modrm = 1; imm_size = op_size == 8 ? 4 : op_size; }
			break;
		case 0xC8:
			if (op == 0xCB || op == 0xCC || op == 0xCE || op == 0xCF) {}
			else if (op == 0xC8) imm_size = 3; /* ENTER imm16,imm8 */
			else if (op == 0xC9) {}            /* LEAVE */
			else if (op == 0xCA) imm_size = 2;
			else if (op == 0xCD) imm_size = 1;
			break;
		case 0xD0:
			if (op == 0xD0 || op == 0xD1 || op == 0xD2 || op == 0xD3) has_modrm = 1;
			else return 0; /* AAD/AAM/SALC and FPU prefix already consumed */
			break;
		case 0xE0: /* LOOP/LOOPE/LOOPNE rel8, IN/OUT */
			if (op <= 0xE3) { imm_size = 1; is_jcc_short = 1; }
			else if (op == 0xE4 || op == 0xE6) imm_size = 1;
			else if (op == 0xE5 || op == 0xE7) imm_size = 1;
			else if (op == 0xE8) { imm_size = 4; is_branch_imm32 = 1; } /* CALL rel32 */
			else if (op == 0xE9) { imm_size = 4; is_branch_imm32 = 1; } /* JMP rel32 */
			else if (op == 0xEA) return 0; /* invalid in 64-bit */
			else if (op == 0xEB) { imm_size = 1; is_jcc_short = 1; }    /* JMP rel8 */
			else if (op == 0xEC || op == 0xED || op == 0xEE || op == 0xEF) {}
			break;
		case 0xF0:
			if (op == 0xF6) {
				/* needs ModRM, then imm depends on subop */
				modrm = p[0];
				has_modrm = 1;
				if (((modrm >> 3) & 0x07) <= 1) imm_size = 1;
			} else if (op == 0xF7) {
				modrm = p[0];
				has_modrm = 1;
				if (((modrm >> 3) & 0x07) <= 1) imm_size = op_size == 8 ? 4 : op_size;
			} else if (op == 0xFE) {
				has_modrm = 1; /* INC/DEC rm8 */
			} else if (op == 0xFF) {
				has_modrm = 1; /* JMP/CALL/PUSH rm */
			} else if (op == 0xF4 || op == 0xF5 || op == 0xF8 || op == 0xF9 ||
			           op == 0xFA || op == 0xFB || op == 0xFC || op == 0xFD) {
				/* HLT/CMC/CLC/STC/CLI/STI/CLD/STD — no operand */
			}
			break;
		default:
			return 0;
		}
	} else if (twoByte && !threeByte) {
		/* 0F xx — second-byte opcode */
		if ((op & 0xF0) == 0x80) {
			imm_size = 4;
			is_branch_imm32 = 1; /* Jcc rel32 */
		} else if ((op & 0xF0) == 0x90) {
			has_modrm = 1; /* SETcc */
		} else if (op == 0x05 || op == 0x06 || op == 0x07 || op == 0x08 ||
		           op == 0x09 || op == 0x0B || op == 0x30 || op == 0x31 ||
		           op == 0x32 || op == 0x33 || op == 0x34 || op == 0x35 ||
		           op == 0x77 || op == 0xA0 || op == 0xA1 || op == 0xA2 ||
		           op == 0xA8 || op == 0xA9 || op == 0xAA) {
			/* no operand */
		} else if (op == 0xA3 || op == 0xA4 || op == 0xA5 ||
		           op == 0xAB || op == 0xAC || op == 0xAD || op == 0xAE ||
		           op == 0xAF || op == 0xB0 || op == 0xB1 || op == 0xB2 ||
		           op == 0xB3 || op == 0xB4 || op == 0xB5 || op == 0xB6 ||
		           op == 0xB7 || op == 0xBC || op == 0xBD || op == 0xBE ||
		           op == 0xBF || op == 0xC0 || op == 0xC1) {
			has_modrm = 1;
			if (op == 0xA4 || op == 0xAC) imm_size = 1; /* SHLD/SHRD imm8 */
		} else if ((op & 0xF0) == 0x10 || (op & 0xF0) == 0x20 ||
		           (op & 0xF0) == 0x40 || (op & 0xF0) == 0x50 ||
		           (op & 0xF0) == 0x60 || (op & 0xF0) == 0x70 ||
		           (op & 0xF0) == 0xD0 || (op & 0xF0) == 0xE0 ||
		           (op & 0xF0) == 0xF0) {
			has_modrm = 1; /* SSE/MMX with ModRM */
			if (op == 0x70 || op == 0x71 || op == 0x72 || op == 0x73 ||
			    op == 0xC2 || op == 0xC4 || op == 0xC5 || op == 0xC6) {
				imm_size = 1;
			}
		} else {
			return 0;
		}
	} else {
		/* 0F 38 / 0F 3A — three-byte. All have ModRM. */
		has_modrm = 1;
		if (threeByte && (op == 0x0F /*reserved*/)) return 0;
		/* 0F 3A immediates: many take an imm8 byte */
		/* Conservatively: no immediate unless we know better. Fail safely. */
		(void)threeByte;
	}

	/* ModRM + SIB + displacement. */
	int disp_size = 0;
	if (has_modrm) {
		modrm = *p++;
		unsigned mod = (modrm >> 6) & 0x3;
		unsigned rm = modrm & 0x7;
		unsigned char sib = 0;
		if (mod != 3) {
			if (rm == 4) {
				sib = *p++;
				/* SIB special: base==5 with mod==0 means disp32 only */
				if (mod == 0 && (sib & 0x07) == 5) disp_size = 4;
			}
			if (mod == 0 && rm == 5) {
				/* RIP-relative on 64-bit (was disp32 absolute on 32-bit). */
				rip_relative = 1;
				disp_size = 4;
			} else if (mod == 1) {
				disp_size = 1;
			} else if (mod == 2) {
				disp_size = 4;
			}
		}
		(void)sib;
	}

	/* Now p points past ModRM/SIB. Skip displacement. */
	p += disp_size;
	/* Skip immediate. */
	p += imm_size;

	int total = (int)(p - func);

	/* Copy if requested, with PC-relative fixup. */
	if (out) {
		if (is_branch_imm32) {
			/* Layout: ... opcode (E8/E9 or 0F 8x) followed by 4-byte rel32 IS
			 * located at p-4..p. The imm32 is signed offset from the byte
			 * after itself (i.e. from p) to the absolute target. Recompute
			 * for the copy site. */
			int32_t old_rel = *(int32_t *)(p - 4);
			unsigned char *abs_target = p + old_rel;
			/* Copy everything except the rel32. */
			int prefix_len = total - 4;
			memcpy(out, func, prefix_len);
			out += prefix_len;
			/* New rel32 = abs_target - (out + 4). */
			intptr_t new_rel64 = (intptr_t)(abs_target - (out + 4));
			if (new_rel64 < INT32_MIN || new_rel64 > INT32_MAX) {
				/* Out of range — can't fix up with rel32. Caller should bail. */
				return 0;
			}
			*(int32_t *)out = (int32_t)new_rel64;
		} else if (rip_relative) {
			/* Layout: ...REX op modrm [sib] disp32 [imm].
			 * The disp32 sits between (p - imm_size - 4) and (p - imm_size).
			 * Recompute so RIP-relative load reads the same absolute byte. */
			int prefix_len = total - imm_size - 4;
			memcpy(out, func, prefix_len);
			int32_t old_disp = *(int32_t *)(func + prefix_len);
			unsigned char *abs_target = func + prefix_len + 4 + old_disp + imm_size;
			intptr_t new_disp64 = (intptr_t)(abs_target - (out + prefix_len + 4 + imm_size));
			if (new_disp64 < INT32_MIN || new_disp64 > INT32_MAX) {
				return 0;
			}
			*(int32_t *)(out + prefix_len) = (int32_t)new_disp64;
			/* Copy the imm tail unchanged. */
			if (imm_size > 0) {
				memcpy(out + prefix_len + 4, func + prefix_len + 4, imm_size);
			}
		} else {
			memcpy(out, func, total);
		}
	}
	(void)copy_delta;
	(void)rex;

	return total;
}

int copy_bytes(unsigned char *func, unsigned char *dest, int required_len)
{
	int bytecount = 0;
	while (bytecount < required_len && *func != 0xCC) {
		intptr_t copy_delta = dest ? (intptr_t)(dest - func) : 0;
		int n = decode_one_x64(func, dest, copy_delta);
		if (n <= 0) {
			break; /* unknown / can't fix up */
		}
		func += n;
		if (dest) dest += n;
		bytecount += n;
	}
	return bytecount;
}

#endif /* __x86_64__ */

/* ===========================================================================
 * aarch64 specific
 *
 * Fixed 4-byte instructions. copy_bytes walks 4-byte chunks until ≥ required_len
 * bytes consumed. Detects PC-relative instructions and rewrites:
 *   - B  imm26 (unconditional branch)
 *   - BL imm26 (branch-and-link / call)
 *   - B.cond imm19 (conditional branch)
 *   - CBZ/CBNZ imm19
 *   - TBZ/TBNZ imm14
 *   - ADR imm21 (PC-relative address)
 *   - ADRP imm21 (PC-relative page)
 *   - LDR (literal) imm19
 * If the offset can't fit at the new location, we can't fix it; return what
 * we have so far.
 *
 * The 16-byte gate (LDR x16, [pc+8] ; BR x16 ; .quad target) has no PC-relative
 * dependency on its surroundings (the literal is local), so the gate itself
 * doesn't need fixup.
 * =========================================================================*/

#if defined(__aarch64__) || defined(_M_ARM64)

void check_thunks(unsigned char *dest, unsigned char *pc)
{
	/* No fPIC thunk pattern on aarch64 — GOT/PLT use ADRP+ADD/LDR. */
	(void)dest; (void)pc;
}

void inject_jmp(void *src, void *dest)
{
	uint32_t *t = (uint32_t *)src;
	t[0] = 0x58000050u;                    /* LDR  x16, [pc+8] */
	t[1] = 0xD61F0200u;                    /* BR   x16 */
	*(uint64_t *)(t + 2) = (uint64_t)(uintptr_t)dest;  /* .quad target */
}

/* Sign-extend `value` from `bits` bits to int64_t. */
static int64_t sign_extend(uint32_t value, int bits)
{
	int shift = 32 - bits;
	return ((int32_t)(value << shift)) >> shift;
}

/* Walk one aarch64 instruction at `func`. If `dest` non-NULL, copy with
 * PC-relative fixup. Returns 4 on success, 0 if a PC-relative target is
 * unreachable from the new location. */
static int decode_one_a64(unsigned char *func, unsigned char *dest)
{
	uint32_t insn = *(uint32_t *)func;

	if (!dest) return 4;

	intptr_t delta = dest - func;     /* shift in PC between original and copy */

	/* B / BL: bits 31-26 = 000101 (B) or 100101 (BL); imm26 at bits 25-0. */
	if ((insn & 0x7C000000u) == 0x14000000u) {
		int64_t imm = sign_extend(insn & 0x03FFFFFFu, 26) * 4;
		int64_t new_imm = imm - delta;
		/* Check imm26*4 range: ±128 MB. */
		if (new_imm < -(int64_t)(1 << 27) || new_imm >= (int64_t)(1 << 27)) return 0;
		uint32_t new_field = (uint32_t)((new_imm / 4) & 0x03FFFFFFu);
		uint32_t out = (insn & ~0x03FFFFFFu) | new_field;
		*(uint32_t *)dest = out;
		return 4;
	}

	/* B.cond: bits 31-24 = 0101 0100, imm19 at bits 23-5, cond at 3-0. */
	if ((insn & 0xFF000010u) == 0x54000000u) {
		int64_t imm = sign_extend((insn >> 5) & 0x7FFFFu, 19) * 4;
		int64_t new_imm = imm - delta;
		if (new_imm < -(int64_t)(1 << 20) || new_imm >= (int64_t)(1 << 20)) return 0;
		uint32_t new_field = (uint32_t)((new_imm / 4) & 0x7FFFFu) << 5;
		uint32_t out = (insn & ~(0x7FFFFu << 5)) | new_field;
		*(uint32_t *)dest = out;
		return 4;
	}

	/* CBZ/CBNZ: bits 31, 30 (sf), bits 30-25 = x_011010, bit 24 = 0/1; imm19. */
	if ((insn & 0x7E000000u) == 0x34000000u) {
		int64_t imm = sign_extend((insn >> 5) & 0x7FFFFu, 19) * 4;
		int64_t new_imm = imm - delta;
		if (new_imm < -(int64_t)(1 << 20) || new_imm >= (int64_t)(1 << 20)) return 0;
		uint32_t new_field = (uint32_t)((new_imm / 4) & 0x7FFFFu) << 5;
		uint32_t out = (insn & ~(0x7FFFFu << 5)) | new_field;
		*(uint32_t *)dest = out;
		return 4;
	}

	/* TBZ/TBNZ: bits 31 sf, 30-25 = 011011, bit 24 op; imm14 at bits 18-5. */
	if ((insn & 0x7E000000u) == 0x36000000u) {
		int64_t imm = sign_extend((insn >> 5) & 0x3FFFu, 14) * 4;
		int64_t new_imm = imm - delta;
		if (new_imm < -(int64_t)(1 << 15) || new_imm >= (int64_t)(1 << 15)) return 0;
		uint32_t new_field = (uint32_t)((new_imm / 4) & 0x3FFFu) << 5;
		uint32_t out = (insn & ~(0x3FFFu << 5)) | new_field;
		*(uint32_t *)dest = out;
		return 4;
	}

	/* ADR / ADRP: bits 31 op, 30-29 immlo, 28-24 = 10000, 23-5 immhi, 4-0 Rd.
	 * ADR  encoding: op=0; imm21 in bits {30:29, 23:5}; offset = sign_extend(imm21).
	 * ADRP encoding: op=1; imm21 same layout; offset = sign_extend(imm21) << 12,
	 *                aligned to page (PC[63:12] used). */
	if ((insn & 0x1F000000u) == 0x10000000u) {
		uint32_t op = (insn >> 31) & 1;
		uint32_t immlo = (insn >> 29) & 0x3;
		uint32_t immhi = (insn >> 5) & 0x7FFFFu;
		uint32_t imm21 = (immhi << 2) | immlo;
		int64_t imm = sign_extend(imm21, 21);
		int64_t imm_scaled = op ? (imm << 12) : imm;
		uintptr_t orig_pc = (uintptr_t)func;
		uintptr_t orig_target = op ? ((orig_pc & ~0xFFFu) + (uintptr_t)imm_scaled)
		                           : (orig_pc + (uintptr_t)imm_scaled);
		uintptr_t new_pc = (uintptr_t)dest;
		intptr_t new_off;
		if (op) {
			intptr_t base_diff = (intptr_t)orig_target - (intptr_t)(new_pc & ~(intptr_t)0xFFF);
			if ((base_diff & 0xFFF) != 0) return 0; /* must be page-aligned */
			new_off = base_diff >> 12;
		} else {
			new_off = (intptr_t)orig_target - (intptr_t)new_pc;
		}
		/* imm21 range: ±1 MB (ADR) or ±4 GB (ADRP). */
		if (new_off < -(int64_t)(1 << 20) || new_off >= (int64_t)(1 << 20)) return 0;
		uint32_t new_imm21 = (uint32_t)(new_off & 0x1FFFFFu);
		uint32_t new_immlo = new_imm21 & 0x3;
		uint32_t new_immhi = (new_imm21 >> 2) & 0x7FFFFu;
		uint32_t out = (insn & ~((0x3u << 29) | (0x7FFFFu << 5)));
		out |= new_immlo << 29;
		out |= new_immhi << 5;
		*(uint32_t *)dest = out;
		return 4;
	}

	/* LDR (literal): bits 31-30 = 00 (32) or 01 (64), 29-24 = 011000, imm19, Rt.
	 * Family also includes LDRSW, prefetch. */
	if ((insn & 0x3F000000u) == 0x18000000u) {
		int64_t imm = sign_extend((insn >> 5) & 0x7FFFFu, 19) * 4;
		int64_t new_imm = imm - delta;
		if (new_imm < -(int64_t)(1 << 20) || new_imm >= (int64_t)(1 << 20)) return 0;
		uint32_t new_field = (uint32_t)((new_imm / 4) & 0x7FFFFu) << 5;
		uint32_t out = (insn & ~(0x7FFFFu << 5)) | new_field;
		*(uint32_t *)dest = out;
		return 4;
	}

	/* No PC-relative bits — copy verbatim. */
	*(uint32_t *)dest = insn;
	return 4;
}

int copy_bytes(unsigned char *func, unsigned char *dest, int required_len)
{
	int bytecount = 0;
	while (bytecount < required_len) {
		int n = decode_one_a64(func + bytecount, dest ? dest + bytecount : NULL);
		if (n == 0) break; /* PC-relative out of range — can't continue */
		bytecount += n;
	}
	return bytecount;
}

#endif /* __aarch64__ */
