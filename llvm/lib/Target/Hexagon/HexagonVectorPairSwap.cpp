//===-- HexagonVectorPairSwap.cpp - Eliminate HVX pair swaps --------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// After register allocation, the compiler sometimes generates V6_vcombine
// instructions solely to swap a pair's halves within the same W register pair:
//
//   $wN = V6_vcombine $vLo, $vHi
//
// where $vLo = getSubReg($wN, vsub_lo) and $vHi = getSubReg($wN, vsub_hi).
//
// These can be eliminated by using the WR (reversed) encoding instead of W,
// saving one execution slot and one cycle of latency per eliminated swap.
//
//===----------------------------------------------------------------------===//

#include "Hexagon.h"
#include "HexagonSubtarget.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/Passes.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/Pass.h"
#include "llvm/Support/CommandLine.h"

using namespace llvm;

#define DEBUG_TYPE "hexagon-wr-pair-swap"

static cl::opt<bool>
    DisableHexagonWRPairSwap("disable-hexagon-wr-pair-swap", cl::Hidden,
                             cl::desc("Disable HVX WR pair swap optimization"));

STATISTIC(NumSwapsEliminated, "Number of HVX pair swaps eliminated");

namespace {

class HexagonVectorPairSwap : public MachineFunctionPass {
public:
  static char ID;
  HexagonVectorPairSwap() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "Hexagon HVX Vector Pair Swap";
  }

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    MachineFunctionPass::getAnalysisUsage(AU);
  }

private:
  const HexagonSubtarget *HST = nullptr;
  const TargetRegisterInfo *TRI = nullptr;

  bool isWReg(MCRegister Reg) const {
    return Reg >= Hexagon::W0 && Reg <= Hexagon::W15;
  }

  MCRegister getWRForW(MCRegister WReg) const {
    assert(isWReg(WReg));
    return Hexagon::WR0 + (WReg - Hexagon::W0);
  }

  bool processBlock(MachineBasicBlock &MBB);
};

} // end anonymous namespace

char HexagonVectorPairSwap::ID = 0;

INITIALIZE_PASS(HexagonVectorPairSwap, "hexagon-wr-pair-swap",
                "Hexagon HVX Vector Pair Swap", false, false)

bool HexagonVectorPairSwap::processBlock(MachineBasicBlock &MBB) {
  bool Changed = false;

  for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
    if (MI.getOpcode() != Hexagon::V6_vcombine)
      continue;

    // Pattern: $wN = V6_vcombine $vLo, $vHi
    // V6_vcombine puts operand 1 (Vu) into Vdd.hi and operand 2 (Vv) into
    // Vdd.lo. So for this to be a self-swap, operand 1 must be the current
    // lo and operand 2 must be the current hi.
    MachineOperand &Dst = MI.getOperand(0);
    MachineOperand &Src1 = MI.getOperand(1); // goes to hi
    MachineOperand &Src2 = MI.getOperand(2); // goes to lo

    // Skip if any operand is undef.
    if (Src1.isUndef() || Src2.isUndef())
      continue;

    MCRegister DstReg = Dst.getReg().asMCReg();
    MCRegister Src1Reg = Src1.getReg().asMCReg();
    MCRegister Src2Reg = Src2.getReg().asMCReg();

    // Must be a W register.
    if (!isWReg(DstReg))
      continue;

    // Check this is a self-swap: putting lo into hi and hi into lo.
    MCRegister ExpectedLo = TRI->getSubReg(DstReg, Hexagon::vsub_lo);
    MCRegister ExpectedHi = TRI->getSubReg(DstReg, Hexagon::vsub_hi);

    // Src1 goes to hi, so it must be the current lo (swap).
    // Src2 goes to lo, so it must be the current hi (swap).
    if (Src1Reg != ExpectedLo || Src2Reg != ExpectedHi)
      continue;

    // Verify all subsequent uses of $wN (until redefinition) are whole-pair
    // references, not individual V sub-register uses.
    MCRegister WRReg = getWRForW(DstReg);
    bool Safe = true;
    SmallVector<MachineOperand *, 8> PairUses;

    auto It = std::next(MI.getIterator());
    for (auto E = MBB.end(); It != E; ++It) {
      MachineInstr &UseMI = *It;
      bool Redefined = false;

      // Process uses before defs: an instruction like $w0 = op $w0, $w0
      // uses $w0 before redefining it.
      for (MachineOperand &MO : UseMI.operands()) {
        if (!MO.isReg() || MO.isDef())
          continue;
        MCRegister Reg = MO.getReg().asMCReg();
        if (!Reg.isValid())
          continue;
        // Use of individual V sub-registers is not safe.
        if (Reg == ExpectedLo || Reg == ExpectedHi) {
          Safe = false;
          break;
        }
        if (Reg == DstReg)
          PairUses.push_back(&MO);
      }

      if (!Safe)
        break;

      // Now check for redefinition of the pair.
      for (const MachineOperand &MO : UseMI.operands()) {
        if (!MO.isReg() || !MO.isDef())
          continue;
        MCRegister Reg = MO.getReg().asMCReg();
        if (!Reg.isValid())
          continue;
        if (TRI->regsOverlap(Reg, DstReg)) {
          Redefined = true;
          break;
        }
      }

      if (!Safe)
        break;
      if (Redefined)
        break;
    }

    if (!Safe)
      continue;

    // Check liveness: if the pair is live-out from this block, registers
    // overlapping the pair might be used in successors. Be conservative.
    if (It == MBB.end()) {
      // We reached the end of the block without a redefinition.
      // Check if any successor has a live-in that overlaps the pair.
      bool LiveOut = false;
      for (const MachineBasicBlock *Succ : MBB.successors()) {
        for (const auto &LI : Succ->liveins()) {
          if (TRI->regsOverlap(LI.PhysReg, DstReg)) {
            LiveOut = true;
            break;
          }
        }
        if (LiveOut)
          break;
      }
      if (LiveOut)
        continue;
    }

    // All checks passed. Rewrite uses from W to WR and erase the vcombine.
    for (MachineOperand *MO : PairUses)
      MO->setReg(WRReg);

    MI.eraseFromParent();
    ++NumSwapsEliminated;
    Changed = true;
  }

  return Changed;
}

bool HexagonVectorPairSwap::runOnMachineFunction(MachineFunction &MF) {
  if (skipFunction(MF.getFunction()))
    return false;

  if (DisableHexagonWRPairSwap)
    return false;

  HST = &MF.getSubtarget<HexagonSubtarget>();
  if (!HST->hasV67Ops() || !HST->useHVXOps())
    return false;

  TRI = HST->getRegisterInfo();

  bool Changed = false;
  for (MachineBasicBlock &MBB : MF)
    Changed |= processBlock(MBB);

  return Changed;
}

FunctionPass *llvm::createHexagonVectorPairSwap() {
  return new HexagonVectorPairSwap();
}
