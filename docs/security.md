# Boundaries and remaining work

Unaudited synthetic-asset testnet sandbox. Do not deposit real assets.

- **Economics:** reduces residual directional exposure after hedge loss. No avoided historical loss, APY, alpha or speed superiority claimed. Sales can incur slippage and adverse execution.
- **Oracles:** manager-controlled scenario context, not independent production feeds. Observation and oracle timestamps remain distinct. Correlated bad sources can pass a disagreement guard.
- **GMX:** full pinned GMX engine in our sandbox, not its official production deployment. Operator retains role administration. Each strategy has separate market, assets, oracle context and spot pool.
- **Reactive:** event ingestion and official callback proxy remain trust dependencies. Delivery is asynchronous. A fast keeper may react sooner. Native venue protections remain necessary.
- **Delivery:** duplicate/order guards and sequence-bound acknowledgements. Failed or expired callbacks can leave residual exposure. Missing acknowledgements can exhaust retries after partial settlement.
- **Expiry:** 15-minute leases / 20 observations are demo resource limits. Expiry stops automation; it does not close positions. Owners must close/retire explicitly.
- **Sponsorship:** three source leases concurrently; low coordinator reserve rejects registration. Public testnet spam can consume the sponsored service. Production needs admission control and per-user metering. Permanent free automation is not promised.
- **Recovery:** three healthy observations spanning 30 seconds plus current-incident approval. Thin-liquidity restoration may need a new strategy after the intentionally destructive sandbox drain.
- **Custody:** one manager per strategy; no pooled shares. Spot withdrawals require local retirement. Source collateral withdrawal requires local retirement and zero GMX position. Emergency actions on one chain do not settle the other.
- **Signing:** encrypted operator keystore loaded in memory. Durable signing journals are ignored private files, never frontend assets. Browser owners sign their own setup/scenario actions.
- **Production:** audits, independent feeds, real liquidity, finality/reorg handling, verified sources, monitoring, quota management, keeper fallback, and protocol governance permissions.

Destination callbacks consume native Unichain testnet ETH from each user's vault. `pay` is restricted to the official proxy. Vault creation requires at least 0.00005 ETH; the UI allocates 0.0001 ETH. Owners can top up by sending ETH directly to their vault; after retirement they can settle proxy debt and withdraw remaining gas with `withdrawGas`.

The source account's withdrawal exports collateral tokens. Unused GMX execution-fee ETH refunded into a source account has no native-ETH sweep in this version; the UI deliberately uses a small testnet fee of 0.00001 ETH per request. Native fee recovery is remaining work before any use with real funds.
