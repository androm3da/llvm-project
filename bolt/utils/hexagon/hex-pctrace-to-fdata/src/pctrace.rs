//===- pctrace.rs - hexagon-sim pctrace_nano parser -----------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

/// Parse hexagon-sim `--pctrace_nano` output.
///
/// Format: `TNUM=0:PCYC=185:PC=0`

pub struct PcTraceEntry {
    pub thread: u32,
    pub cycle: u64,
    pub pc: u64,
}

pub fn parse_pctrace(data: &[u8]) -> Vec<PcTraceEntry> {
    let mut entries = Vec::new();

    for line in data.split(|&b| b == b'\n') {
        if line.is_empty() {
            continue;
        }

        let line_str = match std::str::from_utf8(line) {
            Ok(s) => s.trim(),
            Err(_) => continue,
        };

        // Only process lines starting with TNUM= (skip register dumps,
        // disassembly, and other non-trace output).
        if !line_str.starts_with("TNUM=") {
            continue;
        }

        // Parse TNUM=N:PCYC=N:PC=N
        let mut thread = 0u32;
        let mut cycle = 0u64;
        let mut pc = 0u64;
        let mut valid = true;

        for part in line_str.split(':') {
            if let Some(val) = part.strip_prefix("TNUM=") {
                thread = match val.parse() {
                    Ok(v) => v,
                    Err(_) => {
                        valid = false;
                        break;
                    }
                };
            } else if let Some(val) = part.strip_prefix("PCYC=") {
                cycle = match val.parse() {
                    Ok(v) => v,
                    Err(_) => {
                        valid = false;
                        break;
                    }
                };
            } else if let Some(val) = part.strip_prefix("PC=") {
                // PC value may be followed by a tab and additional text
                let val = val.split('\t').next().unwrap_or(val).trim();
                // PC values are hex (with or without 0x prefix)
                let hex_str = val.strip_prefix("0x").unwrap_or(val);
                pc = match u64::from_str_radix(hex_str, 16) {
                    Ok(v) => v,
                    Err(_) => {
                        valid = false;
                        break;
                    }
                };
            }
        }

        if valid {
            entries.push(PcTraceEntry { thread, cycle, pc });
        }
    }

    entries
}
