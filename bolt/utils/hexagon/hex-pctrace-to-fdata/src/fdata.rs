//===- fdata.rs - BOLT fdata format writer --------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

/// BOLT fdata format writer.
///
/// Format:
///   1 <src_func> <src_offset> 1 <dst_func> <dst_offset> <mispred> <count>

use crate::symbols::SymbolMap;
use std::collections::HashMap;
use std::io::Write;

/// A branch edge: (src_addr, dst_addr) -> count
pub type BranchProfile = HashMap<(u64, u64), u64>;

pub fn write_fdata<W: Write>(
    w: &mut W,
    profile: &BranchProfile,
    symbols: &SymbolMap,
) -> std::io::Result<()> {
    let mut entries: Vec<_> = profile.iter().collect();
    entries.sort_by_key(|&(&(src, dst), _)| (src, dst));

    for (&(src, dst), &count) in &entries {
        let (src_func, src_off) = match symbols.lookup(src) {
            Some(v) => v,
            None => continue,
        };
        let (dst_func, dst_off) = match symbols.lookup(dst) {
            Some(v) => v,
            None => continue,
        };

        // BOLT fdata format:
        // 1 src_func src_offset 1 dst_func dst_offset mispred count
        writeln!(
            w,
            "1 {} {:x} 1 {} {:x} 0 {}",
            src_func, src_off, dst_func, dst_off, count
        )?;
    }

    Ok(())
}
