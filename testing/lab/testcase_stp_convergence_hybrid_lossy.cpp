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
 * Scenario 2: the same irregular 8-node hybrid topology as
 * testcase_stp_convergence_hybrid, but over lossy ("satellite") links that
 * drop ~25% of packets. Measures STP packets exchanged until convergence.
 *
 */
class testcase_stp_convergence_hybrid_lossy final : public stp_convergence_testcase {
public:
    explicit testcase_stp_convergence_hybrid_lossy() :
        stp_convergence_testcase("testcase_stp_convergence_hybrid_lossy") {}

    // Lossy ("satellite") links: 50% packet loss per link. (Overridable via
    // the MIXNET_LOSS env var for experimentation/sweeps.)
    virtual uint8_t link_loss_percent() const override {
        const char *env = getenv("MIXNET_LOSS");
        return env ? static_cast<uint8_t>(atoi(env)) : 50;
    }

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
    testcase_stp_convergence_hybrid_lossy tc;
    return testcase::run_testcase(tc, argc, argv);
}
