//===- reorder.rs - ELF function body reordering --------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

/// ELF function reorder: permute function bodies within .text and update
/// the symbol table so addresses match the new layout.
///
/// This operates within the existing .text section bounds -- no new sections
/// are created, so the result stays within the original TLB/address mapping.

use object::{Object, ObjectSection, ObjectSymbol, SymbolKind};
use std::collections::HashMap;

struct FuncInfo {
    /// Size in bytes
    size: u64,
    /// Byte content (copied from the original .text)
    body: Vec<u8>,
}

/// Reorder functions in the given ELF binary data according to the
/// specified name order.  Returns the modified ELF bytes.
///
/// Functions not listed in `order` are placed after the ordered ones,
/// preserving their original relative order.
pub fn reorder_functions(elf_data: &[u8], order: &[&str]) -> Vec<u8> {
    let elf = object::File::parse(elf_data).expect("cannot parse ELF");

    // Find the .text section
    let text_section = elf
        .sections()
        .find(|s| s.name() == Ok(".text"))
        .expect("no .text section found");
    let text_addr = text_section.address();
    let text_offset = text_section.file_range().expect(".text has no file range").0;
    let text_size = text_section.size();
    let text_data = text_section.data().expect("cannot read .text");

    // Collect function symbols within .text, sorted by address
    let mut funcs: Vec<(String, u64, u64)> = Vec::new();
    for sym in elf.symbols() {
        if sym.kind() != SymbolKind::Text || sym.size() == 0 {
            continue;
        }
        let addr = sym.address();
        if addr >= text_addr && addr < text_addr + text_size {
            let name = sym.name().unwrap_or("").to_string();
            funcs.push((name, addr, sym.size()));
        }
    }
    funcs.sort_by_key(|f| f.1);

    // Extract function bodies from original .text
    let mut func_map: HashMap<String, FuncInfo> = HashMap::new();
    for (name, addr, size) in &funcs {
        let offset_in_text = (*addr - text_addr) as usize;
        let end = offset_in_text + *size as usize;
        if end <= text_data.len() {
            let body = text_data[offset_in_text..end].to_vec();
            func_map.insert(
                name.clone(),
                FuncInfo {
                    size: *size,
                    body,
                },
            );
        }
    }

    // Build the new function order: ordered functions first, then remaining
    let mut ordered_names: Vec<String> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
    for name in order {
        let name_s = name.to_string();
        if func_map.contains_key(&name_s) && seen.insert(name_s.clone()) {
            ordered_names.push(name_s);
        }
    }
    // Append unordered functions in their original address order
    for (name, _, _) in &funcs {
        if func_map.contains_key(name) && seen.insert(name.clone()) {
            ordered_names.push(name.clone());
        }
    }

    // Assign new addresses: pack functions sequentially from text_addr,
    // aligned to 4 bytes (Hexagon word alignment).
    let mut new_addrs: HashMap<String, u64> = HashMap::new();
    let mut cursor = text_addr;
    for name in &ordered_names {
        let info = &func_map[name];
        // Align to 4 bytes (Hexagon instruction word size)
        cursor = (cursor + 3) & !3;
        new_addrs.insert(name.clone(), cursor);
        cursor += info.size;
    }

    // Verify we fit within original .text
    assert!(
        cursor <= text_addr + text_size,
        "reordered functions ({:#x}) exceed .text bounds ({:#x})",
        cursor - text_addr,
        text_size
    );

    // Build the output ELF
    let mut output = elf_data.to_vec();

    // Fill .text with zero bytes for unused gaps
    let text_start = text_offset as usize;
    let text_end = text_start + text_size as usize;
    for b in &mut output[text_start..text_end] {
        *b = 0;
    }

    // Write function bodies at their new positions
    for name in &ordered_names {
        let info = &func_map[name];
        let new_addr = new_addrs[name];
        let file_offset = text_offset + (new_addr - text_addr);
        let start = file_offset as usize;
        let end = start + info.body.len();
        output[start..end].copy_from_slice(&info.body);
    }

    // Update symbol table entries with new addresses.
    let patched = patch_symtab(&mut output, elf_data, &new_addrs);
    eprintln!("Patched {} symbol table entries", patched);

    output
}

