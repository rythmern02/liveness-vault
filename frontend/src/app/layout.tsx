import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { Providers } from "./providers";
import "./globals.css";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Liveness Vault — Proof of Liveness on Rootstock",
  description:
    "A trustless cryptoeconomic protocol enforcing participant liveness on Rootstock (RSK). Stake RBTC, send heartbeats, or get slashed.",
  keywords: ["rootstock", "RSK", "RBTC", "proof of liveness", "smart contract", "DeFi"],
  openGraph: {
    title: "Liveness Vault",
    description: "Trustless on-chain liveness enforcement for DAOs and cohorts. Built on Rootstock.",
    type: "website",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.className}>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
