"use client";

import { ConnectButton } from "@/components/ConnectButton";
import { LivenessCard }  from "@/components/LivenessCard";
import { StatsBar }      from "@/components/StatsBar";
import { ActivityFeed }  from "@/components/ActivityFeed";

export default function Home() {
  return (
    <div className="page-wrapper">
      {/* ── Header ─────────────────────────────────────────────────────────── */}
      <header className="header">
        <a href="/" className="logo">
          <div className="logo-icon">⚡</div>
          Liveness Vault
        </a>
        <ConnectButton />
      </header>

      {/* ── Main content ───────────────────────────────────────────────────── */}
      <main className="main">
        {/* Hero */}
        <section className="hero">
          <p className="hero-tag">⛓ Rootstock · Proof of Liveness</p>
          <h1>Stay Active.<br />Or Get Slashed.</h1>
          <p>
            Stake RBTC to join the protocol. Send periodic heartbeats to prove your
            liveness. Miss the deadline? Anyone can slash your stake and claim a 10% bounty.
          </p>
        </section>

        {/* Stats */}
        <StatsBar />

        {/* Main grid: liveness card + activity */}
        <div className="dashboard-grid">
          <LivenessCard />
          <ActivityFeed />
        </div>
      </main>

      {/* ── Footer ─────────────────────────────────────────────────────────── */}
      <footer className="footer">
        Built on{" "}
        <a href="https://rootstock.io" target="_blank" rel="noopener noreferrer">
          Rootstock (RSK)
        </a>{" "}
        · Contracts verified on{" "}
        <a href="https://explorer.testnet.rootstock.io" target="_blank" rel="noopener noreferrer">
          RSK Explorer
        </a>{" "}
        · MIT License
      </footer>
    </div>
  );
}
