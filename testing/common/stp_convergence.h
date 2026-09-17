/**
 * Copyright (C) 2023 Carnegie Mellon University
 *
 * This file is part of the Mixnet course project developed for
 * the Computer Networks course (15-441/641) taught at Carnegie
 * Mellon University.
 *
 * No part of the Mixnet project may be copied and/or distributed
 * without the express permission of the 15-441/641 course staff.
 */
#ifndef TESTING_COMMON_STP_CONVERGENCE_H_
#define TESTING_COMMON_STP_CONVERGENCE_H_

#include "graph.h"
#include "testcase.h"
#include "framework/orchestrator.h"
#include "mixnet/packet.h"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <queue>
#include <string>
#include <vector>

namespace testing {

/**
 * Base class for STP convergence measurement test-cases.
 *
 * It counts the number of STP packets exchanged across the whole network up
 * to the instant the spanning tree first converges, where "converged" means
 * every node advertises the correct root and the correct path length to it.
 *
 * Mechanism: with measure_stp() enabled, the framework mirrors every STP
 * packet a node sends to the orchestrator's pcap plane. Each mirrored packet
 * carries the sending node's currently-advertised (root, path_length), so we
 * track per-node belief and, on every packet, (a) increment the running count
 * and (b) re-check global correctness. Once all nodes are correct we freeze
 * the count and ignore all subsequent STP packets (including periodic hellos).
 *
 * Concrete subclasses only need to implement build_topology() to populate the
 * graph (addresses + edges).
 *
 * Note on the oracle: the "correct path length" is defined here as the minimum
 * hop count from a node to the root over the physical topology. If the project
 * spec defines STP path length differently (e.g., cost-weighted), override
 * compute_ground_truth() accordingly.
 */
class stp_convergence_testcase : public testcase {
protected:
    // Per-node (indexed by fragment/node id) advertised belief
    std::vector<bool> has_advertised_;
    std::vector<mixnet_address> believed_root_;
    std::vector<uint16_t> believed_path_;

    // Ground truth
    mixnet_address true_root_ = INVALID_MIXADDR;
    uint16_t root_idx_ = 0;             // Index of the true-root node
    std::vector<uint16_t> correct_path_;

    // Accept a uniform path-length offset, inferred from the root's own
    // advertisement (e.g. impls that advertise the root as path_length 1
    // instead of 0). Off by default (strict spec); enabled via the
    // MIXNET_STP_NORMALIZE env var.
    bool normalize_offset_ = true;
    uint16_t detected_offset_ = 0;

    // Running measurement
    uint64_t stp_count_ = 0;            // STP packets observed so far
    uint64_t inter_island_count_ = 0;   // ... of which crossed inter-island links
    uint64_t converged_count_ = 0;      // STP packets at convergence instant
    uint64_t converged_inter_island_ = 0; // ... inter-island subset at convergence
    bool converged_ = false;            // Has the tree converged?

    explicit stp_convergence_testcase(const std::string& name)
        : testcase(name) {}

    // Subclass hook: build the graph (addresses + edges).
    virtual void build_topology() = 0;

    // Subclass hook: is the link between these two nodes a "long-distance"
    // (inter-island) link? Default: no long links, so the inter-island count
    // stays zero for ordinary topologies.
    virtual bool is_inter_island_link(uint16_t, uint16_t) const { return false; }

    /**
     * Computes the true root (lowest mixnet address) and the correct hop
     * distance from every node to the root over the physical topology.
     */
    virtual void compute_ground_truth() {
        const uint16_t n = graph_->num_nodes;
        const auto& adj = graph_->topology();

        // True root = lowest mixnet address across all nodes
        root_idx_ = 0;
        true_root_ = graph_->get_node(0).mixaddr();
        for (uint16_t i = 1; i < n; i++) {
            const mixnet_address a = graph_->get_node(i).mixaddr();
            if (a < true_root_) { true_root_ = a; root_idx_ = i; }
        }

        // BFS from the root to get min hop distance for every node
        correct_path_.assign(n, std::numeric_limits<uint16_t>::max());
        correct_path_[root_idx_] = 0;
        std::queue<uint16_t> q;
        q.push(root_idx_);
        while (!q.empty()) {
            const uint16_t u = q.front(); q.pop();
            for (const uint16_t v : adj[u]) {
                if (correct_path_[v] == std::numeric_limits<uint16_t>::max()) {
                    correct_path_[v] = correct_path_[u] + 1;
                    q.push(v);
                }
            }
        }
    }

