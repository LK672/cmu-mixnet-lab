# 15-441/15-641 Project 1: Mixnet

Project 1 for the 15-441/641 (Networking and the Internet) course at CMU. **Note**: This is a course project, so DO NOT push your solution to a public fork of this repo.

## Requirements

This project is designed to run on Linux. It has been tested on Ubuntu 20.04.2+, but you may get away with using other distributions.

## Building

You need `cmake` to build the project. On Ubuntu, you can install this with:
```bash
sudo apt install build-essential cmake
```

To build the project, in the root directory, run:
```bash
mkdir build
cd build
cmake ..
make
```

From now on you can always build the project by going to the `build` directory and running `make`.

## Running

Mixnet is test-driven. You can find some examples of these tests under the `testing` directory. For instance, [cp1/testcase_line_easy.cpp](testing/cp1/testcase_line_easy.cpp) demonstrates how to create a line topology with two nodes, 'subscribe' to packet data from both of them, and send a FLOOD packet from one to the other.

You can run mixnet in two modes: *autotester* mode, which we will be using to grade your implementation, and *manual* mode, which you can use to debug your implementation on either a single machine (using one process per mixnet node) or a cluster of machines. You will also use the manual mode to perform experiments on AWS (please see the handout for details).

To run in autotester mode, `cd` into the build directory and run:
```
./bin/cp1/testcase_line_easy -a # '-a' toggles the autotester
```
At the end, it should produce output indicating whether your implementation passed or failed that particular test-case.

