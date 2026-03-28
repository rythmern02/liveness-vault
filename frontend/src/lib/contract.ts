import { type Abi } from "viem";

export const CONTRACT_ADDRESS = (
  process.env.NEXT_PUBLIC_CONTRACT_ADDRESS ?? "0x0000000000000000000000000000000000000000"
) as `0x${string}`;

export const PROOF_OF_LIVENESS_ABI = [
  // Write
  { type: "function", name: "join", stateMutability: "payable", inputs: [], outputs: [] },
  { type: "function", name: "heartbeat", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "slash", stateMutability: "nonpayable", inputs: [{ name: "user", type: "address" }], outputs: [] },
  { type: "function", name: "withdraw", stateMutability: "nonpayable", inputs: [], outputs: [] },
  // Views
  {
    type: "function", name: "isActive", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function", name: "getParticipant", stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "tuple", components: [{ name: "stakeAmount", type: "uint256" }, { name: "lastHeartbeat", type: "uint256" }] }],
  },
  {
    type: "function", name: "participantCount", stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function", name: "requiredStake", stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function", name: "heartbeatInterval", stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function", name: "slashedFundsSink", stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  // Events
  {
    type: "event", name: "Joined",
    inputs: [{ name: "user", type: "address", indexed: true }, { name: "stakeAmount", type: "uint256", indexed: false }, { name: "timestamp", type: "uint256", indexed: false }],
  },
  {
    type: "event", name: "Heartbeat",
    inputs: [{ name: "user", type: "address", indexed: true }, { name: "timestamp", type: "uint256", indexed: false }],
  },
  {
    type: "event", name: "Slashed",
    inputs: [{ name: "user", type: "address", indexed: true }, { name: "slasher", type: "address", indexed: true }, { name: "slasherReward", type: "uint256", indexed: false }, { name: "sinkAmount", type: "uint256", indexed: false }],
  },
  {
    type: "event", name: "Withdrawn",
    inputs: [{ name: "user", type: "address", indexed: true }, { name: "amount", type: "uint256", indexed: false }],
  },
] as const satisfies Abi;
