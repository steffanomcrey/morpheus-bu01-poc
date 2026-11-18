TARGET
BuildersV4 proxy 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9 on Base (Appendix A), implementation 0x18FAEf315b40A6D9cf49628f1133B1Aa507513B0 (Sourcify exact_match), functions createSubnet, editSubnet, deposit, withdraw, and _validateSubnet. Verified source: contracts/builder-protocol/BuildersV4.sol.

INVARIANT
The withdraw lock period and minimum deposit a staker accepts at deposit time are the terms governing that deposit. A subnet admin must not be able to worsen those terms retroactively for funds already deposited by third parties.

IMPACT
_validateSubnet checks only withdrawLockPeriodAfterDeposit >= minimalWithdrawLockPeriod (604800 s); there is no upper bound, and UserData stores only lastDeposit, never the lock in force at deposit. editSubnet, gated solely by onlySubnetOwner (the subnet's own admin, a role anyone obtains free: createSubnet is permissionless and the live subnetCreationFeeAmount is 0), replaces the whole Subnet struct at any time. An admin who first attracts third-party deposits under a normal 7-day lock can then raise the lock to 2^110 seconds (or near uint128 max, where lastDeposit + lock additionally overflow-reverts), and every existing staker's withdraw reverts indefinitely: 100% of that subnet's third-party deposits frozen, releasable only by the same admin. Raising minimalDeposit in the same edit forces all-or-nothing exits. Funds at risk per subnet = that subnet's TVL; protocol-wide deposits are ~3,000,986 MOR = $2,130,209.76 at $0.70987/MOR (CoinGecko, morpheusai, 2026-11-18), so a single popular subnet is material. The PoC freezes a demonstrated 100 MOR = $70.99; the mechanism bound is the full victim-subnet TVL. CVSS 3.1: 6.5 (AV:N/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:H).

PRECONDITIONS
Attacker is admin of one subnet (self-created, free) with at least one external staker who deposited before the edit. No protocol owner, multisig, or other privileged role is used; the subnet admin is the attacker itself.

ATTACK
1. Attacker calls createSubnet with admin = attacker, withdrawLockPeriodAfterDeposit = 604800, minimalDeposit = 1.
2. Victim deposits 100 MOR into the subnet under those visible terms.
3. Attacker calls editSubnet with the same subnet name and withdrawLockPeriodAfterDeposit = 2^110.
4. _validateSubnet passes (only a lower bound is checked) and the new lock replaces the old one for all stakers.
5. Victim calls withdraw after the original 7-day term: reverts, "BU: user withdraw is locked", because withdraw reads the CURRENT subnet lock against the victim's stored lastDeposit.
6. Victim retries after +100 years of fork time: still reverts; the 100 MOR remains inside BuildersV4.
7. Control in the PoC: an identical subnet whose lock is never edited pays the victim out in full at +8 days, and a non-admin editSubnet reverts.

POC
Public Foundry project (linked repo): Base mainnet fork pinned at block 58,973,209, run with `forge test`. Two subnets are created by a fresh attacker EOA; a victim deposits 100 MOR into each (balances set by fork-only storage probing). Control subnet withdraws in full after +8 days. Attack subnet: after the admin's editSubnet raises the lock to 2^110, the victim's withdraw reverts at +8 days and at +100 years, the victim's balance stays 0, and the 100 MOR remains in BuildersV4. Non-admin edit reverts. 3/3 runs pass (identical gas 734,559). No protocol owner/admin/multisig is impersonated.

FIX
Snapshot the withdraw terms per user at deposit: store withdrawLockPeriodAfterDeposit (and minimalDeposit) in UserData on every deposit and evaluate withdraw against the snapshot, or bound editSubnet so it can only lower the lock for existing deposits / apply increases solely to deposits made after the edit, plus enforce a sane global maximum lock in _validateSubnet.
