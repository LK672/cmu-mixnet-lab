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
 * Measures the number of STP packets exchanged until the spanning tree
 * converges on an 8-node (near-complete) binary tree topology:
 *
 *                        0
 *                      /   \
 *                     1     2
 *                    / \   / \
 *                   3   4 5   6
 *                  /
 *                 7
 *
 * There is no built-in binary-tree generator, so the edges are wired up
 * explicitly here.
 */
class testcase_stp_convergence_tree final : public stp_convergence_testcase {
public:
    explicit testcase_stp_convergence_tree() :
        stp_convergence_testcase("testcase_stp_convergence_tree") {}

    virtual void build_topology() override {
        init_graph(8);
        graph_->add_edge(0, 1);
        graph_->add_edge(0, 2);
        graph_->add_edge(1, 3);
        graph_->add_edge(1, 4);
        graph_->add_edge(2, 5);
        graph_->add_edge(2, 6);
        graph_->add_edge(3, 7);
    }
};

int main(int argc, char **argv) {
    testcase_stp_convergence_tree tc;
    return testcase::run_testcase(tc, argc, argv);
}
