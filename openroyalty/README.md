# OpenRoyalty 🎵

**OpenRoyalty** is a decentralized, transparent music royalty and licensing platform built on **Stacks** (Clarity smart contracts). It allows artists, producers, and rights holders to register music works, automate royalty splits, enable real-time payouts, and create fan-owned royalty shares — all on-chain.

---

## 🚀 Features
- **On-chain Rights Registry:** Register music works and master recordings as NFTs.
- **Automated Royalty Splits:** Smart contracts handle payouts across multiple rightsholders.
- **Instant Licensing Marketplace:** Buyers can purchase music sync licenses programmatically.
- **Fan Royalty Shares (Notes):** Artists can sell fractional future royalties to fans.
- **Real-time Usage Tracking:** Integrates oracles to push streaming revenue data.
- **DAO Governance:** Token-based voting on protocol parameters and upgrades.
- **Transparent Accounting:** Every payment and revenue split is auditable on-chain.

---

## 🧱 Architecture

The platform consists of **7–10 Clarity contracts**:

1. **`rights-registry.clar`** – Registers music works as NFTs (SIP-009 compliant).  
2. **`split-manager.clar`** – Manages royalty split percentages for each work.  
3. **`royalty-vault.clar`** – Handles all deposits and automated distributions.  
4. **`usage-oracle-adapter.clar`** – Receives verified streaming/usage data from off-chain oracles.  
5. **`licensing-marketplace.clar`** – Enables instant sync and micro-licensing.  
6. **`fan-advance-note.clar`** – Issues fractional revenue-share tokens (SIP-010/1155).  
7. **`governance-token.clar`** – DAO governance for protocol rules and upgrades.  
8. **`protocol-treasury.clar`** – Holds fees, grants, and protocol revenue.  
9. **`access-pass.clar`** – NFT-based membership tiers for superfans and exclusive content.  
10. **`dispute-resolver.clar`** – Resolves disputes (ownership, splits, oracle data).

---

## 🛠 Tech Stack
- **Smart Contracts:** [Clarity Language](https://docs.stacks.co/write-smart-contracts/clarity) (Stacks blockchain)
- **Token Standards:** SIP-009 (NFT), SIP-010 (Fungible Token), SIP-013 (Multi-token)
- **Indexing:** [Stacks API](https://docs.hiro.so/api) + GraphQL for data queries
- **Frontend:** Next.js + TailwindCSS
- **Oracles:** Chainlink Functions or custom off-chain workers posting to `usage-oracle-adapter.clar`
- **Wallet Integration:** Hiro Wallet, Xverse

---

## ⚙️ Installation

### Prerequisites
- Node.js >= 18
- Clarinet (for local Clarity dev): [Install Guide](https://docs.hiro.so/clarinet/getting-started)
- Stacks wallet (testnet)

### Setup
```bash
# Clone repo
git clone https://github.com/your-username/openroyalty.git
cd openroyalty

# Install dependencies
npm install

