//===- bolt/Passes/HexagonBinaryAnalysis.cpp --------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Binary analysis passes for Hexagon targets:
//   - HexagonTrapScanner: scans for trap/privileged instructions
//   - HexagonStatsScanner: collects function and instruction statistics
//
//===----------------------------------------------------------------------===//

#include "bolt/Passes/HexagonBinaryAnalysis.h"
#include "bolt/Core/BinaryBasicBlock.h"
#include "bolt/Core/BinaryContext.h"
#include "bolt/Core/BinaryFunction.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrDesc.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegister.h"
#include "llvm/Support/raw_ostream.h"

#define DEBUG_TYPE "bolt-hexagon-analysis"

using namespace llvm;
using namespace bolt;

// Hexagon instruction type field from TSFlags. These constants mirror
// HexagonII enums from HexagonDepITypes.h / HexagonBaseInfo.h but are
// duplicated here because bolt/lib/Passes cannot depend on LLVMHexagonDesc.
namespace HexType {
enum : unsigned {
  ALU32_2op = 0,
  ALU32_3op = 1,
  ALU32_ADDI = 2,
  ALU64 = 3,
  CJ = 4,
  CR = 5,
  CVI_4SLOT_MPY = 6,
  CVI_FIRST = 6,
  CVI_ZW = 31,
  CVI_LAST = 31,
  DUPLEX = 32,
  ENDLOOP = 33,
  EXTENDER = 34,
  J = 35,
  LD = 36,
  M = 37,
  MAPPING = 38,
  NCJ = 39,
  PSEUDO = 40,
  ST = 41,
  SUBINSN = 42,
  S_2op = 43,
  S_3op = 44,
  V2LDST = 47,
  V4LDST = 48,
};
} // namespace HexType

// Hexagon TSFlags field positions (mirrors HexagonII in HexagonBaseInfo.h).
namespace HexFlags {
enum : unsigned {
  TypePos = 0,
  TypeMask = 0x7f,
  PredicatedPos = 10,
  PredicatedMask = 0x1,
  NewValuePos = 14,
  NewValueMask = 0x1,
  HasNewValuePos = 15,
  HasNewValueMask = 0x1,
};
} // namespace HexFlags

static unsigned getHexType(const MCInstrInfo &MII, const MCInst &Inst) {
  uint64_t TSFlags = MII.get(Inst.getOpcode()).TSFlags;
  return (TSFlags >> HexFlags::TypePos) & HexFlags::TypeMask;
}

static bool isHexPredicated(const MCInstrInfo &MII, const MCInst &Inst) {
  uint64_t TSFlags = MII.get(Inst.getOpcode()).TSFlags;
  return (TSFlags >> HexFlags::PredicatedPos) & HexFlags::PredicatedMask;
}

static bool isHexNewValue(const MCInstrInfo &MII, const MCInst &Inst) {
  uint64_t TSFlags = MII.get(Inst.getOpcode()).TSFlags;
  return ((TSFlags >> HexFlags::NewValuePos) & HexFlags::NewValueMask) ||
         ((TSFlags >> HexFlags::HasNewValuePos) & HexFlags::HasNewValueMask);
}

static bool isHexCVI(unsigned Type) {
  return Type >= HexType::CVI_FIRST && Type <= HexType::CVI_LAST;
}

/// Check whether an indirect call is KCFI-protected by scanning predecessor
/// blocks for the characteristic load-and-compare pattern:
///
///   R6 = memw(Rtarget + #-4)    ; L2_loadri_io with negative offset
///
/// where Rtarget is the register used in the indirect call (callr Rtarget).
static bool isKCFIProtectedCall(BinaryContext &BC, const BinaryBasicBlock &BB,
                                const MCInst &CallInst) {
  // Operand 0 of the indirect call is the target register.
  if (CallInst.getNumOperands() == 0 || !CallInst.getOperand(0).isReg())
    return false;
  MCRegister CallTargetReg = CallInst.getOperand(0).getReg();

  for (const BinaryBasicBlock *Pred : BB.predecessors()) {
    for (const MCInst &Inst : *Pred) {
      StringRef Name = BC.MII->getName(Inst.getOpcode());
      if (Name != "L2_loadri_io")
        continue;
      // L2_loadri_io: Rd = memw(Rs + #s11_2)
      //   operand 0: Rd (def)
      //   operand 1: Rs (base register)
      //   operand 2: immediate offset
      if (Inst.getNumOperands() < 3)
        continue;
      if (!Inst.getOperand(1).isReg() || !Inst.getOperand(2).isImm())
        continue;
      if (Inst.getOperand(1).getReg() == CallTargetReg &&
          Inst.getOperand(2).getImm() < 0)
        return true;
    }
  }
  return false;
}

