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
// Per-hook ABI descriptors paired 1:1 with the Hook_<TAG> callbacks
// declared in hook_callbacks.h. Every entry encodes the named param
// types so the AsmJit-based trampoline emitter can build correct
// FuncSignatures for incoming and outgoing calls.

#include "HookSignature.h"

namespace HS = HamSig;

#define I HS::ParamKind::Int32
#define F HS::ParamKind::Float
#define P HS::ParamKind::Pointer
#define V HS::ParamKind::Vector

#define RV HS::ReturnKind::Void
#define RI HS::ReturnKind::Int32
#define RF HS::ReturnKind::Float
#define RP HS::ReturnKind::Pointer
#define RVS HS::ReturnKind::VectorSret

const HS::HookSignature Sig_Bool_Bool                                          = { RI,  1, { I } };
const HS::HookSignature Sig_Bool_Bool_Int                                      = { RI,  2, { I, I } };
const HS::HookSignature Sig_Bool_Cbase                                         = { RI,  1, { P } };
const HS::HookSignature Sig_Bool_Cbase_Bool                                    = { RI,  2, { P, I } };
const HS::HookSignature Sig_Bool_Cbase_Int                                     = { RI,  2, { P, I } };
const HS::HookSignature Sig_Bool_Entvar                                        = { RI,  1, { P } };
const HS::HookSignature Sig_Bool_Entvar_Float                                  = { RI,  2, { P, F } };
const HS::HookSignature Sig_Bool_Float_Int_Int                                 = { RI,  3, { F, I, I } };
const HS::HookSignature Sig_Bool_Int                                           = { RI,  1, { I } };
const HS::HookSignature Sig_Bool_ItemInfo                                      = { RI,  1, { P } };
const HS::HookSignature Sig_Bool_Void                                          = { RI,  0, {} };
const HS::HookSignature Sig_Bool_pVector                                       = { RI,  1, { P } };
const HS::HookSignature Sig_Bool_pVector_pVector                               = { RI,  2, { P, P } };
const HS::HookSignature Sig_Cbase_Void                                         = { RP,  0, {} };
const HS::HookSignature Sig_Float_Float                                        = { RF,  1, { F } };
const HS::HookSignature Sig_Float_Float_Cbase                                  = { RF,  2, { F, P } };
const HS::HookSignature Sig_Float_Int                                          = { RF,  1, { I } };
const HS::HookSignature Sig_Float_Int_Float                                    = { RF,  2, { I, F } };
const HS::HookSignature Sig_Float_Void                                         = { RF,  0, {} };
const HS::HookSignature Sig_Int_Cbase                                          = { RI,  1, { P } };
const HS::HookSignature Sig_Int_Cbase_Bool                                     = { RI,  2, { P, I } };
const HS::HookSignature Sig_Int_Cbase_pVector                                  = { RI,  2, { P, P } };
const HS::HookSignature Sig_Int_Entvar                                         = { RI,  1, { P } };
const HS::HookSignature Sig_Int_Entvar_Entvar_Float_Float_Int                  = { RI,  5, { P, P, F, F, I } };
const HS::HookSignature Sig_Int_Entvar_Entvar_Float_Int                        = { RI,  4, { P, P, F, I } };
const HS::HookSignature Sig_Int_Entvar_Float                                   = { RI,  2, { P, F } };
const HS::HookSignature Sig_Int_Float                                          = { RI,  1, { F } };
const HS::HookSignature Sig_Int_Float_Float                                    = { RI,  2, { F, F } };
const HS::HookSignature Sig_Int_Float_Int                                      = { RI,  2, { F, I } };
const HS::HookSignature Sig_Int_Float_Int_Int                                  = { RI,  3, { F, I, I } };
const HS::HookSignature Sig_Int_Int                                            = { RI,  1, { I } };
const HS::HookSignature Sig_Int_Int_Int                                        = { RI,  2, { I, I } };
const HS::HookSignature Sig_Int_Int_Int_Float_Int                              = { RI,  4, { I, I, F, I } };
const HS::HookSignature Sig_Int_Int_Str_Int                                    = { RI,  3, { I, P, I } };
const HS::HookSignature Sig_Int_Int_Str_Int_Bool                               = { RI,  4, { I, P, I, I } };
const HS::HookSignature Sig_Int_Int_Str_Int_Int                                = { RI,  4, { I, P, I, I } };
const HS::HookSignature Sig_Int_ItemInfo                                       = { RI,  1, { P } };
const HS::HookSignature Sig_Int_Short                                          = { RI,  1, { I } };
const HS::HookSignature Sig_Int_Str                                            = { RI,  1, { P } };
const HS::HookSignature Sig_Int_Str_Str                                        = { RI,  2, { P, P } };
const HS::HookSignature Sig_Int_Str_Str_Int_Str_Int_Int                        = { RI,  6, { P, P, I, P, I, I } };
const HS::HookSignature Sig_Int_Str_Vector_Str                                 = { RI,  3, { P, V, P } };
const HS::HookSignature Sig_Int_Vector                                         = { RI,  1, { V } };
const HS::HookSignature Sig_Int_Vector_Cbase                                   = { RI,  2, { V, P } };
const HS::HookSignature Sig_Int_Vector_Vector                                  = { RI,  2, { V, V } };
const HS::HookSignature Sig_Int_Vector_Vector_Float_Float                      = { RI,  4, { V, V, F, F } };
const HS::HookSignature Sig_Int_Void                                           = { RI,  0, {} };
const HS::HookSignature Sig_Int_pVector                                        = { RI,  1, { P } };
const HS::HookSignature Sig_Int_pVector_pVector                                = { RI,  2, { P, P } };
const HS::HookSignature Sig_Int_pVector_pVector_Cbase_pFloat                   = { RI,  4, { P, P, P, P } };
const HS::HookSignature Sig_Int_pVector_pVector_Float_Cbase_pVector            = { RI,  5, { P, P, F, P, P } };
const HS::HookSignature Sig_Int_pVector_pVector_Float_Cbase_pVector_pVector_Bool = { RI, 7, { P, P, F, P, P, P, I } };
const HS::HookSignature Sig_Str_Str                                            = { RP,  1, { P } };
const HS::HookSignature Sig_Str_Void                                           = { RP,  0, {} };
const HS::HookSignature Sig_Vector_Float                                       = { RVS, 1, { F } };
const HS::HookSignature Sig_Vector_Float_Cbase_Int                             = { RVS, 3, { F, P, I } };
const HS::HookSignature Sig_Vector_Vector_Vector_Vector                        = { RVS, 3, { V, V, V } };
const HS::HookSignature Sig_Vector_Void                                        = { RVS, 0, {} };
const HS::HookSignature Sig_Vector_pVector                                     = { RVS, 1, { P } };
const HS::HookSignature Sig_Void_Bool                                          = { RV,  1, { I } };
const HS::HookSignature Sig_Void_Bool_Bool                                     = { RV,  2, { I, I } };
const HS::HookSignature Sig_Void_Cbase                                         = { RV,  1, { P } };
const HS::HookSignature Sig_Void_Cbase_Bool                                    = { RV,  2, { P, I } };
const HS::HookSignature Sig_Void_Cbase_Cbase_Int_Float                         = { RV,  4, { P, P, I, F } };
const HS::HookSignature Sig_Void_Cbase_Float                                   = { RV,  2, { P, F } };
const HS::HookSignature Sig_Void_Cbase_Int                                     = { RV,  2, { P, I } };
const HS::HookSignature Sig_Void_Cbase_Int_Float                               = { RV,  3, { P, I, F } };
const HS::HookSignature Sig_Void_Cbase_pVector_Float                           = { RV,  3, { P, P, F } };
const HS::HookSignature Sig_Void_Edict                                         = { RV,  1, { P } };
const HS::HookSignature Sig_Void_Entvar                                        = { RV,  1, { P } };
const HS::HookSignature Sig_Void_Entvar_Entvar_Float                           = { RV,  3, { P, P, F } };
const HS::HookSignature Sig_Void_Entvar_Entvar_Float_Int_Int                   = { RV,  5, { P, P, F, I, I } };
const HS::HookSignature Sig_Void_Entvar_Entvar_Int                             = { RV,  3, { P, P, I } };
const HS::HookSignature Sig_Void_Entvar_Float                                  = { RV,  2, { P, F } };
const HS::HookSignature Sig_Void_Entvar_Float_Float                            = { RV,  3, { P, F, F } };
const HS::HookSignature Sig_Void_Entvar_Float_Vector_Trace_Int                 = { RV,  5, { P, F, V, P, I } };
const HS::HookSignature Sig_Void_Entvar_Int                                    = { RV,  2, { P, I } };
const HS::HookSignature Sig_Void_Float                                         = { RV,  1, { F } };
const HS::HookSignature Sig_Void_Float_Cbase                                   = { RV,  2, { F, P } };
const HS::HookSignature Sig_Void_Float_Float                                   = { RV,  2, { F, F } };
const HS::HookSignature Sig_Void_Float_Float_Float_Int                         = { RV,  4, { F, F, F, I } };
const HS::HookSignature Sig_Void_Float_Int                                     = { RV,  2, { F, I } };
const HS::HookSignature Sig_Void_Float_Vector_Trace_Int                        = { RV,  4, { F, V, P, I } };
const HS::HookSignature Sig_Void_Int                                           = { RV,  1, { I } };
const HS::HookSignature Sig_Void_Int_Bool                                      = { RV,  2, { I, I } };
const HS::HookSignature Sig_Void_Int_Int                                       = { RV,  2, { I, I } };
const HS::HookSignature Sig_Void_Int_Int_Int                                   = { RV,  3, { I, I, I } };
const HS::HookSignature Sig_Void_Int_Str_Bool                                  = { RV,  3, { I, P, I } };
const HS::HookSignature Sig_Void_Short                                         = { RV,  1, { I } };
const HS::HookSignature Sig_Void_Str                                           = { RV,  1, { P } };
const HS::HookSignature Sig_Void_Str_Bool                                      = { RV,  2, { P, I } };
const HS::HookSignature Sig_Void_Str_Float_Float_Float                         = { RV,  4, { P, F, F, F } };
const HS::HookSignature Sig_Void_Str_Float_Float_Float_Bool_Cbase              = { RV,  6, { P, F, F, F, I, P } };
const HS::HookSignature Sig_Void_Str_Float_Float_Float_Int_Cbase               = { RV,  6, { P, F, F, F, I, P } };
const HS::HookSignature Sig_Void_Str_Int                                       = { RV,  2, { P, I } };
const HS::HookSignature Sig_Void_Str_Str_Int                                   = { RV,  3, { P, P, I } };
const HS::HookSignature Sig_Void_Vector                                        = { RV,  1, { V } };
const HS::HookSignature Sig_Void_Vector_Entvar_Entvar_Float_Int_Int            = { RV,  6, { V, P, P, F, I, I } };
const HS::HookSignature Sig_Void_Vector_Vector                                 = { RV,  2, { V, V } };
const HS::HookSignature Sig_Void_Void                                          = { RV,  0, {} };
const HS::HookSignature Sig_Void_pFloat_pFloat                                 = { RV,  2, { P, P } };

// Hook_Deprecated is a no-op dispatcher (Hook* hook only) used as the target
// for hooks that exist in the registry but are absent in some mods (e.g.
// ts_respawnwait). The trampoline reuses Sig_Void_Void's shape — extra
// register/stack args from the engine call are tolerated since the
// dispatcher reads only the prepended Hook* and discards the rest, and
// every supported ABI here is caller-cleanup for the relevant args.
const HS::HookSignature Sig_Deprecated                                         = { RV,  0, {} };

#undef I
#undef F
#undef P
#undef V
#undef RV
#undef RI
#undef RF
#undef RP
#undef RVS
