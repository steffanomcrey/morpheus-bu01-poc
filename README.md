# PoC for BU-01 (Morpheus bug bounty)

Foundry fork test against the deployed contracts, in the program's required format.

Run (one command, from a clean clone; only an RPC endpoint is needed, already set in the test):

    forge test

The test pins its fork block in the source, uses no owner/admin/multisig impersonation,
and asserts the loss with balance-before/after checks plus a non-privileged control call.
See ../REPORT.md for the finding and ../EVIDENCE.md for live-state evidence and run logs.
