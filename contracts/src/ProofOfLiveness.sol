// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IProofOfLiveness} from "./IProofOfLiveness.sol";

/// @title ProofOfLiveness
/// @notice A subscription state machine where participants must periodically send
///         a heartbeat transaction to prove liveness. Inactive participants can
///         be slashed by anyone, who receives 10% of the stake as a reward.

contract ProofOfLiveness is IProofOfLiveness {
    uint256 public immutable requiredStake;
    uint256 public immutable heartbeatInterval;
    address public immutable slashedFundsSink;

    mapping(address => Participant) private _participants;

    constructor(
        uint256 _requiredStake,
        uint256 _heartbeatInterval,
        address _slashedFundsSink
    ) {
        require(_requiredStake > 0, "ProofOfLiveness: stake must be > 0");
        require(_heartbeatInterval > 0, "ProofOfLiveness: interval must be > 0");
        require(_slashedFundsSink != address(0), "ProofOfLiveness: sink cannot be zero address");
        requiredStake = _requiredStake;
        heartbeatInterval = _heartbeatInterval;
        slashedFundsSink = _slashedFundsSink;
    }

    /// @notice Join the liveness protocol by staking the exact required amount.
    function join() external payable {
        if (_participants[msg.sender].stakeAmount > 0) {
            revert AlreadyJoined(msg.sender);
        }
        if (msg.value != requiredStake) {
            revert IncorrectStake(msg.value, requiredStake);
        }

        _participants[msg.sender] = Participant({
            stakeAmount: msg.value,
            lastHeartbeat: block.timestamp
        });

        emit Joined(msg.sender, msg.value, block.timestamp);
    }

    /// @notice Submit a heartbeat to prove liveness. Reverts if caller is not active.
    function heartbeat() external {
        if (!isActive(msg.sender)) {
            revert NotActive(msg.sender);
        }

        _participants[msg.sender].lastHeartbeat = block.timestamp;

        emit Heartbeat(msg.sender, block.timestamp);
    }

    /// @notice Slash an inactive participant. Caller receives 10%, sink receives 90%.
    ///         Follows strict Checks-Effects-Interactions (CEI) pattern.
    function slash(address user) external {
        Participant storage participant = _participants[user];

        if (isActive(user)) {
            revert NotSlashable(user);
        }
        if (participant.stakeAmount == 0) {
            revert NoStake(user);
        }

        uint256 stake = participant.stakeAmount;
        uint256 slasherReward = stake / 10;
        uint256 sinkAmount = stake - slasherReward;

        participant.stakeAmount = 0;

        emit Slashed(user, msg.sender, slasherReward, sinkAmount);

        (bool successSlasher,) = payable(msg.sender).call{value: slasherReward}("");
        require(successSlasher, "ProofOfLiveness: slasher transfer failed");

        (bool successSink,) = payable(slashedFundsSink).call{value: sinkAmount}("");
        require(successSink, "ProofOfLiveness: sink transfer failed");
    }

    /// @notice Returns true if the user's last heartbeat is within the interval.
    function isActive(address user) public view returns (bool) {
        Participant storage p = _participants[user];
        if (p.stakeAmount == 0) return false;
        return block.timestamp <= p.lastHeartbeat + heartbeatInterval;
    }

    /// @notice Returns a participant's full data.
    function getParticipant(address user) external view returns (Participant memory) {
        return _participants[user];
    }
}