/// Patch the ELF symbol table in-place to reflect new function addresses.
/// Returns the number of symbols patched.
fn patch_symtab(
    output: &mut [u8],
    original: &[u8],
    new_addrs: &HashMap<String, u64>,
) -> usize {
    let elf = object::File::parse(original).expect("cannot parse ELF");

    // Build a map from original address -> new address using symbol names
    let mut old_to_new: HashMap<u64, u64> = HashMap::new();
    for sym in elf.symbols() {
        if sym.kind() != SymbolKind::Text || sym.size() == 0 {
            continue;
        }
        let name = sym.name().unwrap_or("");
        if let Some(&new_addr) = new_addrs.get(name) {
            if new_addr != sym.address() {
                old_to_new.insert(sym.address(), new_addr);
            }
        }
    }

    if old_to_new.is_empty() {
        return 0;
    }

    // Determine ELF class (32 or 64 bit)
    let is_elf32 = original[4] == 1; // ELFCLASS32
    let is_little_endian = original[5] == 1;

    // Find .symtab section offset and size
    let mut sym_offset = 0u64;
    let mut sym_size = 0u64;
    for section in elf.sections() {
        if section.name() == Ok(".symtab") {
            let range = section.file_range().expect(".symtab has no file range");
            sym_offset = range.0;
            sym_size = range.1;
            break;
        }
    }

    if sym_size == 0 {
        return 0;
    }

    let entry_size = if is_elf32 { 16usize } else { 24usize };
    let num_entries = sym_size as usize / entry_size;
    let mut patched = 0;

    // Patch each symbol entry
    for i in 0..num_entries {
        let offset = sym_offset as usize + i * entry_size;

        if is_elf32 {
            let st_value = read_u32(original, offset + 4, is_little_endian) as u64;
            let st_info = original[offset + 12];
            let st_type = st_info & 0xf;

            // STT_FUNC = 2
            if st_type == 2 {
                if let Some(&new_addr) = old_to_new.get(&st_value) {
                    write_u32(output, offset + 4, new_addr as u32, is_little_endian);
                    patched += 1;
                }
            }
        } else {
            let st_info = original[offset + 4];
            let st_type = st_info & 0xf;
            let st_value = read_u64(original, offset + 8, is_little_endian);

            if st_type == 2 {
                if let Some(&new_addr) = old_to_new.get(&st_value) {
                    write_u64(output, offset + 8, new_addr, is_little_endian);
                    patched += 1;
                }
            }
        }
    }

    patched
}

fn read_u32(data: &[u8], offset: usize, little_endian: bool) -> u32 {
    let bytes = [
        data[offset],
        data[offset + 1],
        data[offset + 2],
        data[offset + 3],
    ];
    if little_endian {
        u32::from_le_bytes(bytes)
    } else {
        u32::from_be_bytes(bytes)
    }
}

fn write_u32(data: &mut [u8], offset: usize, value: u32, little_endian: bool) {
    let bytes = if little_endian {
        value.to_le_bytes()
    } else {
        value.to_be_bytes()
    };
    data[offset..offset + 4].copy_from_slice(&bytes);
}

fn read_u64(data: &[u8], offset: usize, little_endian: bool) -> u64 {
    let mut bytes = [0u8; 8];
    bytes.copy_from_slice(&data[offset..offset + 8]);
    if little_endian {
        u64::from_le_bytes(bytes)
    } else {
        u64::from_be_bytes(bytes)
    }
}

fn write_u64(data: &mut [u8], offset: usize, value: u64, little_endian: bool) {
    let bytes = if little_endian {
        value.to_le_bytes()
    } else {
        value.to_be_bytes()
    };
    data[offset..offset + 8].copy_from_slice(&bytes);
}
