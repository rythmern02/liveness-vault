// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IProofOfLiveness {
    struct Participant {
        uint256 stakeAmount;
        uint256 lastHeartbeat;
    }

    error NotActive(address user);
    error AlreadyJoined(address user);
    error IncorrectStake(uint256 sent, uint256 required);
    error NotSlashable(address user);
    error NoStake(address user);

    event Joined(address indexed user, uint256 stakeAmount, uint256 timestamp);
    event Heartbeat(address indexed user, uint256 timestamp);
    event Slashed(
        address indexed user,
        address indexed slasher,
        uint256 slasherReward,
        uint256 sinkAmount
    );

    function join() external payable;

    function heartbeat() external;

    function slash(address user) external;

    function isActive(address user) external view returns (bool);

    function getParticipant(address user) external view returns (Participant memory);

    function requiredStake() external view returns (uint256);

    function heartbeatInterval() external view returns (uint256);

    function slashedFundsSink() external view returns (address);
}
