"use client";

import { useReadContract } from "wagmi";
import { formatEther } from "viem";
import { useEffect, useState } from "react";
import { createPublicClient, http, parseAbiItem } from "viem";
import { CONTRACT_ADDRESS, PROOF_OF_LIVENESS_ABI } from "@/lib/contract";
import { rootstockTestnet } from "@/lib/chains";

type ActivityType = "joined" | "heartbeat" | "slashed" | "withdrawn";

interface Activity {
  id: string;
  type: ActivityType;
  user: string;
  blockNumber: bigint;
  extra?: string;
}

const TYPE_CONFIG: Record<ActivityType, { label: string; icon: string; className: string }> = {
  joined:    { label: "Joined",       icon: "🔗", className: "feed-joined" },
  heartbeat: { label: "Heartbeat",    icon: "💓", className: "feed-heartbeat" },
  slashed:   { label: "Slashed",      icon: "⚡", className: "feed-slashed" },
  withdrawn: { label: "Withdrew",     icon: "↩️", className: "feed-withdrawn" },
};

export function ActivityFeed() {
  const [activities, setActivities] = useState<Activity[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const client = createPublicClient({
      chain: rootstockTestnet,
      transport: http(),
    });

    async function fetchEvents() {
      try {
        const currentBlock = await client.getBlockNumber();
        const fromBlock    = currentBlock > 500n ? currentBlock - 500n : 0n;

        const [joins, beats, slashes, withdraws] = await Promise.all([
          client.getLogs({ address: CONTRACT_ADDRESS, event: parseAbiItem("event Joined(address indexed user, uint256 stakeAmount, uint256 timestamp)"), fromBlock }),
          client.getLogs({ address: CONTRACT_ADDRESS, event: parseAbiItem("event Heartbeat(address indexed user, uint256 timestamp)"), fromBlock }),
          client.getLogs({ address: CONTRACT_ADDRESS, event: parseAbiItem("event Slashed(address indexed user, address indexed slasher, uint256 slasherReward, uint256 sinkAmount)"), fromBlock }),
          client.getLogs({ address: CONTRACT_ADDRESS, event: parseAbiItem("event Withdrawn(address indexed user, uint256 amount)"), fromBlock }),
        ]);

        const combined: Activity[] = [
          ...joins.map(e => ({
            id: `${e.blockNumber}-${e.logIndex}-join`,
            type: "joined" as const,
            user: e.args.user!,
            blockNumber: e.blockNumber ?? 0n,
            extra: `staked ${formatEther(e.args.stakeAmount ?? 0n)} RBTC`,
          })),
          ...beats.map(e => ({
            id: `${e.blockNumber}-${e.logIndex}-hb`,
            type: "heartbeat" as const,
            user: e.args.user!,
            blockNumber: e.blockNumber ?? 0n,
          })),
          ...slashes.map(e => ({
            id: `${e.blockNumber}-${e.logIndex}-slash`,
            type: "slashed" as const,
            user: e.args.user!,
            blockNumber: e.blockNumber ?? 0n,
            extra: `bounty ${formatEther(e.args.slasherReward ?? 0n)} RBTC`,
          })),
          ...withdraws.map(e => ({
            id: `${e.blockNumber}-${e.logIndex}-wd`,
            type: "withdrawn" as const,
            user: e.args.user!,
            blockNumber: e.blockNumber ?? 0n,
            extra: `returned ${formatEther(e.args.amount ?? 0n)} RBTC`,
          })),
        ].sort((a, b) => Number(b.blockNumber - a.blockNumber)).slice(0, 20);

        setActivities(combined);
      } catch {
        // Silently fail if no contract is deployed yet
      } finally {
        setLoading(false);
      }
    }

    fetchEvents();
    const id = setInterval(fetchEvents, 30_000);
    return () => clearInterval(id);
  }, []);

  return (
    <div id="activity-feed" className="feed-container">
      <h3 className="feed-title">Recent Activity</h3>
      {loading ? (
        <div className="feed-loading">
          <span className="spinner" /> Loading events…
        </div>
      ) : activities.length === 0 ? (
        <div className="feed-empty">No activity yet. Be the first to join!</div>
      ) : (
        <ul className="feed-list">
          {activities.map((a) => {
            const cfg = TYPE_CONFIG[a.type];
            return (
              <li key={a.id} className={`feed-item ${cfg.className}`}>
                <span className="feed-icon">{cfg.icon}</span>
                <div className="feed-content">
                  <span className="feed-event">{cfg.label}</span>
                  <span className="feed-user">
                    {a.user.slice(0, 6)}…{a.user.slice(-4)}
                  </span>
                  {a.extra && <span className="feed-extra">{a.extra}</span>}
                </div>
                <span className="feed-block">#{a.blockNumber.toString()}</span>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
