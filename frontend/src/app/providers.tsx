"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig, http, injected, type Config } from "wagmi";
import { rootstockTestnet, rootstockMainnet } from "@/lib/chains";

const wagmiConfig: Config = createConfig({
  chains: [rootstockTestnet, rootstockMainnet],
  connectors: [injected()],
  transports: {
    [rootstockTestnet.id]: http(),
    [rootstockMainnet.id]: http(),
  },
  ssr: true,
});

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    </WagmiProvider>
  );
}