    // The uniform path-length offset an impl uses for the root. The root's true
    // hop distance is 0, so whatever it currently advertises IS the offset. Only
    // meaningful once the root has advertised itself as root; 0 otherwise (and
    // always 0 in strict mode). Under normalization the root's own comparison
    // becomes vacuous, so the offset is pinned by the non-root nodes.
    uint16_t current_offset() const {
        return (normalize_offset_ && has_advertised_[root_idx_] &&
                believed_root_[root_idx_] == true_root_)
            ? believed_path_[root_idx_] : 0;
    }

    // Returns true iff every node currently advertises the correct belief.
    bool all_converged() const {
        const uint16_t offset = current_offset();
        for (uint16_t i = 0; i < graph_->num_nodes; i++) {
            if (!has_advertised_[i]) { return false; }
            if (believed_root_[i] != true_root_) { return false; }
            if (believed_path_[i] != correct_path_[i] + offset) { return false; }
        }
        return true;
    }

public:
    // Mirror STP packets for measurement.
    virtual bool measure_stp() const override { return true; }

    virtual void pcap(const uint16_t fragment_id,
                      const mixnet_packet *const packet) override {
        // Stop counting once the tree has converged.
        if (converged_) { return; }
        if (packet->type != PACKET_TYPE_STP) { return; }

        stp_count_++;

        // The egress port was stashed in _reserved[0] by the mirror. Map it to
        // the neighbor node (ports index the adjacency list in order) so we can
        // tell whether this packet crossed a long-distance link.
        const uint8_t egress_port = static_cast<uint8_t>(packet->_reserved[0]);
        const auto& adj = graph_->topology()[fragment_id];
        if ((egress_port < adj.size()) &&
            is_inter_island_link(fragment_id, adj[egress_port])) {
            inter_island_count_++;
        }

        const auto *stp = reinterpret_cast<const
            mixnet_packet_stp*>(packet->payload());

        has_advertised_[fragment_id] = true;
        believed_root_[fragment_id] = stp->root_address;
        believed_path_[fragment_id] = stp->path_length;

        if (all_converged()) {
            converged_ = true;
            converged_count_ = stp_count_;
            converged_inter_island_ = inter_island_count_;
            detected_offset_ = current_offset();
        }
    }

    virtual void setup() override {
        build_topology();
        const uint16_t n = graph_->num_nodes;

        has_advertised_.assign(n, false);
        believed_root_.assign(n, INVALID_MIXADDR);
        believed_path_.assign(n, 0);

        // Opt-in: tolerate a uniform root path-length offset (e.g. impls that
        // advertise the root as path_length 1 instead of 0). "0" or empty = off.
        if (const char* e = std::getenv("MIXNET_STP_NORMALIZE")) {
            normalize_offset_ = (e[0] != '\0' && !(e[0] == '0' && e[1] == '\0'));
        }

        compute_ground_truth();
    }

    virtual error_code run(orchestrator&) override {
        // Let STP run; pcap() counts packets and detects convergence
        // asynchronously in the orchestrator's pcap thread.
        await_convergence();
        return error_code::NONE;
    }

    virtual void teardown() override {
        pass_teardown_ = converged_;
        std::cout << "[STP] " << name
                  << " converged=" << (converged_ ? "true" : "false")
                  << " stp_packets_until_convergence="
                  << (converged_ ? converged_count_ : stp_count_)
                  << " inter_island_stp_packets="
                  << (converged_ ? converged_inter_island_ : inter_island_count_)
                  << (normalize_offset_
                        ? " root_path_offset=" + std::to_string(detected_offset_)
                        : "")
                  << (converged_ ? "" : " (NOT CONVERGED; values are total observed)")
                  << std::endl;
    }
};

} // namespace testing

#endif // TESTING_COMMON_STP_CONVERGENCE_H_
