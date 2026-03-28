export const PROOF_OF_LIVENESS_ABI = [
  // Write
  "function join() external payable",
  "function heartbeat() external",
  "function slash(address user) external",
  "function withdraw() external",
  // Views
  "function isActive(address user) external view returns (bool)",
  "function getParticipant(address user) external view returns (tuple(uint256 stakeAmount, uint256 lastHeartbeat))",
  "function participantCount() external view returns (uint256)",
  "function requiredStake() external view returns (uint256)",
  "function heartbeatInterval() external view returns (uint256)",
  "function slashedFundsSink() external view returns (address)",
  // Events
  "event Joined(address indexed user, uint256 stakeAmount, uint256 timestamp)",
  "event Heartbeat(address indexed user, uint256 timestamp)",
  "event Slashed(address indexed user, address indexed slasher, uint256 slasherReward, uint256 sinkAmount)",
  "event Withdrawn(address indexed user, uint256 amount)",
  // Custom Errors
  "error NotActive(address user)",
  "error AlreadyJoined(address user)",
  "error IncorrectStake(uint256 sent, uint256 required)",
  "error NotSlashable(address user)",
  "error NoStake(address user)",
  "error TransferFailed(address to, uint256 amount)",
  "error ZeroAddress()",
] as const;
