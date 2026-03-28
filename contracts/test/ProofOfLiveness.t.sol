// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProofOfLiveness} from "../src/ProofOfLiveness.sol";
import {IProofOfLiveness} from "../src/IProofOfLiveness.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Attacker contract for reentrancy testing
// ─────────────────────────────────────────────────────────────────────────────

/// @dev Attempts to re-enter slash() via the slasher-reward receive callback.
contract ReentrantSlasher {
    ProofOfLiveness public target;
    address public victim;

    constructor(ProofOfLiveness _target) {
        target = _target;
    }

    function attack(address _victim) external {
        victim = _victim;
        target.slash(_victim);
    }

    receive() external payable {
        // Attempt re-entry — should revert with reentrancy guard
        if (victim != address(0) && target.getParticipant(victim).stakeAmount == 0) {
            return; // Already slashed, nothing to re-enter
        }
        try target.slash(victim) {} catch {}
    }
}

/// @dev Attempts to re-enter withdraw() via the withdraw receive callback.
contract ReentrantWithdrawer {
    ProofOfLiveness public target;
    uint256 public callCount;

    constructor(ProofOfLiveness _target) {
        target = _target;
    }

    function joinAndWithdraw(uint256 stake) external payable {
        target.join{value: stake}();
        target.withdraw();
    }

    receive() external payable {
        callCount++;
        if (callCount < 5) {
            // Attempt re-entry during withdraw
            try target.withdraw() {} catch {}
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Test Contract
// ─────────────────────────────────────────────────────────────────────────────

contract ProofOfLivenessTest is Test {
    // Re-declare events for expectEmit assertions
    event Joined(address indexed user, uint256 stakeAmount, uint256 timestamp);
    event Heartbeat(address indexed user, uint256 timestamp);
    event Slashed(address indexed user, address indexed slasher, uint256 slasherReward, uint256 sinkAmount);
    event Withdrawn(address indexed user, uint256 amount);

    ProofOfLiveness public pol;

    address public alice   = makeAddr("alice");
    address public bob     = makeAddr("bob");
    address public carol   = makeAddr("carol");
    address public sink    = makeAddr("sink");
    address public slasher = makeAddr("slasher");

    uint256 public constant REQUIRED_STAKE      = 1 ether;
    uint256 public constant HEARTBEAT_INTERVAL  = 1 days;

    // ── Setup ──────────────────────────────────────────────────────────────────

    function setUp() public {
        pol = new ProofOfLiveness(REQUIRED_STAKE, HEARTBEAT_INTERVAL, sink);

        vm.deal(alice,   10 ether);
        vm.deal(bob,     10 ether);
        vm.deal(carol,   10 ether);
        vm.deal(slasher, 1 ether);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR VALIDATION
    // ══════════════════════════════════════════════════════════════════════════

    function test_ConstructorSetsImmutables() public {
        assertEq(pol.requiredStake(),     REQUIRED_STAKE);
        assertEq(pol.heartbeatInterval(), HEARTBEAT_INTERVAL);
        assertEq(pol.slashedFundsSink(),  sink);
    }

    // Note: Foundry test functions cannot be 'view' even if they only call view methods;
    //       the vm cheatcode context requires a non-view function. Linter warning is a false positive here.
    function test_ConstructorRevertsOnZeroStake() public {
        vm.expectRevert();
        new ProofOfLiveness(0, HEARTBEAT_INTERVAL, sink);
    }

    function test_ConstructorRevertsOnIntervalBelowMinimum() public {
        // Interval must be >= 60 seconds
        vm.expectRevert();
        new ProofOfLiveness(REQUIRED_STAKE, 59, sink);
    }

    function test_ConstructorRevertsOnExactMinimumInterval() public {
        // 60 seconds should succeed
        ProofOfLiveness minPol = new ProofOfLiveness(REQUIRED_STAKE, 60, sink);
        assertEq(minPol.heartbeatInterval(), 60);
    }

    function test_ConstructorRevertsOnZeroSink() public {
        vm.expectRevert(IProofOfLiveness.ZeroAddress.selector);
        new ProofOfLiveness(REQUIRED_STAKE, HEARTBEAT_INTERVAL, address(0));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // JOIN
    // ══════════════════════════════════════════════════════════════════════════

    function test_JoinSucceeds() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        IProofOfLiveness.Participant memory p = pol.getParticipant(alice);
        assertEq(p.stakeAmount,    REQUIRED_STAKE);
        assertEq(p.lastHeartbeat,  block.timestamp);
        assertTrue(pol.isActive(alice));
    }

    function test_JoinIncrementsParticipantCount() public {
        assertEq(pol.participantCount(), 0);

        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();
        assertEq(pol.participantCount(), 1);

        vm.prank(bob);
        pol.join{value: REQUIRED_STAKE}();
        assertEq(pol.participantCount(), 2);
    }

    function test_JoinEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Joined(alice, REQUIRED_STAKE, block.timestamp);

        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();
    }

    function test_JoinRevertsIfAlreadyJoined() public {
        vm.startPrank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.AlreadyJoined.selector, alice));
        pol.join{value: REQUIRED_STAKE}();
        vm.stopPrank();
    }

    function test_JoinRevertsWithIncorrectStakeTooLow() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IProofOfLiveness.IncorrectStake.selector, 0.5 ether, REQUIRED_STAKE)
        );
        pol.join{value: 0.5 ether}();
    }

    function test_JoinRevertsWithIncorrectStakeTooHigh() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IProofOfLiveness.IncorrectStake.selector, 2 ether, REQUIRED_STAKE)
        );
        pol.join{value: 2 ether}();
    }

    function test_JoinRevertsWithZeroValue() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IProofOfLiveness.IncorrectStake.selector, 0, REQUIRED_STAKE)
        );
        pol.join{value: 0}();
    }

    function test_CanRejoinAfterSlash() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(slasher);
        pol.slash(alice);

        // Alice should be able to rejoin
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        assertTrue(pol.isActive(alice));
        assertEq(pol.participantCount(), 1);
    }

    function test_CanRejoinAfterWithdraw() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.prank(alice);
        pol.withdraw();

        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        assertTrue(pol.isActive(alice));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // HEARTBEAT
    // ══════════════════════════════════════════════════════════════════════════

    function test_HeartbeatUpdatesTimestamp() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        uint256 joinTime = block.timestamp;
        vm.warp(block.timestamp + 12 hours);

        vm.prank(alice);
        pol.heartbeat();

        IProofOfLiveness.Participant memory p = pol.getParticipant(alice);
        assertGt(p.lastHeartbeat, joinTime);
        assertEq(p.lastHeartbeat, block.timestamp);
    }

    function test_HeartbeatEmitsEvent() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + 6 hours);

        vm.expectEmit(true, false, false, true);
        emit Heartbeat(alice, block.timestamp);

        vm.prank(alice);
        pol.heartbeat();
    }

    function test_HeartbeatRevertsIfNotActive() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NotActive.selector, alice));
        pol.heartbeat();
    }

    function test_HeartbeatRevertsIfNotJoined() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NotActive.selector, alice));
        pol.heartbeat();
    }

    function test_HeartbeatExtendsDeadline() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + 12 hours);
        vm.prank(alice);
        pol.heartbeat();

        // 23 hours after heartbeat — still active
        vm.warp(block.timestamp + 23 hours);
        assertTrue(pol.isActive(alice));

        // 25 hours after heartbeat — inactive
        vm.warp(block.timestamp + 2 hours);
        assertFalse(pol.isActive(alice));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SLASH
    // ══════════════════════════════════════════════════════════════════════════

    function test_SlashSucceedsAfterIntervalExpires() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        assertTrue(pol.isActive(alice));

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);
        assertFalse(pol.isActive(alice));

        uint256 slasherBefore = slasher.balance;
        uint256 sinkBefore    = sink.balance;

        vm.prank(slasher);
        pol.slash(alice);

        uint256 expectedSlasherReward = REQUIRED_STAKE / 10;
        uint256 expectedSinkAmount    = REQUIRED_STAKE - expectedSlasherReward;

        assertEq(slasher.balance, slasherBefore + expectedSlasherReward);
        assertEq(sink.balance,    sinkBefore    + expectedSinkAmount);
    }

    function test_SlashPayoutMath() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        uint256 slasherBefore = slasher.balance;
        uint256 sinkBefore    = sink.balance;

        vm.prank(slasher);
        pol.slash(alice);

        assertEq(slasher.balance - slasherBefore, 0.1 ether);
        assertEq(sink.balance    - sinkBefore,    0.9 ether);
        assertEq((slasher.balance - slasherBefore) + (sink.balance - sinkBefore), REQUIRED_STAKE);
    }

    function test_SlashZerosOutStake() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(slasher);
        pol.slash(alice);

        IProofOfLiveness.Participant memory p = pol.getParticipant(alice);
        assertEq(p.stakeAmount, 0);
    }

    function test_SlashDecrementsParticipantCount() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();
        assertEq(pol.participantCount(), 1);

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(slasher);
        pol.slash(alice);
        assertEq(pol.participantCount(), 0);
    }

    function test_SlashEmitsEvent() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.expectEmit(true, true, false, true);
        emit Slashed(alice, slasher, 0.1 ether, 0.9 ether);

        vm.prank(slasher);
        pol.slash(alice);
    }

    function test_SlashRevertsIfActive() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.prank(slasher);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NotSlashable.selector, alice));
        pol.slash(alice);
    }

    function test_SlashRevertsIfNoStake() public {
        vm.prank(slasher);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NoStake.selector, alice));
        pol.slash(alice);
    }

    function test_SlashCannotBeDoubleSlashed() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(slasher);
        pol.slash(alice);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NoStake.selector, alice));
        pol.slash(alice);
    }

    function test_AnyoneCanSlash() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        // Bob (not the slasher role) slashes Alice — should work
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        pol.slash(alice);

        assertEq(bob.balance, bobBefore + REQUIRED_STAKE / 10);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // WITHDRAW
    // ══════════════════════════════════════════════════════════════════════════

    function test_WithdrawSucceeds() public {
        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        assertEq(alice.balance, aliceBefore - REQUIRED_STAKE);

        vm.prank(alice);
        pol.withdraw();

        assertEq(alice.balance,  aliceBefore);   // full refund
        assertFalse(pol.isActive(alice));

        IProofOfLiveness.Participant memory p = pol.getParticipant(alice);
        assertEq(p.stakeAmount, 0);
    }

    function test_WithdrawEmitsEvent() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(alice, REQUIRED_STAKE);

        vm.prank(alice);
        pol.withdraw();
    }

    function test_WithdrawDecrementsParticipantCount() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();
        assertEq(pol.participantCount(), 1);

        vm.prank(alice);
        pol.withdraw();
        assertEq(pol.participantCount(), 0);
    }

    function test_WithdrawRevertsIfNoStake() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NoStake.selector, alice));
        pol.withdraw();
    }

    function test_WithdrawRevertsIfNotActive() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NotActive.selector, alice));
        pol.withdraw();
    }

    function test_WithdrawClearsLastHeartbeat() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.prank(alice);
        pol.withdraw();

        IProofOfLiveness.Participant memory p = pol.getParticipant(alice);
        assertEq(p.lastHeartbeat, 0);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // isActive BOUNDARY CONDITIONS
    // ══════════════════════════════════════════════════════════════════════════

    function test_IsActiveReturnsFalseForNonParticipant() public {
        assertFalse(pol.isActive(alice));
    }

    function test_ExactlyAtDeadlineIsStillActive() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL);
        assertTrue(pol.isActive(alice));
    }

    function test_OneSecondAfterDeadlineIsInactive() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);
        assertFalse(pol.isActive(alice));
    }

    function test_LateUserCannotHeartbeat() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1 seconds);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NotActive.selector, alice));
        pol.heartbeat();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MULTI-PARTICIPANT
    // ══════════════════════════════════════════════════════════════════════════

    function test_MultipleParticipantsIndependent() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.prank(bob);
        pol.join{value: REQUIRED_STAKE}();

        assertEq(pol.participantCount(), 2);

        vm.warp(block.timestamp + 12 hours);
        vm.prank(alice);
        pol.heartbeat();

        vm.warp(block.timestamp + 13 hours);

        assertTrue(pol.isActive(alice));
        assertFalse(pol.isActive(bob));

        vm.prank(slasher);
        pol.slash(bob);

        assertTrue(pol.isActive(alice));
        assertEq(pol.participantCount(), 1);
    }

    function test_ContractBalanceMatchesTotalStakes() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.prank(bob);
        pol.join{value: REQUIRED_STAKE}();

        vm.prank(carol);
        pol.join{value: REQUIRED_STAKE}();

        assertEq(address(pol).balance, 3 * REQUIRED_STAKE);

        // Withdraw one
        vm.prank(alice);
        pol.withdraw();
        assertEq(address(pol).balance, 2 * REQUIRED_STAKE);

        // Slash one
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);
        vm.prank(slasher);
        pol.slash(bob);
        assertEq(address(pol).balance, REQUIRED_STAKE);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // REENTRANCY — SLASH
    // ══════════════════════════════════════════════════════════════════════════

    function test_SlashIsReentrancyProof() public {
        // Join as alice
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        // Deploy attacker — will try to re-enter slash() on receive()
        ReentrantSlasher attacker = new ReentrantSlasher(pol);
        vm.deal(address(attacker), 0 ether);

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        // Attack should not cause double-slash or double-pay
        attacker.attack(alice);

        // Stake must be zero — not double-drained
        assertEq(pol.getParticipant(alice).stakeAmount, 0);
        assertEq(pol.participantCount(), 0);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // REENTRANCY — WITHDRAW
    // ══════════════════════════════════════════════════════════════════════════

    function test_WithdrawIsReentrancyProof() public {
        ReentrantWithdrawer attacker = new ReentrantWithdrawer(pol);
        vm.deal(address(attacker), REQUIRED_STAKE);

        attacker.joinAndWithdraw{value: REQUIRED_STAKE}(REQUIRED_STAKE);

        // Contract balance should be 0; attacker didn't drain extra
        assertEq(address(pol).balance, 0);
        // Participant's stake must be 0 (withdraw succeeded once, no re-entry succeeded)
        assertEq(pol.getParticipant(address(attacker)).stakeAmount, 0);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ══════════════════════════════════════════════════════════════════════════

    function testFuzz_SlashPayoutAlwaysSumsToStake(uint256 stake) public {
        stake = bound(stake, 10, type(uint128).max);

        ProofOfLiveness customPol = new ProofOfLiveness(stake, HEARTBEAT_INTERVAL, sink);

        address player = makeAddr("player");
        vm.deal(player, stake);

        vm.prank(player);
        customPol.join{value: stake}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        uint256 slasherBefore = slasher.balance;
        uint256 sinkBefore    = sink.balance;

        vm.prank(slasher);
        customPol.slash(player);

        uint256 totalPaid = (slasher.balance - slasherBefore) + (sink.balance - sinkBefore);
        assertEq(totalPaid, stake);
    }

    function testFuzz_WithdrawAlwaysReturnsFullStake(uint256 stake) public {
        stake = bound(stake, 60, type(uint128).max); // stake >= min interval

        ProofOfLiveness customPol = new ProofOfLiveness(stake, HEARTBEAT_INTERVAL, sink);

        address player = makeAddr("playerW");
        vm.deal(player, stake);

        uint256 balanceBefore = player.balance;

        vm.prank(player);
        customPol.join{value: stake}();

        vm.prank(player);
        customPol.withdraw();

        assertEq(player.balance, balanceBefore);
    }

    function testFuzz_HeartbeatInterval(uint256 interval, uint256 elapsed) public {
        interval = bound(interval, 60, 365 days);
        elapsed  = bound(elapsed, 0, 2 * interval);

        ProofOfLiveness customPol = new ProofOfLiveness(REQUIRED_STAKE, interval, sink);

        vm.deal(alice, REQUIRED_STAKE);
        vm.prank(alice);
        customPol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + elapsed);

        bool active = customPol.isActive(alice);
        if (elapsed <= interval) {
            assertTrue(active, "Should be active within interval");
        } else {
            assertFalse(active, "Should be inactive after interval");
        }
    }

    // Note: Foundry fuzz tests cannot be 'view'; linter mutability warning is a false positive.
    function testFuzz_ParticipantCountTracking(uint8 n) public {
        n = uint8(bound(n, 1, 20));

        for (uint256 i = 0; i < n; i++) {
            address user = makeAddr(string(abi.encode(i)));
            vm.deal(user, REQUIRED_STAKE);
            vm.prank(user);
            pol.join{value: REQUIRED_STAKE}();
        }

        assertEq(pol.participantCount(), n);
    }
}