//===----------------------------------------------------------------------===//
// HexagonTrapScanner
//===----------------------------------------------------------------------===//

namespace llvm {
namespace bolt {
namespace HexagonTrapScanner {

Error Analysis::runOnFunctions(BinaryContext &BC) {
  if (!BC.isHexagon())
    return Error::success();

  unsigned TotalFindings = 0;

  for (auto &BFI : BC.getBinaryFunctions()) {
    BinaryFunction &BF = BFI.second;
    if (!BF.hasCFG())
      continue;

    for (const BinaryBasicBlock &BB : BF) {
      for (const MCInst &Inst : BB) {
        StringRef Name = BC.MII->getName(Inst.getOpcode());

        // Classify the instruction.
        StringRef Category;
        StringRef Detail;

        if (Name == "J2_trap0") {
          int64_t Imm = 0;
          if (Inst.getNumOperands() > 0 && Inst.getOperand(0).isImm())
            Imm = Inst.getOperand(0).getImm();

          Category = "trap0";
          if (Imm == 0)
            Detail = "supervisor call (trap0(#0))";
          else if (Imm == 0xDB)
            Detail = "debug breakpoint (trap0(#0xDB))";
          else if (Imm == 0xFB)
            Detail = "compiler barrier (trap0(#0xFB))";
          else {
            Detail = "unknown trap0 immediate";
          }
        } else if (Name == "J2_trap1") {
          Category = "trap1";
          Detail = "monitor-level trap";
        } else if (Name == "Y2_dcfetch" || Name == "Y2_dcfetchbo") {
          Category = "cache";
          Detail = "data cache fetch";
        } else if (Name == "Y2_barrier") {
          Category = "barrier";
          Detail = "memory barrier";
        } else {
          continue; // Not an instruction of interest.
        }

        ++TotalFindings;
        BC.outs() << "  " << BF.getOneName() << " : ";
        BC.printInstruction(BC.outs(), Inst, 0, &BF);
        BC.outs() << "    category=" << Category << "  " << Detail << "\n";
      }
    }
  }

  BC.outs() << "BOLT-INFO: hexagon-trap scanner found " << TotalFindings
            << " notable instruction(s)\n";
  return Error::success();
}

} // namespace HexagonTrapScanner

//===----------------------------------------------------------------------===//
// HexagonStatsScanner
//===----------------------------------------------------------------------===//

namespace HexagonStatsScanner {

Error Analysis::runOnFunctions(BinaryContext &BC) {
  if (!BC.isHexagon())
    return Error::success();

  unsigned FuncCount = 0;
  unsigned FuncWithCFG = 0;
  unsigned FuncWithoutCFG = 0;
  uint64_t TotalInsns = 0;

  // Type breakdown counters.
  uint64_t ALU32Count = 0;
  uint64_t ALU64Count = 0;
  uint64_t LoadCount = 0;
  uint64_t StoreCount = 0;
  uint64_t JumpCount = 0;
  uint64_t MulCount = 0;
  uint64_t CVICount = 0;
  uint64_t SystemCount = 0;
  uint64_t ExtenderCount = 0;
  uint64_t OtherCount = 0;

  uint64_t PredicatedCount = 0;
  uint64_t NewValueCount = 0;
  uint64_t IndirectCallCount = 0;
  uint64_t IndirectCallKCFICount = 0;
  uint64_t IndirectBranchCount = 0;

  for (auto &BFI : BC.getBinaryFunctions()) {
    BinaryFunction &BF = BFI.second;
    ++FuncCount;

    if (!BF.hasCFG()) {
      ++FuncWithoutCFG;
      continue;
    }
    ++FuncWithCFG;

    for (const BinaryBasicBlock &BB : BF) {
      for (const MCInst &Inst : BB) {
        ++TotalInsns;

        unsigned Type = getHexType(*BC.MII, Inst);
        switch (Type) {
        case HexType::ALU32_2op:
        case HexType::ALU32_3op:
        case HexType::ALU32_ADDI:
          ++ALU32Count;
          break;
        case HexType::ALU64:
        case HexType::S_2op:
        case HexType::S_3op:
          ++ALU64Count;
          break;
        case HexType::LD:
        case HexType::V2LDST:
        case HexType::V4LDST:
          ++LoadCount;
          break;
        case HexType::ST:
          ++StoreCount;
          break;
        case HexType::J:
        case HexType::CJ:
        case HexType::NCJ:
          ++JumpCount;
          break;
        case HexType::M:
          ++MulCount;
          break;
        case HexType::CR:
          ++SystemCount;
          break;
        case HexType::EXTENDER:
          ++ExtenderCount;
          break;
        default:
          if (isHexCVI(Type))
            ++CVICount;
          else
            ++OtherCount;
          break;
        }

        if (isHexPredicated(*BC.MII, Inst))
          ++PredicatedCount;

        if (isHexNewValue(*BC.MII, Inst))
          ++NewValueCount;

        if (BC.MIB->isIndirectCall(Inst)) {
          ++IndirectCallCount;
          if (isKCFIProtectedCall(BC, BB, Inst))
            ++IndirectCallKCFICount;
        } else if (BC.MIB->isIndirectBranch(Inst)) {
          ++IndirectBranchCount;
        }
      }
    }
  }

  // Print summary.
  BC.outs() << "\nBOLT-INFO: Hexagon Binary Statistics\n";
  BC.outs() << "=====================================\n";
  BC.outs() << "  Functions total:        " << FuncCount << "\n";
  BC.outs() << "    with CFG:             " << FuncWithCFG << "\n";
  BC.outs() << "    without CFG:          " << FuncWithoutCFG << "\n";
  BC.outs() << "  Total instructions:     " << TotalInsns << "\n";
  BC.outs() << "\n  Instruction Type Breakdown:\n";
  BC.outs() << "    ALU32:                " << ALU32Count << "\n";
  BC.outs() << "    ALU64/S-type:         " << ALU64Count << "\n";
  BC.outs() << "    Load:                 " << LoadCount << "\n";
  BC.outs() << "    Store:                " << StoreCount << "\n";
  BC.outs() << "    Jump/Branch:          " << JumpCount << "\n";
  BC.outs() << "    Multiply:             " << MulCount << "\n";
  BC.outs() << "    CVI/HVX:              " << CVICount << "\n";
  BC.outs() << "    System (CR):          " << SystemCount << "\n";
  BC.outs() << "    Constant extender:    " << ExtenderCount << "\n";
  BC.outs() << "    Other:                " << OtherCount << "\n";

  BC.outs() << "\n  Instruction Properties:\n";
  BC.outs() << "    Predicated:           " << PredicatedCount << "\n";
  BC.outs() << "    New-value:            " << NewValueCount << "\n";
  BC.outs() << "    Indirect call:        " << IndirectCallCount << "\n";
  BC.outs() << "      KCFI-protected:     " << IndirectCallKCFICount << "\n";
  BC.outs() << "      Unprotected:        "
            << (IndirectCallCount - IndirectCallKCFICount) << "\n";
  BC.outs() << "    Indirect branch:      " << IndirectBranchCount << "\n";

  if (TotalInsns > 0) {
    double HVXDensity = 100.0 * CVICount / TotalInsns;
    BC.outs() << "\n  HVX density:            ";
    BC.outs() << format("%.1f%%", HVXDensity) << "\n";
  }

  BC.outs() << "\n";
  return Error::success();
}

} // namespace HexagonStatsScanner
} // namespace bolt
} // namespace llvm
