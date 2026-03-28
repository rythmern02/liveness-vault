// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IProofOfLiveness} from "./IProofOfLiveness.sol";

/// @title ProofOfLiveness
/// @author Rootcamp Capstone
/// @notice A cryptoeconomic Proof-of-Liveness primitive where participants must submit
///         periodic heartbeats to remain active. Failing to do so within the configured
///         interval results in stake slashing by any external caller.
/// @dev Security model:
///      - All state-mutating functions follow the Checks-Effects-Interactions (CEI) pattern.
///      - A re-entrancy guard (`_locked`) prevents recursive calls during ETH transfers.
///      - Participant state is zeroed before any external call, eliminating double-spend risk.
///      - All constructor arguments are validated to prevent misconfiguration.
///
///      Slashing mechanics:
///      - The slasher earns 10% of the slashed stake as a gas bounty.
///      - The remaining 90% is forwarded to `slashedFundsSink` (DAO treasury / burn address).
///
///      Withdrawal mechanics:
///      - Active participants may exit at any time and reclaim 100% of their stake.
///      - Withdrawn participants can rejoin by calling join() again.
contract ProofOfLiveness is IProofOfLiveness {
    // ─────────────────────────────────────────────────────────── Immutables ─────

    /// @inheritdoc IProofOfLiveness
    uint256 public immutable requiredStake;

    /// @inheritdoc IProofOfLiveness
    uint256 public immutable heartbeatInterval;

    /// @inheritdoc IProofOfLiveness
    address public immutable slashedFundsSink;

    // ──────────────────────────────────────────────────────────── Storage ───────

    /// @dev Participant state keyed by address.
    mapping(address => Participant) private _participants;

    /// @dev Tracks the number of currently active (non-slashed, non-withdrawn) participants.
    uint256 private _participantCount;

    /// @dev Re-entrancy guard. Set to true while a state-mutating call is executing.
    bool private _locked;

    // ───────────────────────────────────────────────────────────── Modifier ─────

    /// @dev Reverts if the contract is already executing a guarded function.
    modifier nonReentrant() {
        require(!_locked, "ProofOfLiveness: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    // ─────────────────────────────────────────────────────────── Constructor ────

    /// @notice Deploy the contract with fixed protocol parameters.
    /// @param _requiredStake      Exact native-token amount participants must stake.
    /// @param _heartbeatInterval  Maximum seconds allowed between heartbeats before going inactive.
    /// @param _slashedFundsSink   Address that receives 90% of every slashed stake.
    /// @dev All parameters are immutable post-deployment. Use a governance proxy if upgradability
    ///      is desired.
    constructor(
        uint256 _requiredStake,
        uint256 _heartbeatInterval,
        address _slashedFundsSink
    ) {
        if (_requiredStake == 0) revert IncorrectStake(0, 1);
        if (_heartbeatInterval < 1 minutes) revert IncorrectStake(_heartbeatInterval, 60);
        if (_slashedFundsSink == address(0)) revert ZeroAddress();

        requiredStake = _requiredStake;
        heartbeatInterval = _heartbeatInterval;
        slashedFundsSink = _slashedFundsSink;
    }

    // ─────────────────────────────────────────────────────── Write Functions ────

    /// @inheritdoc IProofOfLiveness
    /// @dev Participants must send exactly `requiredStake`. Any deviation reverts.
    ///      Re-joining after a slash or withdrawal is allowed (stake is reset to 0 on those paths).
    function join() external payable nonReentrant {
        // Checks
        if (_participants[msg.sender].stakeAmount != 0) revert AlreadyJoined(msg.sender);
        if (msg.value != requiredStake) revert IncorrectStake(msg.value, requiredStake);

        // Effects
        _participants[msg.sender] = Participant({
            stakeAmount: msg.value,
            lastHeartbeat: block.timestamp
        });
        unchecked {
            ++_participantCount;
        }

        emit Joined(msg.sender, msg.value, block.timestamp);
    }

    /// @inheritdoc IProofOfLiveness
    /// @dev Heartbeat is rejected if the caller is already inactive (missed deadline).
    ///      Only the lastHeartbeat field is updated — stakeAmount remains unchanged.
    function heartbeat() external nonReentrant {
        // Checks
        if (!isActive(msg.sender)) revert NotActive(msg.sender);

        // Effects
        _participants[msg.sender].lastHeartbeat = block.timestamp;

        emit Heartbeat(msg.sender, block.timestamp);
    }

    /// @inheritdoc IProofOfLiveness
    /// @dev Implements CEI strictly:
    ///      1. Checks — user must be inactive and have stake.
    ///      2. Effects — stake zeroed, count decremented BEFORE any external call.
    ///      3. Interactions — ETH transfers happen last.
    function slash(address user) external nonReentrant {
        Participant storage participant = _participants[user];

        // Checks
        if (isActive(user)) revert NotSlashable(user);
        if (participant.stakeAmount == 0) revert NoStake(user);

        // Effects
        uint256 stake = participant.stakeAmount;
        uint256 slasherReward = stake / 10;
        uint256 sinkAmount = stake - slasherReward;

        participant.stakeAmount = 0;
        unchecked {
            --_participantCount;
        }

        emit Slashed(user, msg.sender, slasherReward, sinkAmount);

        // Interactions
        (bool successSlasher,) = payable(msg.sender).call{value: slasherReward}("");
        if (!successSlasher) revert TransferFailed(msg.sender, slasherReward);

        (bool successSink,) = payable(slashedFundsSink).call{value: sinkAmount}("");
        if (!successSink) revert TransferFailed(slashedFundsSink, sinkAmount);
    }

    /// @inheritdoc IProofOfLiveness
    /// @dev Only active participants (within heartbeat window) may withdraw.
    ///      Follows CEI — stake is cleared before the external ETH transfer.
    function withdraw() external nonReentrant {
        Participant storage participant = _participants[msg.sender];

        // Checks
        if (participant.stakeAmount == 0) revert NoStake(msg.sender);
        if (!isActive(msg.sender)) revert NotActive(msg.sender);

        // Effects
        uint256 amount = participant.stakeAmount;
        participant.stakeAmount = 0;
        participant.lastHeartbeat = 0;
        unchecked {
            --_participantCount;
        }

        emit Withdrawn(msg.sender, amount);

        // Interactions
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed(msg.sender, amount);
    }

    // ──────────────────────────────────────────────────────── View Functions ────

    /// @inheritdoc IProofOfLiveness
    /// @dev Returns false for non-participants (stakeAmount == 0 guard).
    function isActive(address user) public view returns (bool) {
        Participant storage p = _participants[user];
        if (p.stakeAmount == 0) return false;
        return block.timestamp <= p.lastHeartbeat + heartbeatInterval;
    }

    /// @inheritdoc IProofOfLiveness
    function getParticipant(address user) external view returns (Participant memory) {
        return _participants[user];
    }

    /// @inheritdoc IProofOfLiveness
    function participantCount() external view returns (uint256) {
        return _participantCount;
    }
}
