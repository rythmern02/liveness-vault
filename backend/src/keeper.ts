import "dotenv/config";
import {
  ethers,
  JsonRpcProvider,
  Wallet,
  Contract,
  EventLog,
  Log,
} from "ethers";
import { PROOF_OF_LIVENESS_ABI } from "./abi.js";

const REQUIRED_ENV = [
  "RPC_URL",
  "KEEPER_PRIVATE_KEY",
  "CONTRACT_ADDRESS",
] as const;

for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(`[keeper] Missing required env var: ${key}`);
    process.exit(1);
  }
}

const RPC_URL = process.env["RPC_URL"]!;
const PRIVATE_KEY = process.env["KEEPER_PRIVATE_KEY"]!;
const CONTRACT_ADDRESS = process.env["CONTRACT_ADDRESS"]!;
const POLL_INTERVAL_MS = Number(process.env["POLL_INTERVAL_MS"] ?? "30000");
const GAS_LIMIT = BigInt(process.env["GAS_LIMIT"] ?? "200000");
const SCAN_FROM_BLOCK = Number(process.env["SCAN_FROM_BLOCK"] ?? "0");

const log = (msg: string, data?: unknown) => {
  const ts = new Date().toISOString();
  if (data !== undefined) {
    console.log(`[${ts}] [keeper] ${msg}`, JSON.stringify(data, null, 2));
  } else {
    console.log(`[${ts}] [keeper] ${msg}`);
  }
};

const logError = (msg: string, err: unknown) => {
  const ts = new Date().toISOString();
  const errMsg = err instanceof Error ? err.message : String(err);
  console.error(`[${ts}] [keeper] ERROR ${msg}: ${errMsg}`);
};

async function getActiveParticipants(
  contract: Contract,
  provider: JsonRpcProvider,
  fromBlock: number
): Promise<Set<string>> {
  const participants = new Set<string>();

  try {
    const currentBlock = await provider.getBlockNumber();
    log(`Scanning Join events from block ${fromBlock} to ${currentBlock}`);

    const joinFilter = contract.filters["Joined"]();
    const joinEvents = await contract.queryFilter(joinFilter, fromBlock, currentBlock);

    for (const event of joinEvents) {
      const e = event as EventLog;
      const user = e.args?.[0] as string | undefined;
      if (user) {
        participants.add(user.toLowerCase());
      }
    }

    log(`Found ${participants.size} historical participants`);
  } catch (err) {
    logError("Failed to scan historical events", err);
  }

  return participants;
}

async function checkAndSlash(
  contract: Contract,
  keeperAddress: string,
  participants: Set<string>
): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  log(`Checking ${participants.size} participants at timestamp ${now}`);

  for (const user of participants) {
    try {
      const [isActive, participant] = await Promise.all([
        contract["isActive"](user) as Promise<boolean>,
        contract["getParticipant"](user) as Promise<{
          stakeAmount: bigint;
          lastHeartbeat: bigint;
        }>,
      ]);

      if (participant.stakeAmount === 0n) {
        log(`${user} has no stake, removing from tracking`);
        participants.delete(user);
        continue;
      }

      if (!isActive) {
        const lastHeartbeat = Number(participant.lastHeartbeat);
        const staleness = now - lastHeartbeat;
        const reward = participant.stakeAmount / 10n;

        log(`${user} is INACTIVE (stale by ${staleness}s). Slashing for reward: ${ethers.formatEther(reward)} RBTC`);

        try {
          const tx = await (contract["slash"] as (
            user: string,
            opts: { gasLimit: bigint }
          ) => Promise<{ hash: string; wait: () => Promise<unknown> }>)(
            user,
            { gasLimit: GAS_LIMIT }
          );

          log(`Slash tx sent for ${user}: ${tx.hash}`);
          await tx.wait();
          log(`Slash confirmed for ${user}. Earned ${ethers.formatEther(reward)} RBTC`);

          participants.delete(user);
        } catch (slashErr) {
          logError(`Failed to slash ${user}`, slashErr);
        }
      } else {
        const heartbeatInterval = await (contract["heartbeatInterval"]() as Promise<bigint>);
        const deadline = Number(participant.lastHeartbeat) + Number(heartbeatInterval);
        const remaining = deadline - now;
        log(`${user} is active. Time remaining: ${remaining}s`);
      }
    } catch (err) {
      logError(`Error checking participant ${user}`, err);
    }
  }
}

async function watchNewJoins(
  contract: Contract,
  participants: Set<string>
): Promise<void> {
  contract.on("Joined", (user: string) => {
    const addr = user.toLowerCase();
    if (!participants.has(addr)) {
      participants.add(addr);
      log(`New participant joined: ${addr}`);
    }
  });

  contract.on("Slashed", (user: string) => {
    const addr = user.toLowerCase();
    participants.delete(addr);
    log(`Participant slashed and removed from tracking: ${addr}`);
  });
}

async function main(): Promise<void> {
  log("Keeper bot starting...");
  log("Config", {
    rpcUrl: RPC_URL,
    contractAddress: CONTRACT_ADDRESS,
    pollIntervalMs: POLL_INTERVAL_MS,
    gasLimit: GAS_LIMIT.toString(),
  });

  const provider = new JsonRpcProvider(RPC_URL);
  const wallet = new Wallet(PRIVATE_KEY, provider);
  const keeperAddress = await wallet.getAddress();

  log(`Keeper wallet: ${keeperAddress}`);

  const network = await provider.getNetwork();
  log(`Connected to network: chainId=${network.chainId}`);

  const balance = await provider.getBalance(keeperAddress);
  log(`Keeper balance: ${ethers.formatEther(balance)} RBTC`);

  if (balance === 0n) {
    console.warn("[keeper] WARNING: Keeper wallet has zero balance. Slash transactions will fail.");
  }

  const contract = new Contract(CONTRACT_ADDRESS, PROOF_OF_LIVENESS_ABI, wallet);

  const [requiredStake, heartbeatInterval, slashedFundsSink] = await Promise.all([
    contract["requiredStake"]() as Promise<bigint>,
    contract["heartbeatInterval"]() as Promise<bigint>,
    contract["slashedFundsSink"]() as Promise<string>,
  ]);

  log("Contract config", {
    requiredStake: ethers.formatEther(requiredStake) + " RBTC",
    heartbeatInterval: heartbeatInterval.toString() + "s",
    slashedFundsSink,
  });

  const participants = await getActiveParticipants(contract, provider, SCAN_FROM_BLOCK);

  await watchNewJoins(contract, participants);

  const runCycle = async () => {
    try {
      await checkAndSlash(contract, keeperAddress, participants);
    } catch (err) {
      logError("Unexpected error in check cycle", err);
    }
  };

  await runCycle();

  log(`Starting poll loop every ${POLL_INTERVAL_MS / 1000}s`);
  setInterval(runCycle, POLL_INTERVAL_MS);
}

main().catch((err) => {
  logError("Fatal error", err);
  process.exit(1);
});
