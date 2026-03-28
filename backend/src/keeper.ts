import "dotenv/config";
import http from "node:http";
import {
  ethers,
  JsonRpcProvider,
  Wallet,
  Contract,
  EventLog,
} from "ethers";
import { PROOF_OF_LIVENESS_ABI } from "./abi.js";

// ─────────────────────────────────────────────────────────────────── Config ──

const REQUIRED_ENV = ["RPC_URL", "KEEPER_PRIVATE_KEY", "CONTRACT_ADDRESS"] as const;

for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(JSON.stringify({ level: "FATAL", msg: `Missing required env var: ${key}` }));
    process.exit(1);
  }
}

const RPC_URL = process.env["RPC_URL"]!;
const PRIVATE_KEY = process.env["KEEPER_PRIVATE_KEY"]!;
const CONTRACT_ADDRESS = process.env["CONTRACT_ADDRESS"]!;
const POLL_INTERVAL_MS = Number(process.env["POLL_INTERVAL_MS"] ?? "30000");
const GAS_LIMIT = BigInt(process.env["GAS_LIMIT"] ?? "200000");
const SCAN_FROM_BLOCK = Number(process.env["SCAN_FROM_BLOCK"] ?? "0");
const HEALTH_PORT = Number(process.env["HEALTH_PORT"] ?? "3001");
const MAX_RETRIES = Number(process.env["MAX_RETRIES"] ?? "5");
const RETRY_BASE_MS = Number(process.env["RETRY_BASE_MS"] ?? "1000");

// ────────────────────────────────────────────────────────────────── Logging ──

type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR" | "FATAL";

function log(level: LogLevel, msg: string, data?: Record<string, unknown>): void {
  const entry: Record<string, unknown> = {
    ts: new Date().toISOString(),
    level,
    msg,
  };
  if (data) Object.assign(entry, data);
  const output = JSON.stringify(entry);
  if (level === "ERROR" || level === "FATAL" || level === "WARN") {
    console.error(output);
  } else {
    console.log(output);
  }
}

// ──────────────────────────────────────────────────────── Retry with Backoff ─

async function withRetry<T>(
  fn: () => Promise<T>,
  label: string,
  maxRetries = MAX_RETRIES
): Promise<T> {
  let lastErr: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      if (attempt === maxRetries) break;
      const delay = RETRY_BASE_MS * 2 ** attempt + Math.random() * 200;
      log("WARN", `${label} failed (attempt ${attempt + 1}/${maxRetries + 1}), retrying in ${Math.round(delay)}ms`, {
        error: err instanceof Error ? err.message : String(err),
      });
      await new Promise((res) => setTimeout(res, delay));
    }
  }
  log("ERROR", `${label} failed after ${maxRetries + 1} attempts`, {
    error: lastErr instanceof Error ? lastErr.message : String(lastErr),
  });
  throw lastErr;
}

// ──────────────────────────────────────────────────────── Health Check HTTP ──

interface HealthStatus {
  status: "ok" | "degraded";
  uptime: number;
  participantsTracked: number;
  lastCycleAt: string | null;
  network: { chainId: string; rpcUrl: string };
  contract: string;
}

function startHealthServer(getStatus: () => HealthStatus): http.Server {
  const server = http.createServer((req, res) => {
    if (req.url === "/health" && req.method === "GET") {
      const status = getStatus();
      res.writeHead(status.status === "ok" ? 200 : 503, { "Content-Type": "application/json" });
      res.end(JSON.stringify(status, null, 2));
    } else {
      res.writeHead(404);
      res.end(JSON.stringify({ error: "Not Found" }));
    }
  });

  server.listen(HEALTH_PORT, () => {
    log("INFO", `Health server listening`, { port: HEALTH_PORT, path: "/health" });
  });

  return server;
}

// ─────────────────────────────────────────────────────── Participant Helpers ─

async function getHistoricalParticipants(
  contract: Contract,
  provider: JsonRpcProvider,
  fromBlock: number
): Promise<Set<string>> {
  const participants = new Set<string>();

  return withRetry(async () => {
    const currentBlock = await provider.getBlockNumber();
    log("INFO", `Scanning Joined events`, { fromBlock, toBlock: currentBlock });

    const joinFilter = contract.filters["Joined"]();
    
    // RSK RPCs (and Infura/Alchemy) have a 2000 block range limit per eth_getLogs call.
    // We must paginate the request in 2000-block chunks.
    const CHUNK_SIZE = 2000;
    for (let start = fromBlock; start <= currentBlock; start += CHUNK_SIZE) {
      const end = Math.min(start + CHUNK_SIZE - 1, currentBlock);
      const joinEvents = await contract.queryFilter(joinFilter, start, end);

      for (const event of joinEvents) {
        const e = event as EventLog;
        const user = e.args?.[0] as string | undefined;
        if (user) participants.add(user.toLowerCase());
      }
    }

    log("INFO", `Historical scan complete`, { participantsFound: participants.size });
    return participants;
  }, "getHistoricalParticipants");
}

