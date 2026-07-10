//===- main.rs - Hexagon pctrace to BOLT fdata conversion tool -----------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

mod callgraph;
mod cluster;
mod fdata;
mod packets;
mod pctrace;
mod reorder;
mod symbols;

use clap::{Parser, Subcommand};
use memmap2::Mmap;
use std::collections::HashMap;
use std::fs::File;
use std::io::BufWriter;

#[derive(Parser)]
#[command(name = "hex-pctrace-to-fdata")]
#[command(about = "Hexagon profiling and function reordering tools")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Convert hexagon-sim pctrace_nano output to BOLT fdata format
    Fdata {
        /// Path to the ELF binary
        #[arg(long)]
        binary: String,

        /// Path to the pctrace_nano trace file
        #[arg(long)]
        trace: String,

        /// Output fdata file
        #[arg(short, long, default_value = "-")]
        output: String,
    },

    /// Compute function order from fdata profile using call graph clustering
    Order {
        /// Path to the BOLT fdata profile
        #[arg(long)]
        fdata: String,

        /// Output ordering file (one function name per line)
        #[arg(short, long, default_value = "-")]
        output: String,
    },

    /// Reorder functions in an ELF binary according to an ordering file.
    /// WARNING: only updates symbol table, not PC-relative call instructions.
    /// Use source-level reordering or link-time ordering for working binaries.
    Reorder {
        /// Path to the input ELF binary
        #[arg(long)]
        binary: String,

        /// Path to the function ordering file (one name per line)
        #[arg(long)]
        order: String,

        /// Path to the output ELF binary
        #[arg(short, long)]
        output: String,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Fdata {
            binary,
            trace,
            output,
        } => cmd_fdata(&binary, &trace, &output),
        Commands::Order { fdata, output } => cmd_order(&fdata, &output),
        Commands::Reorder {
            binary,
            order,
            output,
        } => cmd_reorder(&binary, &order, &output),
    }
}

fn cmd_fdata(binary: &str, trace: &str, output: &str) {
    // Memory-map the binary
    let bin_file = File::open(binary).expect("cannot open binary");
    let bin_mmap = unsafe { Mmap::map(&bin_file).expect("cannot mmap binary") };

    // Read symbols
    let syms = symbols::read_symbols(&bin_mmap);
    let sym_map = symbols::SymbolMap::new(&syms);
    eprintln!("Loaded {} function symbols from {}", syms.len(), binary);

    // Find executable sections for packet map
    let elf = object::File::parse(&*bin_mmap).expect("cannot parse ELF");
    use object::{Object, ObjectSection};
    let mut packet_map = HashMap::new();
    for section in elf.sections() {
        let name = section.name().unwrap_or("");
        if name == ".text" || name == ".start" {
            let addr = section.address();
            let data = section.data().expect("cannot read section data");
            let section_packets = packets::build_packet_map(addr, data);
            eprintln!(
                "Built packet map for {} ({} packets, {:#x}-{:#x})",
                name,
                section_packets.len(),
                addr,
                addr + data.len() as u64
            );
            packet_map.extend(section_packets);
        }
    }

    // Memory-map the trace
    let trace_file = File::open(trace).expect("cannot open trace");
    let trace_mmap = unsafe { Mmap::map(&trace_file).expect("cannot mmap trace") };

    // Parse trace
    let entries = pctrace::parse_pctrace(&trace_mmap);
    eprintln!("Parsed {} trace entries from {}", entries.len(), trace);

    // Build branch profile by deduplicating stall cycles first.
    let mut profile: fdata::BranchProfile = HashMap::new();
    let mut prev_pc: Option<u64> = None;
    let mut prev_thread: u32 = 0;

    for entry in &entries {
        if let Some(ppc) = prev_pc {
            if ppc == entry.pc && prev_thread == entry.thread {
                continue;
            }
        }

        if let Some(ppc) = prev_pc {
            if prev_thread == entry.thread {
                let is_sequential = match packets::next_packet(ppc, &packet_map) {
                    Some(next_seq) => next_seq == entry.pc,
                    None => false,
                };

                let same_function = match (sym_map.lookup(ppc), sym_map.lookup(entry.pc)) {
                    (Some((f1, _)), Some((f2, _))) => std::ptr::eq(f1, f2) || f1 == f2,
                    _ => true,
                };

                if !is_sequential || !same_function {
                    let branch_addr = match packet_map.get(&ppc) {
                        Some(&size) if size >= 4 => ppc + (size as u64) - 4,
                        _ => ppc,
                    };
                    *profile.entry((branch_addr, entry.pc)).or_insert(0) += 1;
                }
            }
        }

        prev_pc = Some(entry.pc);
        prev_thread = entry.thread;
    }

    eprintln!(
        "Found {} unique branch edges, {} total taken branches",
        profile.len(),
        profile.values().sum::<u64>()
    );

    // Write fdata output
    if output == "-" {
        let stdout = std::io::stdout();
        let mut w = BufWriter::new(stdout.lock());
        fdata::write_fdata(&mut w, &profile, &sym_map).expect("write failed");
    } else {
        let file = File::create(output).expect("cannot create output file");
        let mut w = BufWriter::new(file);
        fdata::write_fdata(&mut w, &profile, &sym_map).expect("write failed");
        eprintln!("Wrote fdata to {}", output);
    }
}

fn cmd_order(fdata_path: &str, output: &str) {
    let fdata_content = std::fs::read_to_string(fdata_path).expect("cannot read fdata");
    let cg = callgraph::CallGraph::from_fdata(&fdata_content);
    eprintln!(
        "Built call graph: {} functions, {} edges",
        cg.nodes.len(),
        cg.edges.len()
    );

    let order = cluster::hfsort(&cg);
    eprintln!("Computed order for {} functions", order.len());

    if output == "-" {
        for name in &order {
            println!("{}", name);
        }
    } else {
        let mut content = String::new();
        for name in &order {
            content.push_str(name);
            content.push('\n');
        }
        std::fs::write(output, &content).expect("cannot write output");
        eprintln!("Wrote function order to {}", output);
    }
}

fn cmd_reorder(binary: &str, order_path: &str, output: &str) {
    let order_content = std::fs::read_to_string(order_path).expect("cannot read order file");
    let order: Vec<&str> = order_content.lines().filter(|l| !l.is_empty()).collect();

    let bin_data = std::fs::read(binary).expect("cannot read binary");
    let result = reorder::reorder_functions(&bin_data, &order);
    std::fs::write(output, &result).expect("cannot write output");

    // Copy permissions from input
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let meta = std::fs::metadata(binary).expect("cannot read metadata");
        let perms = std::fs::Permissions::from_mode(meta.permissions().mode());
        std::fs::set_permissions(output, perms).expect("cannot set permissions");
    }

    eprintln!("Wrote reordered binary to {}", output);
}
