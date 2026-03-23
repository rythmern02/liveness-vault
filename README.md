# Proof of Liveness Subscription State Machine 

A fully functional "Proof of Liveness" primitive built on the Rootstock (RSK) network. This project demonstrates a cryptoeconomic mechanism where participants stake native RBTC to prove their active participation over time through periodic "heartbeat" transactions. 

If a participant fails to submit their heartbeat within the required interval, they become inactive and their stake can be slashed by anyone—creating an economic incentive for a decentralized network of Keeper bots to maintain the system's state.

## 🏗 System Architecture

This monorepo is divided into three distinct workspaces:

### 1. Contracts (`/contracts`)
A Foundry-based smart contract development environment containing the core logic.
*   **Protocol Mechanics**: Participants join by locking up a precise `requiredStake`. Once joined, they must call `heartbeat()` before `heartbeatInterval` expires.
*   **The Slashing Game Theory**: If `block.timestamp > lastHeartbeat + heartbeatInterval`, the user's status changes to inactive. Any external address can call `slash()`. The slasher is rewarded with **10%** of the user's stake to cover gas and incentivize maintenance, while the remaining **90%** is sent to a `slashedFundsSink` (e.g., a treasury or burn address).
*   **Strict Security**: The `slash` function rigorously implements the Checks-Effects-Interactions (CEI) pattern, zeroing out the stake before executing native ETH transfers to absolutely prevent reentrancy attacks.
*   **Tests**: Exhaustive time-manipulation testing (`vm.warp`) using Foundry cheatcodes exists inside `GameTheory.t.sol` to verify math and security.

### 2. Keeper Bot Backend (`/backend`)
A lightweight, fault-tolerant Node.js & TypeScript service utilizing `ethers.js` (v6).
*   **Continuous Monitoring**: Subscribes to contract events and polls the RPC on a set interval.
*   **Automated Execution**: Maintains an in-memory set of actively joined participants and calculates their deadlines off-chain.
*   **Bounty Hunting**: As soon as a user misses their heartbeat deadline, the bot automatically broadcasts a `slash()` transaction to claim the 10% bounty reward.

### 3. Frontend Dashboard (`/frontend`)
A modern Next.js (App Router) web application styled with TailwindCSS and powered by `wagmi` / `viem`.
*   **Wallet Integration**: Connect standard Web3 wallets to interact with the Rootstock network.
*   **Liveness Tracking**: Displays the user's current status (`Active`, `Inactive/Slashed`, `Not Joined`) alongside a live countdown timer ticking down to their heartbeat deadline.
*   **Frictionless Actions**: Easy 1-click `Join` and `Heartbeat` buttons seamlessly handle native token transfers and logic validation.

## 🚀 Getting Started

### Prerequisites
Make sure you have Node > 18, [Foundry](https://book.getfoundry.sh/getting-started/installation), and [pnpm](https://pnpm.io/installation) installed.

```bash
# Install dependencies across all workspaces
pnpm install
```

### Running the Smart Contracts
Move into the `contracts` directory to compile and run tests.
```bash
cd contracts
forge build
forge test -vvv
```

### Running the Keeper Bot
To run the automated slashing service, configure your environment variables.
```bash
cd backend
cp .env.example .env
# Fill in your RPC_URL, KEEPER_PRIVATE_KEY, and CONTRACT_ADDRESS in the .env file
pnpm run dev
```

### Running the Frontend
Start the Next.js development server to view the UI.
```bash
cd frontend
pnpm run dev
```

## 📜 License
This project is licensed under the MIT License.
