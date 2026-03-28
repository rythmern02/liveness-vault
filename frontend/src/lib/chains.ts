import { defineChain } from "viem";

export const rootstockTestnet = defineChain({
  id: 31,
  name: "Rootstock Testnet",
  nativeCurrency: { decimals: 18, name: "Test RBTC", symbol: "tRBTC" },
  rpcUrls: {
    default: { http: ["https://rpc.testnet.rootstock.io/mMT24fA7ejB0ViywdU74VsNgX1jcju-T"] },
    public:  { http: ["https://rpc.testnet.rootstock.io/mMT24fA7ejB0ViywdU74VsNgX1jcju-T"] },
  },
  blockExplorers: {
    default: { name: "RSK Explorer Testnet", url: "https://explorer.testnet.rootstock.io" },
  },
  testnet: true,
});

export const rootstockMainnet = defineChain({
  id: 30,
  name: "Rootstock Mainnet",
  nativeCurrency: { decimals: 18, name: "RBTC", symbol: "RBTC" },
  rpcUrls: {
    default: { http: ["https://public-node.rsk.co"] },
    public:  { http: ["https://public-node.rsk.co"] },
  },
  blockExplorers: {
    default: { name: "RSK Explorer", url: "https://explorer.rootstock.io" },
  },
});
