# Hedge Pact — Keep both sides of the pact

Track: **Set It and Forget It** / Reactive Omni Buildathon.

Application: https://hedge-pact.release-worried7z.chatgpt.site

Source: https://github.com/pandu926/hedge-pact

Demo (83 seconds): https://hedge-pact.release-worried7z.chatgpt.site/demo.mp4

## Problem and narrative

Auto-deleveraging can close a profitable perpetual short. A strategy holding the offsetting spot on another chain then becomes directionally exposed. The xyz:SKHYNIX incident on Hyperliquid motivates this failure class: an unrepresentative oracle update, rapid liquidations, and ADL of profitable shorts. We do not assert that the affected accounts held a cross-chain spot hedge, that Hyperliquid is integrated, or that this MVP could have prevented reported historical losses.

## What we built

A self-service strategy sandbox: isolated native GMX account/market/oracle on Base Sepolia, a token-settled spot vault on Unichain Sepolia, and a Reactive Lasna coordinator. Users create and fund their own strategy, open a real position in the deployed GMX engine, register both sides, and arm a policy. A native GMX execution callback publishes the actual remaining position. Reactive verifies the source and routes the observation across chains. The destination applies local safety checks, settles tokens, and acknowledges the actual result.

There is no browser or private server in the protective execution path. The short cannot increase while armed. Unsafe references quarantine execution; failed swaps retain balances; retries stop after three attempts; recovery requires fresh spaced observations and current-incident approval.

## What is proven

In the public verified run, a native GMX short fell from **100 ETH to 60 ETH** after ADL. Reactive caused the Unichain vault to sell **40 ETH** in bounded chunks and receive **99,660.227478 synthetic USD**. The final acknowledgement confirmed spot and short at **60 ETH each**. [Receipt audit](../evidence/verified-hops.json), [full evidence](../evidence/public-run.json), [addresses](../deployments/manifest.json).

At the synthetic $2,500 reference, 40 ETH corresponds to $100,000. Actual output was $339.772522 below that reference value. Removing the 40 ETH residual removes $10,000 of directional sensitivity to a hypothetical subsequent 10% price move, before costs. This is a conditional exposure calculation, not observed profit or historical losses avoided; it removes upside as well as downside.

Validation: **26 Foundry tests**, **2 full GMX integration tests**, browser desktop/mobile checks, and public receipts including actual ERC20 transfers and sequence-bound acknowledgements. Public transport testing exposed and fixed callback billing and cross-chain clock skew. Failed attempts were retained, their coordinators retired, and superseded engine permissions revoked.

## Why Reactive

The economic relationship spans two independently administered chains. Native GMX risk mechanisms cannot directly enforce the remote spot leg. Reactive provides a shared on-chain decision and receipt loop without a continuously running project keeper. This is an interoperability and policy thesis. Earlier paired testing found the keeper faster in **98/98** completed pairs, so we make no speed-superiority claim.

## Limits

Full GMX code is deployed in our sandbox, not GMX's official production deployment. Assets, oracle context and AMM liquidity are synthetic. The operator controls sandbox GMX roles. Asynchronous delivery can fail or expire. Fifteen-minute leases, three concurrent sessions and observation quotas bound the sponsored demo. Contracts are unaudited. Production needs independent oracle sources, hardened admission/billing, monitoring, finality/reorg treatment, security review and protocol permissions.

Incident source: https://nexusmutual.io/blog/xyz-skhynix-flash-crash-on-hyperliquid-incident-report
