// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProofOfLiveness} from "../src/ProofOfLiveness.sol";
import {IProofOfLiveness} from "../src/IProofOfLiveness.sol";

contract GameTheoryTest is Test {
    event Joined(address indexed user, uint256 stakeAmount, uint256 timestamp);
    event Heartbeat(address indexed user, uint256 timestamp);
    event Slashed(
        address indexed user,
        address indexed slasher,
        uint256 slasherReward,
        uint256 sinkAmount
    );

    ProofOfLiveness public pol;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public sink = makeAddr("sink");
    address public slasher = makeAddr("slasher");

    uint256 public constant REQUIRED_STAKE = 1 ether;
    uint256 public constant HEARTBEAT_INTERVAL = 1 days;

    function setUp() public {
        pol = new ProofOfLiveness(REQUIRED_STAKE, HEARTBEAT_INTERVAL, sink);

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
        vm.deal(slasher, 1 ether);
    }

    function test_JoinSucceeds() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        IProofOfLiveness.Participant memory p = pol.getParticipant(alice);
        assertEq(p.stakeAmount, REQUIRED_STAKE);
        assertEq(p.lastHeartbeat, block.timestamp);
        assertTrue(pol.isActive(alice));
    }

    function test_JoinRevertsIfAlreadyJoined() public {
        vm.startPrank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.AlreadyJoined.selector, alice));
        pol.join{value: REQUIRED_STAKE}();
        vm.stopPrank();
    }

    function test_JoinRevertsWithIncorrectStake() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IProofOfLiveness.IncorrectStake.selector, 0.5 ether, REQUIRED_STAKE)
        );
        pol.join{value: 0.5 ether}();
    }

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

    function test_HeartbeatRevertsIfNotActive() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NotActive.selector, alice));
        pol.heartbeat();
    }

    function test_SlashSucceedsAfterIntervalExpires() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        assertTrue(pol.isActive(alice));

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        assertFalse(pol.isActive(alice));

        uint256 slasherBalanceBefore = slasher.balance;
        uint256 sinkBalanceBefore = sink.balance;

        vm.prank(slasher);
        pol.slash(alice);

        uint256 expectedSlasherReward = REQUIRED_STAKE / 10;
        uint256 expectedSinkAmount = REQUIRED_STAKE - expectedSlasherReward;

        assertEq(slasher.balance, slasherBalanceBefore + expectedSlasherReward);
        assertEq(sink.balance, sinkBalanceBefore + expectedSinkAmount);
    }

    function test_SlashPayoutMath() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        uint256 slasherBefore = slasher.balance;
        uint256 sinkBefore = sink.balance;

        vm.prank(slasher);
        pol.slash(alice);

        uint256 slasherGain = slasher.balance - slasherBefore;
        uint256 sinkGain = sink.balance - sinkBefore;

        assertEq(slasherGain, 0.1 ether);
        assertEq(sinkGain, 0.9 ether);
        assertEq(slasherGain + sinkGain, REQUIRED_STAKE);
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

    function test_SlashRevertsIfActive() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        assertTrue(pol.isActive(alice));

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

    function test_HeartbeatExtendsDeadline() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + 12 hours);
        vm.prank(alice);
        pol.heartbeat();

        vm.warp(block.timestamp + 23 hours);
        assertTrue(pol.isActive(alice));

        vm.warp(block.timestamp + 2 hours);
        assertFalse(pol.isActive(alice));
    }

    function test_MultipleParticipantsIndependent() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.prank(bob);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + 12 hours);
        vm.prank(alice);
        pol.heartbeat();

        vm.warp(block.timestamp + 13 hours);

        assertTrue(pol.isActive(alice));
        assertFalse(pol.isActive(bob));

        vm.prank(slasher);
        pol.slash(bob);

        assertTrue(pol.isActive(alice));
    }

    function test_IsActiveReturnsFalseForNonParticipant() public {
        assertFalse(pol.isActive(alice));
    }

    function test_LateUserCannotHeartbeat() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1 seconds);

        assertFalse(pol.isActive(alice));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IProofOfLiveness.NotActive.selector, alice));
        pol.heartbeat();
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

    function test_SlashEmitsEvent() public {
        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.expectEmit(true, true, false, true);
        emit Slashed(alice, slasher, 0.1 ether, 0.9 ether);

        vm.prank(slasher);
        pol.slash(alice);
    }

    function test_JoinEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Joined(alice, REQUIRED_STAKE, block.timestamp);

        vm.prank(alice);
        pol.join{value: REQUIRED_STAKE}();
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

    function testFuzz_SlashPayoutAlwaysSumsToStake(uint256 stake) public {
        stake = bound(stake, 10, type(uint128).max);

        ProofOfLiveness customPol = new ProofOfLiveness(stake, HEARTBEAT_INTERVAL, sink);

        address player = makeAddr("player");
        vm.deal(player, stake);

        vm.prank(player);
        customPol.join{value: stake}();

        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        uint256 slasherBefore = slasher.balance;
        uint256 sinkBefore = sink.balance;

        vm.prank(slasher);
        customPol.slash(player);

        uint256 totalPaid = (slasher.balance - slasherBefore) + (sink.balance - sinkBefore);
        assertEq(totalPaid, stake);
    }
}