You can also run the same test in 'manual' mode. For the `testcase_line_easy` example, you will need three terminal windows open: one for each of the two mixnet nodes, and one for the 'orchestrator', which bootstraps the topology, sets up connections, coordinates actions, etc. In general, you will need (n + 1) terminals, where n is the number of mixnet nodes in the test topology. First, start the orchestrator:
```
./bin/cp1/testcase_line_easy # Note that '-a' is missing
```
You should see output that looks like this: ```[Orchestrator] Started listening on port 9107```. Note the port (it's always 9107) the orchestrator is running on. Next, type the following command in each of the other two terminals:
```
./bin/node 127.0.0.1 9107
```
The format is as follows: `./node {server_ip} {server_port}` (also see `./bin/node -h`). The `{server_ip}` argument corresponds to the *public* IPv4 address of the machine on which the orchestrator is running; since we are running everything locally, we can simply use the machine's loopback address (127.0.0.1). Please refer to the other test-cases, as well as the test API in [framework/orchestrator.h](framework/orchestrator.h#L174) for more examples and detailed usage.

The entry-point to your code is the `run_node()` function in [mixnet/node.c](mixnet/node.c). For details, please refer to the handout. Good luck!

## Lab: Running experiments on EC2 (distributed mode)

Step 1 of the lab asks you to measure STP convergence on **8 EC2 servers in the same region** across the line, binary-tree, ring, and fully-connected topologies. To count the number of STP packets to convergence, we provide the following test cases:

```
testcase_stp_convergence_line   testcase_stp_convergence_tree
testcase_stp_convergence_ring   testcase_stp_convergence_full_mesh
```

To run these tests in EC2 in manual mode: one process is the *orchestrator* and each mixnet node is a separate `./bin/node` process on its own EC2 server. The orchestrator prints the `[STP] ... stp_packets_until_convergence=...` line when the run finishes.

### 1. Provision the cluster

- Launch **8 instances in the same region and VPC/subnet** (e.g. `t3.micro`, Ubuntu 26.04), all in **one security group**.
- Security group rules:
  - Inbound **SSH (22)** from your device (allowlist your device's public IP address. You can use `curl ipinfo.io` to get your current IP address -- note: your IP address may change periodically. If for some reason you suddenly cannot ssh in, check that your IP has not changed).
  - Inbound **All TCP** with **source = this same security group** (a self-referencing rule). The nodes talk to the orchestrator on ports **9107** (control) and **9108** (pcap), and to *each other* on **ephemeral ports** the framework picks at random — so restricting to a couple of fixed ports will not work. Keeping the cluster in one VPC and allowing all TCP *within the security group only* is the simplest correct setup.
- Use the instances' **private IPs** for all mixnet traffic (they're in the same VPC).

### 2. Duplicate code onto every instance

You can clone the repo using GitHub for each instance. However, the automation in step 4 rsyncs your local tree to each host and builds it there (by default). Before building, make sure that each instance has built the toolchain (`sudo apt install -y build-essential cmake`);

### 3. Launch the orchestrator and the nodes

Pick one instance as the orchestrator (it can also run a node — the orchestrator is just a coordinator and is **not** itself a mixnet node). On that instance:

```bash
cd build
./bin/lab/testcase_stp_convergence_line     # note: no '-a' — manual mode
# -> [Orchestrator] Started listening on port 9107
```

Then, on **each** of the 8 node instances (including the orchestrator's, since it hosts node 0), point a node at the orchestrator's **private** IP:

```bash
cd build
./bin/node <orchestrator-private-ip> 9107
```

Once all 8 nodes have connected, the orchestrator runs the topology and prints the result, e.g.:

```
[STP] testcase_stp_convergence_line converged=true stp_packets_until_convergence=42 inter_island_stp_packets=0
```

Repeat for `tree`, `ring`, and `full_mesh`. Record `stp_packets_until_convergence` for each topology for your plots.

### 4. Automate it (recommended)

To help automate the process of running your tests remotely, we've provided an LLM-generated (but TA validated) script :D [impls/run_ec2.sh](impls/run_ec2.sh) which connects to your instances over SSH: by default it rsyncs your local tree to every host and rebuilds, then starts the orchestrator on the first host, launches a node on every host, and prints the orchestrator's output.

```bash
# hosts.txt: one SSH target per line, one per node (8 lines for these topologies)
#   ubuntu@10.0.1.11
#   ubuntu@10.0.1.12
#   ...
SSH_KEY=<path to key> ./impls/run_ec2.sh testcase_stp_convergence_line hosts.txt   # rsyncs, builds, runs
```

After the first run has synced + built every host, add `SYNC=0` to reuse the existing build on later runs:
```bash
SSH_KEY=<path to key> SYNC=0 ./impls/run_ec2.sh testcase_stp_convergence_ring hosts.txt
```

**Measuring RTT (ping).** The `testcase_rtt_line` test-case pings between the two furthest nodes (0 → 7). You will need to modify your baseline `node.c` such that the *source node* prints the round-trip time when the response returns (see Step 1 in the handout — print `now - send_time` on receiving a ping response). To see the node logs when using `run_ec2.sh`, pass in  `NODE_LOGS=1` so the node output — where the RTT line is printed — is shown:
```bash
NODE_LOGS=1 SSH_KEY=<path to key> \
  ./impls/run_ec2.sh testcase_rtt_line hosts.txt
# -> look for "RTT to 7: <ms> ms" in node 0's per-host log block
```

You will need to implement your own testcase_rtt_*topology* for the remaining topologies. You may also find that RTT on the order of milliseconds may be too coarse. If this is the case, please change your ping implementation to report microseconds.   

See the comments at the top of the script for all options (`IMPL`, `NODE_LOGS`, `REMOTE_DIR`, `ORCH_IP`, `SSH`, `SYNC`).

> **Remember to stop or terminate your instances when you're done** — idle EC2 servers will drain your credits!

## Lab: STP convergence optimization

The lab asks you to reduce the number of **STP control messages** exchanged before the spanning tree converges. You submit a separate implementation for each scenario — each in its own folder under `impls/` — and each is built as the `node` binary and measured on its own convergence test-case (found under [testing/lab/](testing/lab)):

| implementation | scenario | test-case | what's counted | required? |
|---|---|---|---|---|
| `noloss/`  | hybrid, no loss    | `testcase_stp_convergence_hybrid`       | total STP packets to convergence | **yes** |
| `lossy/`   | hybrid, lossy links | `testcase_stp_convergence_hybrid_lossy` | total STP packets to convergence | **yes** |
| `islands/` | Hawaii islands     | `testcase_stp_convergence_islands`      | STP packets over the **inter-island** links only | optional (extra credit) |

The lossy links drop **50%** of packets per link by default (override with `MIXNET_LOSS=<pct>`); the islands topology joins island meshes with **50 ms** one-way inter-island links.

Each convergence test-case ends by printing a single `[STP]` line carrying the two metrics the lab is scored on:
```
[STP] testcase_stp_convergence_islands converged=true stp_packets_until_convergence=118 inter_island_stp_packets=20
```
- **`stp_packets_until_convergence`** — total `PACKET_TYPE_STP` control packets every node sent, counted from startup until the tree first *converges*. For the sake of this project, we consider that a tree is **converged** at the first instant every node's latest STP advertisement reports both the correct root (the lowest node address) **and** the correct path length (its shortest-hop distance to the root).
- **`inter_island_stp_packets`** — the subset of those STP packets that crossed a long-distance inter-island link, over the same window. This is your score for the `islands` scenario; it is `0` for topologies with no inter-island links.

**How the leaderboard number is computed.** The autograder runs each scenario **10 times** and reports the mean of the metric over those runs. A scenario earns a leaderboard entry only if it converges on all 10 runs. Note that passing the tests does not give you full points; it simply means you have an implementation that converges. **Your score will be based off of the number of packets to convergence.**

Because the grader averages 10 runs, we recommend testing your implementation locally with multiple repetitions `run_impl.sh` — it prints the per-run metrics and the min / mean / max across runs:
```bash
./impls/run_impl.sh islands 10
# ...
# converged:            10/10
# total STP packets     min=59  mean=60.0  max=61
# inter-island STP      min=11  mean=12.0  max=13
```

### Writing your implementations

Your **baseline** solution — your working cp1/cp2 code — lives in `mixnet/`. That's what builds by default (both `run_impl.sh` and `run_ec2.sh` build `mixnet/` as-is unless you point them elsewhere), and it's where the baseline numbers come from.

Each **optimized** scenario is then a self-contained **folder** under [impls/](impls) holding a complete implementation: an entry `node.c` (the file with `run_node`) plus any helper `.c`/`.h` files. Start from your baseline in `mixnet/` and optimize how/when it emits STP packets. Stubs are provided:
```
impls/noloss/node.c   impls/lossy/node.c   impls/islands/node.c
```
If your solution spans multiple files, just make sure the helper `.c`/`.h` files are also in the same scenario folder — every `.c` in a scenario folder is compiled together. 

(Yes, unfortunately this is pretty redundant, but we wanted to offer flexibility in case students want to create custom `node.h` files per scenario.)

### Running the convergence tests

The `impls/run_impl.sh` helper builds the `node` binary, runs the matching convergence test-case in autotest mode, and reports the per-run metrics and their min/mean/max. **By default it builds whatever is in `mixnet/`** — i.e. your **baseline** working solution — so the default form gives you the baseline numbers:
```bash
./impls/run_impl.sh noloss          # mixnet/ as-is (baseline), hybrid topology
./impls/run_impl.sh lossy 10        # mixnet/ as-is, averaged over 10 runs
./impls/run_impl.sh islands         # mixnet/ as-is (extra-credit islands topology)
```
The first argument is the **scenario** (`noloss`→hybrid, `lossy`→lossy hybrid, `islands`→Hawaii islands), which picks the topology / test-case.

To measure an **optimized** implementation instead, pass `--impl` pointing at its sources (a single `.c` file, built as `node.c`, or a folder of sources). It's staged into `mixnet/` for the run and restored afterwards — so you can compare baseline vs. optimized on the same scenario:
```bash
./impls/run_impl.sh islands 10                       # baseline (mixnet/) on the islands scenario
./impls/run_impl.sh islands 10 --impl impls/islands  # your optimized impls/islands/ folder
```

To do it by hand instead: install your sources into `mixnet/`, run `make` in `build/`, then `./bin/lab/testcase_stp_convergence_islands -a`.

> Note: the local build uses the same compiler flags as the autograder (see [CMakeLists.txt](CMakeLists.txt)), so a clean local build will compile on the autograder too.

### Submitting

Package your implementations into `submission.zip` and upload it to Gradescope:
```bash
./impls/make_submission.sh          # zips the impls/{noloss,lossy,islands}/ folders
```
`noloss/` and `lossy/` are required; `islands/` is optional (extra credit). Each folder must contain an entry `node.c` (the file with `run_node`); any helper `.c`/`.h` files in the folder are bundled and compiled with it, and the immutable framework headers are never included.
