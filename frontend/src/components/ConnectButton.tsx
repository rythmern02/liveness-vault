"use client";

import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from "wagmi";
import { injected } from "wagmi/connectors";
import { rootstockTestnet } from "@/lib/chains";

export function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { connect, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();

  const isWrongNetwork = isConnected && chainId !== rootstockTestnet.id;

  if (!isConnected) {
    return (
      <button
        id="connect-wallet-btn"
        onClick={() => connect({ connector: injected() })}
        disabled={isConnecting}
        className="connect-btn"
      >
        {isConnecting ? (
          <span className="flex items-center gap-2">
            <span className="spinner" />
            Connecting…
          </span>
        ) : (
          "Connect Wallet"
        )}
      </button>
    );
  }

  if (isWrongNetwork) {
    return (
      <button
        id="switch-network-btn"
        onClick={() => switchChain({ chainId: rootstockTestnet.id })}
        className="connect-btn wrong-network"
      >
        Switch to RSK Testnet
      </button>
    );
  }

  return (
    <div className="wallet-info">
      <div className="wallet-address">
        <span className="wallet-dot" />
        {address?.slice(0, 6)}…{address?.slice(-4)}
      </div>
      <button
        id="disconnect-wallet-btn"
        onClick={() => disconnect()}
        className="disconnect-btn"
      >
        Disconnect
      </button>
    </div>
  );
}
