// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IProofOfLiveness
/// @notice Interface for the Proof of Liveness subscription state machine.
/// @dev Participants stake native tokens and must call heartbeat() periodically to remain active.
///      Inactive participants can be slashed by any external caller for a bounty reward.
interface IProofOfLiveness {
    // ────────────────────────────────────────────────────────────── Structs ─────

    /// @notice Snapshot of a participant's on-chain state.
    /// @param stakeAmount  The amount of native token locked by this participant (0 if not joined or slashed).
    /// @param lastHeartbeat  Unix timestamp of the participant's most recent heartbeat (or join time).
    struct Participant {
        uint256 stakeAmount;
        uint256 lastHeartbeat;
    }

    // ────────────────────────────────────────────────────────────── Errors ──────

    /// @notice Emitted when an address that has already joined attempts to join again.
    error AlreadyJoined(address user);

    /// @notice Emitted when the sent value does not exactly equal the required stake.
    /// @param sent      The amount actually sent.
    /// @param required  The amount that was expected.
    error IncorrectStake(uint256 sent, uint256 required);

    /// @notice Emitted when an operation requires the caller to be active but they are not.
    error NotActive(address user);

    /// @notice Emitted when slash() is called on a user who is still within their heartbeat window.
    error NotSlashable(address user);

    /// @notice Emitted when slash() or withdraw() is called for a user with no stake.
    error NoStake(address user);

    /// @notice Emitted when a native-token transfer fails.
    error TransferFailed(address to, uint256 amount);

    /// @notice Emitted when the zero address is used where it must not be.
    error ZeroAddress();

    // ────────────────────────────────────────────────────────────── Events ──────

    /// @notice Emitted when a participant successfully joins.
    /// @param user        The address of the new participant.
    /// @param stakeAmount The amount staked (always == requiredStake).
    /// @param timestamp   The block timestamp at join time.
    event Joined(address indexed user, uint256 stakeAmount, uint256 timestamp);

    /// @notice Emitted when a participant submits a successful heartbeat.
    /// @param user      The participant's address.
    /// @param timestamp The block timestamp of the heartbeat.
    event Heartbeat(address indexed user, uint256 timestamp);

    /// @notice Emitted when an inactive participant's stake is slashed.
    /// @param user          The slashed participant.
    /// @param slasher       The address that called slash() and received the bounty.
    /// @param slasherReward The portion of stake sent to the slasher (10%).
    /// @param sinkAmount    The portion sent to the slashedFundsSink (90%).
    event Slashed(
        address indexed user,
        address indexed slasher,
        uint256 slasherReward,
        uint256 sinkAmount
    );

    /// @notice Emitted when an active participant voluntarily exits and retrieves their stake.
    /// @param user   The withdrawing participant.
    /// @param amount The stake returned to them.
    event Withdrawn(address indexed user, uint256 amount);

    // ─────────────────────────────────────────────────────── Write Functions ────

    /// @notice Join the protocol by staking exactly `requiredStake` native tokens.
    function join() external payable;

    /// @notice Prove liveness by updating the caller's last-heartbeat timestamp.
    /// @dev Reverts if the caller is not currently active.
    function heartbeat() external;

    /// @notice Slash an inactive participant and claim a 10% bounty.
    /// @param user The address of the participant to slash.
    function slash(address user) external;

    /// @notice Voluntarily exit the protocol and reclaim the full stake.
    /// @dev Only callable while the participant is still active (within heartbeat window).
    function withdraw() external;

    // ──────────────────────────────────────────────────────── View Functions ────

    /// @notice Returns true if the participant is currently within their heartbeat window.
    /// @param user The address to check.
    function isActive(address user) external view returns (bool);

    /// @notice Returns the full on-chain data for a participant.
    /// @param user The address to query.
    function getParticipant(address user) external view returns (Participant memory);

    /// @notice Returns the total number of participants who have not yet been slashed or withdrawn.
    function participantCount() external view returns (uint256);

    /// @notice The exact amount of native token required to join.
    function requiredStake() external view returns (uint256);

    /// @notice The maximum number of seconds allowed between consecutive heartbeats.
    function heartbeatInterval() external view returns (uint256);

    /// @notice The address that receives the 90% sink portion of a slashed stake.
    function slashedFundsSink() external view returns (address);
}
