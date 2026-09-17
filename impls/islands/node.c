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

/* ======================================================================
 *  LAB SCENARIO 3 — Hawaii islands, long links   (OPTIONAL, EXTRA CREDIT)
 * ----------------------------------------------------------------------
 *  Graded by:  testcase_stp_convergence_islands
 *  Topology:   8 nodes across 3 islands (O'ahu K4, Maui single node, Hawai'i
 *              K3) joined by two 50 ms one-way inter-island links, with Maui
 *              bridging the two meshes (see the handout figure).
 *  Goal:       minimize the STP control messages sent over the expensive
 *              inter-island links. 
 *              Nodes do not know a priori which links are long-distance;
 *  Hint:       What signals can you use to help infer which links are 
 *              long-distance?
 *
 *  This folder is optional.
 *
 *
 *  Build & measure locally:   ./impls/run_impl.sh islands
 *  Submit:                    ./impls/make_submission.sh
 * ====================================================================== */

#include "node.h"

#include "connection.h"
#include "packet.h"

#include <stdio.h>
#include <stdlib.h>

void run_node(void *const handle,
              volatile bool *const keep_running,
              const struct mixnet_node_config c) {

    (void) c;
    (void) handle;
    while(*keep_running) {}
}
