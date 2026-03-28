"use client";

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatEther } from "viem";
import { CONTRACT_ADDRESS, PROOF_OF_LIVENESS_ABI } from "@/lib/contract";
import { StatusBadge } from "./StatusBadge";
import { CountdownTimer } from "./CountdownTimer";

export function LivenessCard() {
  const { address, isConnected } = useAccount();

  // ── Read state ──────────────────────────────────────────────────────────────
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

  const { data: participant, refetch: refetchParticipant } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: PROOF_OF_LIVENESS_ABI,
    functionName: "getParticipant",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: isActive, refetch: refetchActive } = useReadContract({
    address: CONTRACT_ADDRESS,
    abi: PROOF_OF_LIVENESS_ABI,
    functionName: "isActive",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const refetchAll = () => { refetchParticipant(); refetchActive(); };

  // ── Write actions ───────────────────────────────────────────────────────────
  const { writeContract, data: txHash, isPending, reset } = useWriteContract();

  const { isLoading: isConfirming } = useWaitForTransactionReceipt({
    hash: txHash,
    query: {
      enabled: !!txHash,
    },
    onReplaced: () => { refetchAll(); reset(); },
  });

  // Re-fetch after confirmation
  const isBusy = isPending || isConfirming;

  // Track when tx completes
  const { isSuccess: txSuccess } = useWaitForTransactionReceipt({ hash: txHash });
  if (txSuccess) { refetchAll(); }

  // ── Derived state ───────────────────────────────────────────────────────────
  const hasStake    = participant && participant.stakeAmount > 0n;
  const deadline    = hasStake && heartbeatInterval
    ? participant.lastHeartbeat + heartbeatInterval
    : null;

  type Status = "active" | "inactive" | "not-joined";
  let status: Status = "not-joined";
  if (hasStake) status = isActive ? "active" : "inactive";

  // ── Handlers ────────────────────────────────────────────────────────────────
  const handleJoin = () => {
    if (!requiredStake) return;
    writeContract({
      address: CONTRACT_ADDRESS,
      abi: PROOF_OF_LIVENESS_ABI,
      functionName: "join",
      value: requiredStake,
    });
  };

  const handleHeartbeat = () => {
    writeContract({ address: CONTRACT_ADDRESS, abi: PROOF_OF_LIVENESS_ABI, functionName: "heartbeat" });
  };

  const handleWithdraw = () => {
    writeContract({ address: CONTRACT_ADDRESS, abi: PROOF_OF_LIVENESS_ABI, functionName: "withdraw" });
  };

  // ── Render ──────────────────────────────────────────────────────────────────
  if (!isConnected) {
    return (
      <div className="card card-idle">
        <p className="card-idle-msg">Connect your wallet to participate in the Liveness Protocol.</p>
      </div>
    );
  }

  return (
    <div id="liveness-card" className="card">
      {/* Header */}
      <div className="card-header">
        <h2 className="card-title">Your Liveness Status</h2>
        <StatusBadge status={status} />
      </div>

      {/* Countdown */}
      {hasStake && (
        <CountdownTimer
          deadline={deadline ? BigInt(deadline) : null}
          interval={heartbeatInterval ?? null}
        />
      )}

      {/* Stake info */}
      {requiredStake && (
        <div className="stake-info">
          <span className="stake-label">Required Stake</span>
          <span className="stake-value">{formatEther(requiredStake)} RBTC</span>
        </div>
      )}

      {/* Tx feedback */}
      {txHash && (
        <div className="tx-banner">
          <span className="tx-label">{isConfirming ? "⏳ Confirming…" : "✅ Confirmed!"}</span>
          <a
            href={`https://explorer.testnet.rootstock.io/tx/${txHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="tx-link"
          >
            View tx ↗
          </a>
        </div>
      )}

      {/* Actions */}
      <div className="card-actions">
        {status === "not-joined" && (
          <button
            id="join-btn"
            onClick={handleJoin}
            disabled={isBusy || !requiredStake}
            className="action-btn btn-primary"
          >
            {isBusy ? <><span className="spinner" /> Processing…</> : `Join — Stake ${requiredStake ? formatEther(requiredStake) : "?"} RBTC`}
          </button>
        )}

        {status === "active" && (
          <>
            <button
              id="heartbeat-btn"
              onClick={handleHeartbeat}
              disabled={isBusy}
              className="action-btn btn-primary"
            >
              {isBusy ? <><span className="spinner" /> Processing…</> : "💓 Send Heartbeat"}
            </button>
            <button
              id="withdraw-btn"
              onClick={handleWithdraw}
              disabled={isBusy}
              className="action-btn btn-ghost"
            >
              Withdraw Stake
            </button>
          </>
        )}

        {status === "inactive" && (
          <div className="inactive-msg">
            ⚠️ Your heartbeat expired. You can be slashed by anyone. Rejoin after being slashed.
          </div>
        )}
      </div>
    </div>
  );
}
