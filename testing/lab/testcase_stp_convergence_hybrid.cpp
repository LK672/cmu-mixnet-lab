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

/**
 * Measures the number of STP packets exchanged until convergence on the
 * irregular 8-node hybrid topology used in Scenario 1 (no loss) and
 * Scenario 2 (lossy links) of the lab.
 *
 * Edges (root = node 0, the lowest address):
 *
 *      0 -- 1, 0 -- 3, 0 -- 6
 *      1 -- 2, 1 -- 3
 *      2 -- 4, 2 -- 5
 *      3 -- 4, 3 -- 6
 *      4 -- 5, 4 -- 7
 *      6 -- 7
 *
 * Hop distances from the root: 0:0, {1,3,6}:1, {2,4,7}:2, 5:3. Node 5 is
 * equidistant from the root via node 2 and node 4, so this topology
 * exercises the address tie-break (parent = node 2).
 */
class testcase_stp_convergence_hybrid final : public stp_convergence_testcase {
public:
    explicit testcase_stp_convergence_hybrid() :
        stp_convergence_testcase("testcase_stp_convergence_hybrid") {}

    virtual void build_topology() override {
        init_graph(8);
        graph_->add_edge(0, 1);
        graph_->add_edge(0, 3);
        graph_->add_edge(0, 6);
        graph_->add_edge(1, 2);
        graph_->add_edge(1, 3);
        graph_->add_edge(2, 4);
        graph_->add_edge(2, 5);
        graph_->add_edge(3, 4);
        graph_->add_edge(3, 6);
        graph_->add_edge(4, 5);
        graph_->add_edge(4, 7);
        graph_->add_edge(6, 7);
    }
};

int main(int argc, char **argv) {
    testcase_stp_convergence_hybrid tc;
    return testcase::run_testcase(tc, argc, argv);
}
