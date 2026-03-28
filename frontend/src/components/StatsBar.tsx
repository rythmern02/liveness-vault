"use client";

import { useReadContract } from "wagmi";
import { formatEther } from "viem";
import { CONTRACT_ADDRESS, PROOF_OF_LIVENESS_ABI } from "@/lib/contract";

export function StatsBar() {
  const { data: participantCount } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: PROOF_OF_LIVENESS_ABI,
    functionName: "participantCount",
    query: { refetchInterval: 10_000 },
  });

  const { data: requiredStake } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: PROOF_OF_LIVENESS_ABI,
    functionName: "requiredStake",
  });

  const { data: heartbeatInterval } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: PROOF_OF_LIVENESS_ABI,
    functionName: "heartbeatInterval",
  });

  const totalStaked = participantCount !== undefined && requiredStake !== undefined
    ? participantCount * requiredStake
    : null;

  const intervalDays = heartbeatInterval
    ? (Number(heartbeatInterval) / 86400).toFixed(1)
    : null;

  return (
    <div id="stats-bar" className="stats-bar">
      <Stat label="Active Participants" value={participantCount?.toString() ?? "—"} />
      <Stat
        label="Total Staked"
        value={totalStaked !== null ? `${formatEther(totalStaked)} RBTC` : "—"}
      />
      <Stat
        label="Heartbeat Interval"
        value={intervalDays !== null ? `${intervalDays}d` : "—"}
      />
      <Stat
        label="Slash Bounty"
        value="10%"
        sublabel="of inactive stake"
      />
    </div>
  );
}

function Stat({ label, value, sublabel }: { label: string; value: string; sublabel?: string }) {
  return (
    <div className="stat-item">
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
      {sublabel && <div className="stat-sublabel">{sublabel}</div>}
    </div>
  );
}
