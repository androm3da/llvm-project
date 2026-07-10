//===- cluster.rs - HFSort-style call graph clustering --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

/// HFSort-style greedy call graph clustering for function reordering.
///
/// Based on the algorithm from BOLT's HFSort (bolt/lib/Passes/HFSort.cpp):
/// 1. Start with one cluster per function, weighted by execution count
/// 2. Sort inter-cluster call edges by weight
/// 3. Greedily merge the two clusters connected by the heaviest edge
/// 4. Output function names in merged-cluster order (hot to cold)

use crate::callgraph::CallGraph;
use std::collections::BinaryHeap;
use std::cmp::Ordering;

/// An edge between two clusters in the priority queue.
#[derive(Clone)]
struct ClusterEdge {
    weight: u64,
    src_cluster: usize,
    dst_cluster: usize,
}

impl PartialEq for ClusterEdge {
    fn eq(&self, other: &Self) -> bool {
        self.weight == other.weight
    }
}
impl Eq for ClusterEdge {}

impl PartialOrd for ClusterEdge {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for ClusterEdge {
    fn cmp(&self, other: &Self) -> Ordering {
        self.weight.cmp(&other.weight)
    }
}

/// Perform HFSort greedy clustering on the call graph.
/// Returns function names in optimized order.
pub fn hfsort(cg: &CallGraph) -> Vec<String> {
    let n = cg.nodes.len();
    if n == 0 {
        return Vec::new();
    }

    // Each cluster: list of node IDs in order, total weight
    let mut cluster_members: Vec<Vec<usize>> = (0..n).map(|i| vec![i]).collect();
    let mut cluster_weight: Vec<u64> = cg.counts.clone();
    // Union-find: which cluster does each node belong to?
    let mut node_cluster: Vec<usize> = (0..n).collect();

    // Find the root cluster for a node (with path compression)
    fn find_cluster(node_cluster: &mut [usize], mut node: usize) -> usize {
        while node_cluster[node] != node {
            node_cluster[node] = node_cluster[node_cluster[node]];
            node = node_cluster[node];
        }
        node
    }

    // Build priority queue of inter-cluster edges
    let mut heap = BinaryHeap::new();
    for &(src, dst, weight) in &cg.edges {
        heap.push(ClusterEdge {
            weight,
            src_cluster: src,
            dst_cluster: dst,
        });
    }

    // Greedily merge clusters connected by heaviest edges
    while let Some(edge) = heap.pop() {
        let src_root = find_cluster(&mut node_cluster, edge.src_cluster);
        let dst_root = find_cluster(&mut node_cluster, edge.dst_cluster);

        // Skip if already in the same cluster
        if src_root == dst_root {
            continue;
        }

        // Merge smaller cluster into larger (by member count)
        let (keep, merge) = if cluster_members[src_root].len() >= cluster_members[dst_root].len() {
            (src_root, dst_root)
        } else {
            (dst_root, src_root)
        };

        // Append merged cluster's members to keeper
        let merge_members = std::mem::take(&mut cluster_members[merge]);
        cluster_members[keep].extend(merge_members);
        cluster_weight[keep] += cluster_weight[merge];
        cluster_weight[merge] = 0;
        node_cluster[merge] = keep;
    }

    // Collect all clusters, sort by total weight (hottest first)
    let mut clusters: Vec<(u64, &Vec<usize>)> = cluster_members
        .iter()
        .enumerate()
        .filter(|(_, members)| !members.is_empty())
        .map(|(i, members)| (cluster_weight[i], members))
        .collect();
    clusters.sort_by(|a, b| b.0.cmp(&a.0));

    // Flatten clusters into function order
    let mut order = Vec::with_capacity(n);
    for (_, members) in &clusters {
        for &node_id in *members {
            order.push(cg.nodes[node_id].clone());
        }
    }

    order
}
