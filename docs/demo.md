# Judge walkthrough — under 3 minutes

0:00 — A hedge is two positions. ADL can remove a profitable short while spot survives on another chain. Hyperliquid's xyz:SKHYNIX incident motivates the failure class; we do not claim to prevent the reported losses.

0:20 — Open live app / evidence. Important stages link to explorer transactions. No wallet needed to inspect.

0:35 — Show isolated GMX source market and Unichain spot vault: 100 ETH spot against actual short 100 ETH. This is full GMX code in our Base Sepolia sandbox.

0:55 — Prepare destination spot context and trigger native partial ADL. GMX closes $200,000, leaving 60 ETH. The manager signs the incident trigger; the response needs no further browser signature.

1:15 — Inspect callback, observation, Reactive decision, spot ERC20 settlement, acknowledgement. Each trade is capped at 25 ETH.

1:45 — Safety branches: reference disagreement/staleness holds trading; failed swap preserves balances; retries are bounded; recovery requires spaced observations/current approval.

2:10 — Keeper was faster in all 98 completed prior pairs. Our thesis is cross-chain policy and verifiable settlement. A native mechanism remains preferable when it can protect both legs.

2:35 — Show self-service onboarding, source, tests, manifest. Keep both sides of the pact.
