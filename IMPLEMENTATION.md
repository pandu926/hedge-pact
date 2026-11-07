# Hedge Pact MVP implementation

Accepted: self-service, isolated strategies, full GMX sandbox on Base Sepolia, spot vaults on Unichain Sepolia, Reactive Lasna. Hyperliquid SKHYNIX is the incident narrative, not a live integration.

Execution sequence:
- [x] Native GMX short → partial ADL → actual remaining position proof.
- [x] Isolated source accounts/markets and spot pools; registration handshake.
- [x] Reactive routing, acknowledged settlement, bounded retries and recovery.
- [x] Self-service wallet onboarding, Scenario Lab, dashboard and receipt viewer.
- [x] Local isolation/security/lifecycle verification and public deployment preflight.
- [x] Public end-to-end receipt proofs, public repository/site, <3-minute video.

Budgets: Base Sepolia0.02ETH, Unichain Sepolia0.01ETH, Lasna3lREACT. Never use mainnet. Preserve all prior pilot files. No private key or signing journal in public artifacts.
