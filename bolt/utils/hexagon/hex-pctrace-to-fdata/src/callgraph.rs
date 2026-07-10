//===- callgraph.rs - Weighted call graph from BOLT fdata ----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

/// Weighted call graph built from BOLT fdata profile data.
///
/// Each node is a function with an execution count (sum of outgoing
/// edge weights).  Each edge represents a call between two functions
/// with a weight proportional to the number of observed transitions.

use std::collections::HashMap;

pub struct CallGraph {
    /// Function name -> node index
    pub name_to_id: HashMap<String, usize>,
    /// Node index -> function name
    pub nodes: Vec<String>,
    /// Node execution counts (sum of all edge weights involving this node)
    pub counts: Vec<u64>,
    /// Edges: (src_id, dst_id, weight)
    pub edges: Vec<(usize, usize, u64)>,
}

impl CallGraph {
    /// Parse BOLT fdata format and build a call graph.
    ///
    /// fdata format:
    ///   1 src_func src_offset 1 dst_func dst_offset mispred count
    ///
    /// We aggregate all edges between the same (src_func, dst_func) pair,
    /// summing counts.  Intra-function edges (src == dst) are used for node
    /// weights but not included as call graph edges.
    pub fn from_fdata(content: &str) -> Self {
        let mut name_to_id: HashMap<String, usize> = HashMap::new();
        let mut nodes: Vec<String> = Vec::new();
        let mut edge_map: HashMap<(usize, usize), u64> = HashMap::new();

        let get_or_insert = |name: &str,
                             name_to_id: &mut HashMap<String, usize>,
                             nodes: &mut Vec<String>|
         -> usize {
            if let Some(&id) = name_to_id.get(name) {
                id
            } else {
                let id = nodes.len();
                nodes.push(name.to_string());
                name_to_id.insert(name.to_string(), id);
                id
            }
        };

        for line in content.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() < 8 {
                continue;
            }
            // Format: 1 src_func src_off 1 dst_func dst_off mispred count
            let src_func = parts[1];
            let dst_func = parts[4];
            let count: u64 = match parts[7].parse() {
                Ok(c) => c,
                Err(_) => continue,
            };

            let src_id = get_or_insert(src_func, &mut name_to_id, &mut nodes);
            let dst_id = get_or_insert(dst_func, &mut name_to_id, &mut nodes);

            // Aggregate inter-function edges
            if src_id != dst_id {
                *edge_map.entry((src_id, dst_id)).or_insert(0) += count;
            }
        }

        // Compute node counts from edge weights
        let mut counts = vec![0u64; nodes.len()];
        for (&(src, dst), &weight) in &edge_map {
            counts[src] += weight;
            counts[dst] += weight;
        }

        let edges: Vec<(usize, usize, u64)> = edge_map
            .into_iter()
            .map(|((s, d), w)| (s, d, w))
            .collect();

        CallGraph {
            name_to_id,
            nodes,
            counts,
            edges,
        }
    }
}
