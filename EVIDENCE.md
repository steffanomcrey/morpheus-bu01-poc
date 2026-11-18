# BU-01 evidence

Scope enumeration: the target is an Appendix A entry: BuildersV4 proxy 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9 on Base, implementation 0x18FAEf315b40A6D9cf49628f1133B1Aa507513B0 (Sourcify exact_match). The MOR token used is the Appendix A Base MOROFT 0x7431aDa8a591C955a994a21710752EF9b882b8e3. No other contract is a target.

Live-state reads (read-only, Base, threat-model phase, block ~58,976,101):
- subnetCreationFeeAmount() = 0 (subnet creation is free). minimalWithdrawLockPeriod() = 604800.
- BuildersV4 MOR balance equals totalDeposited to the wei: ~3,000,986 MOR deposited protocol-wide.
- RewardPool pool 3 emits 3,456 MOR/day decreasing ~0.5926 MOR/day; BuildersTreasuryV2 holds ~175,417 MOR vs ~66,456 MOR unclaimed (context for subnet reward flows, not part of this finding).
- Deployed implementation differs from the stale Morpheus Docs table; the live EIP-1967 slot was used.

Code evidence (verified deployed source, BuildersV4.sol):
- _validateSubnet: checks name non-empty, admin != 0, claimAdmin != 0, withdrawLockPeriodAfterDeposit >= minimalWithdrawLockPeriod. No upper bound.
- editSubnet: onlySubnetOwner (the subnet admin), requires only that the name is unchanged, then replaces the whole Subnet struct.
- withdraw: requires block.timestamp > userData.lastDeposit + subnet.withdrawLockPeriodAfterDeposit, reading the CURRENT subnet lock. UserData has no lock snapshot field.
- deposit: requires cumulative >= subnet.minimalDeposit (also editable), sets userData.lastDeposit.

Reproduction: poc/ run 3 times at pinned Base block 58,973,209: PASS, PASS, PASS (gas 734,559 each). Controls inside the test: an unedited subnet pays out in full after the original lock (+8 days), and editSubnet from a non-admin reverts.

Full analysis and gate re-check, including the explicit material-difference argument against Trust Security TRST-M-7 and TRST-L-4 (predecessor BuildersV2 audit): validation/BU-01/VERDICT.md. Threat model: recon/hypo-builders.md (BU-01, Part A fence-verification table). Fence: recon/audit-fence.md (BuildersV4 itself has zero audit coverage).
