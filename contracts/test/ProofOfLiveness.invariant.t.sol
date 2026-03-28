// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ProofOfLiveness} from "../src/ProofOfLiveness.sol";
import {IProofOfLiveness} from "../src/IProofOfLiveness.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Handler contract — drives all state transitions during invariant testing
// ─────────────────────────────────────────────────────────────────────────────

contract LivenessHandler is Test {
    ProofOfLiveness public pol;

    address public sink;
    uint256 public constant REQUIRED_STAKE    = 1 ether;
    uint256 public constant HEARTBEAT_INTERVAL = 1 days;

    // Track participants so we can make valid calls
    address[] public participants;
    mapping(address => bool) public isParticipant;

    // Ghost variable — mirrors what the sum of stakes should be
    uint256 public ghostTotalStaked;

    uint256 internal _actorSeed;

    constructor(ProofOfLiveness _pol, address _sink) {
        pol  = _pol;
        sink = _sink;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _getOrCreateActor(uint256 seed) internal returns (address actor) {
        actor = address(uint160(uint256(keccak256(abi.encode("actor", seed % 10)))));
        vm.deal(actor, REQUIRED_STAKE * 2);
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    function join(uint256 seed) external {
        address actor = _getOrCreateActor(seed);
        if (isParticipant[actor]) return;

        vm.prank(actor);
        try pol.join{value: REQUIRED_STAKE}() {
            participants.push(actor);
            isParticipant[actor] = true;
            ghostTotalStaked += REQUIRED_STAKE;
        } catch {}
    }

    function heartbeat(uint256 seed) external {
        if (participants.length == 0) return;
        address actor = participants[seed % participants.length];

        vm.prank(actor);
        try pol.heartbeat() {} catch {}
    }

    function slash(uint256 seed) external {
        if (participants.length == 0) return;
        address victim = participants[seed % participants.length];

        address sender = _getOrCreateActor(seed + 100);

        // Advance time sometimes to create slashable state
        if (seed % 3 == 0) {
            vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);
        }

        uint256 stakeBefore = pol.getParticipant(victim).stakeAmount;

        vm.prank(sender);
        try pol.slash(victim) {
            ghostTotalStaked -= stakeBefore;
            // Remove from tracking
            isParticipant[victim] = false;
        } catch {}
    }

    function withdraw(uint256 seed) external {
        if (participants.length == 0) return;
        address actor = participants[seed % participants.length];

        uint256 stakeBefore = pol.getParticipant(actor).stakeAmount;

        vm.prank(actor);
        try pol.withdraw() {
            ghostTotalStaked -= stakeBefore;
            isParticipant[actor] = false;
        } catch {}
    }

    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 0, 2 days);
        vm.warp(block.timestamp + seconds_);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant Test Contract
// ─────────────────────────────────────────────────────────────────────────────

contract ProofOfLivenessInvariantTest is Test {
    ProofOfLiveness public pol;
    LivenessHandler public handler;

    address public sink = makeAddr("invariant_sink");

    function setUp() public {
        pol     = new ProofOfLiveness(1 ether, 1 days, sink);
        handler = new LivenessHandler(pol, sink);

        // Restrict invariant fuzzer to only call handler functions
        targetContract(address(handler));
    }

    /// @dev INVARIANT A: The contract's native-token balance must always be >= the sum of all
    ///      active participant stakes recorded by the ghost variable.
    ///      Any violation means funds were incorrectly drained or double-spent.
    function invariant_contractBalanceGeGhostStaked() public {
        assertGe(
            address(pol).balance,
            handler.ghostTotalStaked(),
            "INV-A: contract balance < ghost total staked"
        );
    }

    /// @dev INVARIANT B: participantCount() must never exceed 10 (the max actors the handler creates)
    ///      and must never underflow (i.e., should always be >= 0).
    function invariant_participantCountIsConsistent() public view {
        uint256 count = pol.participantCount();
        // Handler creates at most 10 distinct actors
        assertLe(count, 10, "INV-B: participantCount exceeds max actors");
    }

    /// @dev INVARIANT C: isActive() must return false for any address with stakeAmount == 0.
    function invariant_noStakeImpliesNotActive() public {
        // Spot-check 5 deterministic addresses
        for (uint256 i = 0; i < 10; i++) {
            address a = address(uint160(uint256(keccak256(abi.encode("actor", i)))));
            IProofOfLiveness.Participant memory p = pol.getParticipant(a);
            if (p.stakeAmount == 0) {
                assertFalse(pol.isActive(a), "INV-C: isActive true with zero stake");
            }
        }
    }
}
