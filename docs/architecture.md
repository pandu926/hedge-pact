# Execution and trust

Strategy id: `keccak256(abi.encode(84532, manager, nonce))`. SourceAccount is an EIP-1167 clone. SourceFactory creates a separate GMX market, index token, collateral token, and oracle context. This isolates price shocks as well as positions. GMX liquidity/collateral are synthetic tokens; keeper actions are scoped through manager-only factory methods.

SourceFactory is trusted with GMX controller/keeper roles in this sandbox. Publication reads `Reader.getPosition` for a fixed account/market/collateral/short key. It never accepts a supplied short quantity. Native callbacks authenticate GMX handler addresses and event account/market, then publish actual remaining `sizeInTokens`. Unchanged refresh requires the manager or authenticated account, preventing outsiders from exhausting the observation budget.

Reactive subscribes to fixed factories. Source/destination registration must match id, owner, source, expiry. Destination ids derive from the caller, preventing another wallet from occupying that owner's id. A callback checks both the official proxy and coordinator address.

Observations carry sequence, source time, oracle time, lease expiry, short quantity, and venue price. Destination accepts increasing sequences, stores remote truth independently of local balances, and acts on monotonic reductions. Increasing the native short is forbidden while armed.

Unsafe/stale source or reference prices quarantine the strategy. Price deviation above 2% holds execution. Accepted decisions sell at most 25 ETH per call, with 1% minimum-output protection. The AMM transfers actual ERC20 assets; acknowledgement includes actual balances, target, mode, sequence, and remaining work.

Recovery requires three healthy observations over 30 seconds and current-incident manager approval. New incidents reset approval. A fresh observation never renews an old oracle timestamp.

Pending work enables CRON. Retry is spaced five seconds, capped at three, then unsubscribed. Initial delivery and binding can be retransmitted idempotently. Every callback reserves the first address word for proxy authentication.

The browser performs setup and scenario triggers only; automatic response needs no browser signature. History reads 500-block pages, retries and persists a cursor. Factory getters discover owner strategies without scanning all history.

Closing publishes zero short quantity and permits an already armed vault to sell remaining spot in bounded chunks. Initial unarmed snapshots cannot liquidate initial spot. Retirement and withdrawal are chain-local; cross-chain closure is not atomic.

Public transport testing exposed two additional requirements: vaults inherit the official `AbstractCallback` payer and are created with a native-ETH callback reserve; chain timestamps require bounded skew tolerance (60 seconds for registration horizon and 10 seconds for future observations). Clock tolerance does not renew stale data. Both failures and their retired deployments are retained in evidence.
