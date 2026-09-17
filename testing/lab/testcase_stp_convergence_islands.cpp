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
#include "common/testing.h"
#include "common/stp_convergence.h"

#include <vector>

/**
 * EC "ALOHA-ANDREWNET" scenario: 8 nodes across 3 islands. Each island is a
 * full intra-island mesh; islands are joined by single, loop-free, long-
 * distance inter-island links. Maui is a single node that bridges the two
 * meshes:
 *
 *   O'ahu {0,1,2,3} --1==4-- Maui {4} --4==5-- Hawai'i {5,6,7}
 *
 * Reports both total STP packets to convergence and how many of those crossed
 * the two inter-island (long-distance) links -- the baseline students try to
 * beat by keeping STP traffic off the long links.
 */
class testcase_stp_convergence_islands final : public stp_convergence_testcase {
public:
    explicit testcase_stp_convergence_islands() :
        stp_convergence_testcase("testcase_stp_convergence_islands") {}

    virtual bool is_inter_island_link(uint16_t a, uint16_t b) const override {
        auto edge = [&](uint16_t x, uint16_t y) {
            return (a == x && b == y) || (a == y && b == x);
        };
        return edge(1, 4) || edge(4, 5);
    }

    virtual void build_topology() override {
        init_graph(8);

        // Each island is a full intra-island mesh (Maui is a single node).
        const std::vector<std::vector<uint16_t>> islands = {
            {0, 1, 2, 3},       // O'ahu
            {4},                // Maui
            {5, 6, 7},          // Hawai'i (Big Island)
        };
        for (const auto& island : islands) {
            for (size_t i = 0; i < island.size(); i++) {
                for (size_t j = i + 1; j < island.size(); j++) {
                    graph_->add_edge(island[i], island[j]);
                }
            }
        }
        // Single, loop-free inter-island links (the island chain), each with a
        // "long-distance" one-way latency; intra-island links have none. This
        // is the signal a node's ping-based detector uses to find long links.
        const uint16_t kInterIslandLatencyMs = 50;
        graph_->add_edge(1, 4, kInterIslandLatencyMs);
        graph_->add_edge(4, 5, kInterIslandLatencyMs);

        // Inter-island latency dominates; keep a generous convergence budget.
        max_convergence_time_ms_ = 5000;
    }
};

int main(int argc, char **argv) {
    testcase_stp_convergence_islands tc;
    return testcase::run_testcase(tc, argc, argv);
}
