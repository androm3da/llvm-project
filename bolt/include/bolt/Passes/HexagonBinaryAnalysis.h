//===- bolt/Passes/HexagonBinaryAnalysis.h ----------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Binary analysis passes for Hexagon targets:
//   - HexagonTrapScanner: scans for privileged/trap instructions
//   - HexagonStatsScanner: collects function and instruction statistics
//
//===----------------------------------------------------------------------===//

#ifndef BOLT_PASSES_HEXAGONBINARYANALYSIS_H
#define BOLT_PASSES_HEXAGONBINARYANALYSIS_H

#include "bolt/Passes/BinaryPasses.h"

namespace llvm {
namespace bolt {

namespace HexagonTrapScanner {

class Analysis : public BinaryFunctionPass {
public:
  Analysis() : BinaryFunctionPass(false) {}

  const char *getName() const override { return "hexagon-trap-scanner"; }

  Error runOnFunctions(BinaryContext &BC) override;
};

} // namespace HexagonTrapScanner

namespace HexagonStatsScanner {

class Analysis : public BinaryFunctionPass {
public:
  Analysis() : BinaryFunctionPass(false) {}

  const char *getName() const override { return "hexagon-stats-scanner"; }

  Error runOnFunctions(BinaryContext &BC) override;
};

} // namespace HexagonStatsScanner

} // namespace bolt
} // namespace llvm

#endif
