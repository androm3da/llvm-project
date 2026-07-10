//===- symbols.rs - ELF symbol table reader ---------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

/// ELF symbol table reader using the `object` crate.

use object::{Object, ObjectSymbol, SymbolKind};
use std::collections::BTreeMap;

pub struct SymbolInfo {
    pub name: String,
    pub addr: u64,
    pub size: u64,
}

/// Read function symbols from an ELF file, sorted by address.
pub fn read_symbols(data: &[u8]) -> Vec<SymbolInfo> {
    let file = object::File::parse(data).expect("failed to parse ELF");
    let mut syms: Vec<SymbolInfo> = file
        .symbols()
        .filter(|s| s.kind() == SymbolKind::Text)
        .map(|s| SymbolInfo {
            name: s.name().unwrap_or("??").to_string(),
            addr: s.address(),
            size: s.size(),
        })
        .collect();

    syms.sort_by_key(|s| s.addr);
    syms
}

/// Map of address ranges to symbol names.
pub struct SymbolMap {
    /// BTreeMap from start_addr -> (name, size)
    map: BTreeMap<u64, (String, u64)>,
}

impl SymbolMap {
    pub fn new(symbols: &[SymbolInfo]) -> Self {
        let mut map = BTreeMap::new();
        for sym in symbols {
            map.insert(sym.addr, (sym.name.clone(), sym.size));
        }
        SymbolMap { map }
    }

    /// Look up the function containing `addr`, returning (name, offset_within_func).
    pub fn lookup(&self, addr: u64) -> Option<(&str, u64)> {
        // Find the greatest symbol address <= addr
        let (&sym_addr, (name, size)) = self.map.range(..=addr).next_back()?;
        let offset = addr - sym_addr;
        // Check if addr is within the symbol's bounds (or within reasonable range
        // if size is 0).
        if *size > 0 && offset >= *size {
            return None;
        }
        Some((name, offset))
    }
}
