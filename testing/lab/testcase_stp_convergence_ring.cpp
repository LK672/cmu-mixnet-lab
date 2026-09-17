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
 * converges on an 8-node ring topology.
 */
class testcase_stp_convergence_ring final : public stp_convergence_testcase {
public:
    explicit testcase_stp_convergence_ring() :
        stp_convergence_testcase("testcase_stp_convergence_ring") {}

    virtual void build_topology() override {
        init_graph(8);
        graph_->generate_topology(graph::type::RING);
    }
};

int main(int argc, char **argv) {
    testcase_stp_convergence_ring tc;
    return testcase::run_testcase(tc, argc, argv);
}
