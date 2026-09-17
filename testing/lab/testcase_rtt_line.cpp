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

/**
 * RTT driver for the 8-node LINE topology (Step 1 of the lab).
 *
 *      0 - 1 - 2 - 3 - 4 - 5 - 6 - 7
 *
 * The two furthest nodes are 0 and 7, so this test-case pings from node 0 to
 * node 7. It does NOT compute the RTT itself: the round-trip time is printed by
 * the *source node* (node 0) when the ping response returns to it -- see the
 * handout (Step 1, RTT), which asks you to print `now - send_time` on receiving
 * a ping response. Because both timestamps are taken on the same node, the
 * measurement is unaffected by clock differences between servers.
 *
 * Run it in manual mode across your cluster (co-locate the orchestrator with
 * node 0); the RTT line appears on node 0's terminal. This test-case only
 * injects the ping and confirms the round trip completed (request delivered at
 * the destination, response delivered back at the source => two pcap events).
 *
 * To measure another topology, copy this file, swap the topology in setup(),
 * and ping between that topology's two furthest nodes.
 */
class testcase_rtt_line final : public testcase {
public:
    explicit testcase_rtt_line() : testcase("testcase_rtt_line") {}

    virtual void pcap(const uint16_t /* fragment_id */,
                      const mixnet_packet *const packet) override {
        // We only expect the ping request (delivered at node 7) and the ping
        // response (delivered back at node 0).
        if (packet->type == PACKET_TYPE_PING) { pcap_count_++; }
        else { pass_pcap_ = false; }
    }

    virtual void setup() override {
        init_graph(8);
        graph_->generate_topology(graph::type::LINE);
        // Default mixnet addresses are the node indices (0..7), so the line is
        // 0 - 1 - ... - 7 and the two furthest nodes are 0 and 7.
    }

    virtual error_code run(orchestrator& o) override {
        await_convergence();                 // let STP + routing settle
        // Watch every node's user-delivered packets via the pcap plane.
        for (uint16_t i = 0; i < graph_->num_nodes; i++) {
            DIE_ON_ERROR(o.pcap_change_subscription(i, true));
        }
        // Ping between the two furthest nodes; source = node 0.
        DIE_ON_ERROR(o.send_packet(0, 7, PACKET_TYPE_PING));
        await_packet_propagation();
        return error_code::NONE;
    }

    virtual void teardown() override {
        // Request delivered at node 7 + response delivered back at node 0.
        pass_teardown_ = (pcap_count_ == 2);
    }
};

int main(int argc, char **argv) {
    testcase_rtt_line tc;
    return testcase::run_testcase(tc, argc, argv);
}