interface ParticipantState {
  stakeAmount: bigint;
  lastHeartbeat: bigint;
}

async function fetchParticipantState(
  contract: Contract,
  user: string
): Promise<{ isActive: boolean; state: ParticipantState }> {
  return withRetry(async () => {
    const [isActive, state] = await Promise.all([
      contract["isActive"](user) as Promise<boolean>,
      contract["getParticipant"](user) as Promise<ParticipantState>,
    ]);
    return { isActive, state };
  }, `fetchParticipantState(${user})`);
}

// ─────────────────────────────────────────────────────────────── Main Cycle ──

async function checkAndSlash(
  contract: Contract,
  participants: Set<string>,
  heartbeatInterval: bigint
): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  log("INFO", `Starting slash-check cycle`, { participants: participants.size, timestamp: now });

  // Build a list of (user, staleness) so we prioritize the most overdue first
  const slashCandidates: Array<{ user: string; staleness: number; reward: bigint }> = [];

  for (const user of participants) {
    try {
      const { isActive, state } = await fetchParticipantState(contract, user);

      if (state.stakeAmount === 0n) {
        log("INFO", `Removing zero-stake participant`, { user });
        participants.delete(user);
        continue;
      }

      if (!isActive) {
        const staleness = now - Number(state.lastHeartbeat);
        slashCandidates.push({ user, staleness, reward: state.stakeAmount / 10n });
      } else {
        const deadline = Number(state.lastHeartbeat) + Number(heartbeatInterval);
        const remaining = deadline - now;
        log("DEBUG", `Participant active`, { user, remainingSeconds: remaining });
      }
    } catch (err) {
      log("ERROR", `Failed to check participant`, {
        user,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  if (slashCandidates.length > 0) {
    // Sort by staleness descending — slash the longest-overdue first for maximum bounty priority
    slashCandidates.sort((a, b) => b.staleness - a.staleness);
    log("INFO", `Slash candidates found`, { count: slashCandidates.length });

    for (const { user, staleness, reward } of slashCandidates) {
      log("INFO", `Slashing participant`, {
        user,
        staleSince: `${staleness}s`,
        expectedReward: ethers.formatEther(reward) + " RBTC",
      });

      try {
        await withRetry(async () => {
          const tx = await (contract["slash"] as (
            user: string,
            opts: { gasLimit: bigint }
          ) => Promise<{ hash: string; wait: () => Promise<unknown> }>)(user, { gasLimit: GAS_LIMIT });

          log("INFO", `Slash tx broadcast`, { user, txHash: tx.hash });
          await tx.wait();
          log("INFO", `Slash confirmed`, { user, reward: ethers.formatEther(reward) + " RBTC" });
        }, `slash(${user})`, 2); // max 2 retries for on-chain txs (gas issues may be permanent)

        participants.delete(user);
      } catch (err) {
        log("ERROR", `Slash failed`, {
          user,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  } else {
    log("INFO", `No slashable participants found`);
  }
}

// ───────────────────────────────────────────────────────────── Manual Polling ─

async function scanRecentEvents(
  contract: Contract,
  provider: JsonRpcProvider,
  participants: Set<string>,
  fromBlock: number,
  toBlock: number
): Promise<void> {
  if (fromBlock > toBlock) return;
  
  await withRetry(async () => {
    // Note: If fromBlock to toBlock is > 2000, we'd need to paginate here too, 
    // but the poll interval is 30s so the diff is at most 1-2 blocks.
    const joins = await contract.queryFilter(contract.filters["Joined"](), fromBlock, toBlock);
    const slashes = await contract.queryFilter(contract.filters["Slashed"](), fromBlock, toBlock);
    const withdraws = await contract.queryFilter(contract.filters["Withdrawn"](), fromBlock, toBlock);

    for (const e of joins) {
      const u = (e as EventLog).args?.[0] as string | undefined;
      if (u && !participants.has(u.toLowerCase())) {
        participants.add(u.toLowerCase());
        log("INFO", `New participant tracked (via poll)`, { user: u.toLowerCase() });
      }
    }

    for (const e of slashes) {
      const u = (e as EventLog).args?.[0] as string | undefined;
      if (u) {
        participants.delete(u.toLowerCase());
        log("INFO", `Participant removed / slashed (via poll)`, { user: u.toLowerCase() });
      }
    }

    for (const e of withdraws) {
      const u = (e as EventLog).args?.[0] as string | undefined;
      if (u) {
        participants.delete(u.toLowerCase());
        log("INFO", `Participant removed / withdrawn (via poll)`, { user: u.toLowerCase() });
      }
    }
  }, `scanRecentEvents(${fromBlock} - ${toBlock})`);
}

// ─────────────────────────────────────────────────────────────────────── Main

async function main(): Promise<void> {
  const startedAt = Date.now();
  let lastCycleAt: Date | null = null;
  let participants = new Set<string>();
  let chainId = "unknown";

  log("INFO", `Keeper bot starting`, {
    rpcUrl: RPC_URL,
    contractAddress: CONTRACT_ADDRESS,
    pollIntervalMs: POLL_INTERVAL_MS,
    gasLimit: GAS_LIMIT.toString(),
    healthPort: HEALTH_PORT,
  });

  // ── Health server (starts immediately so k8s/docker can probe it) ──────────
  const healthServer = startHealthServer(() => ({
    status: "ok",
    uptime: Math.floor((Date.now() - startedAt) / 1000),
    participantsTracked: participants.size,
    lastCycleAt: lastCycleAt?.toISOString() ?? null,
    network: { chainId, rpcUrl: RPC_URL },
    contract: CONTRACT_ADDRESS,
  }));

  // ── Provider & wallet ────────────────────────────────────────────────────
  const provider = new JsonRpcProvider(RPC_URL);
  const wallet = new Wallet(PRIVATE_KEY, provider);
  const keeperAddr = await wallet.getAddress();

  const network = await withRetry(() => provider.getNetwork(), "getNetwork");
  chainId = network.chainId.toString();

  const balance = await provider.getBalance(keeperAddr);
  log("INFO", `Keeper wallet ready`, {
    address: keeperAddr,
    balance: ethers.formatEther(balance) + " RBTC",
    chainId,
  });

  if (balance === 0n) {
    log("WARN", `Keeper wallet has zero balance — slash transactions will fail`);
  }

  // ── Contract ─────────────────────────────────────────────────────────────
  const contract = new Contract(CONTRACT_ADDRESS, PROOF_OF_LIVENESS_ABI, wallet);

  const [requiredStake, heartbeatInterval, slashedFundsSink] = await withRetry(
    () => Promise.all([
      contract["requiredStake"]() as Promise<bigint>,
      contract["heartbeatInterval"]() as Promise<bigint>,
      contract["slashedFundsSink"]() as Promise<string>,
    ]),
    "fetchContractConfig"
  );

  log("INFO", `Contract config loaded`, {
    requiredStake: ethers.formatEther(requiredStake) + " RBTC",
    heartbeatInterval: heartbeatInterval.toString() + "s",
    slashedFundsSink,
  });

  // ── Backfill historical participants ────────────────────────────────────
  participants = await getHistoricalParticipants(contract, provider, SCAN_FROM_BLOCK);

  // ── Manual Polling Setup ─────────────────────────────────────────────────
  // Note: We skip backfilling historical participants because public RSK 
  // testnet RPCs lack wide `eth_getLogs` range support (unless using chunks),
  // but we already got them via `getHistoricalParticipants`.
  // We use manual polling (`scanRecentEvents`) instead of `contract.on` 
  // because RSK RPC blocks `eth_newFilter`.
  let lastCheckedBlock = await provider.getBlockNumber();

  // ── Poll loop ─────────────────────────────────────────────────────────────
  const runCycle = async (): Promise<void> => {
    try {
      const currentBlock = await provider.getBlockNumber();
      if (currentBlock > lastCheckedBlock) {
        await scanRecentEvents(contract, provider, participants, lastCheckedBlock + 1, currentBlock);
        lastCheckedBlock = currentBlock;
      }

      await checkAndSlash(contract, participants, heartbeatInterval);
      lastCycleAt = new Date();
    } catch (err) {
      log("ERROR", `Unexpected error in poll cycle`, {
        error: err instanceof Error ? err.message : String(err),
      });
    }
  };

  await runCycle();
  log("INFO", `Poll loop started`, { intervalSeconds: POLL_INTERVAL_MS / 1000 });
  const pollTimer = setInterval(runCycle, POLL_INTERVAL_MS);

  // ── Graceful shutdown ────────────────────────────────────────────────────
  const shutdown = async (signal: string): Promise<void> => {
    log("INFO", `Received ${signal} — shutting down gracefully`);
    clearInterval(pollTimer);
    await contract.removeAllListeners();
    healthServer.close(() => {
      log("INFO", `Health server closed. Goodbye.`);
      process.exit(0);
    });
  };

  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

main().catch((err) => {
  log("FATAL", `Unhandled startup error`, {
    error: err instanceof Error ? err.message : String(err),
  });
  process.exit(1);
});
