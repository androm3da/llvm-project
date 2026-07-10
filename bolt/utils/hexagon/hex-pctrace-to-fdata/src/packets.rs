//===- packets.rs - Hexagon VLIW packet boundary detection ----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

/// Determine Hexagon packet sizes by reading parse bits.
///
/// Hexagon instructions are 32-bit words.  Bits [15:14] encode the
/// parse bits (PP field):
///   00 = duplex (end of packet)
///   01 = not end of packet
///   10 = not end of packet (reserved in some ISA versions)
///   11 = end of packet
///
/// We walk .text and build a map from PC -> next packet start.

use std::collections::HashMap;

/// Build a map from packet-start address to packet size (in bytes).
pub fn build_packet_map(text_addr: u64, text_data: &[u8]) -> HashMap<u64, u32> {
    let mut map = HashMap::new();
    let mut offset = 0usize;
    let mut packet_start = 0usize;

    while offset + 4 <= text_data.len() {
        let word = u32::from_le_bytes([
            text_data[offset],
            text_data[offset + 1],
            text_data[offset + 2],
            text_data[offset + 3],
        ]);

        let parse_bits = (word >> 14) & 0x3;
        offset += 4;

        // PP=00 (duplex), PP=11 (end of packet), PP=10 (also end in practice)
        if parse_bits != 1 {
            let size = (offset - packet_start) as u32;
            let addr = text_addr + packet_start as u64;
            map.insert(addr, size);
            packet_start = offset;
        }
    }

    map
}

/// Given a PC and the packet map, return the next sequential packet address.
pub fn next_packet(pc: u64, packet_map: &HashMap<u64, u32>) -> Option<u64> {
    packet_map.get(&pc).map(|&size| pc + size as u64)
}
