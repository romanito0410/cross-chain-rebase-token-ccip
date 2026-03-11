# 🔄 Cross-Chain Rebase Token — Chainlink CCIP

A cross-chain rebase token that automatically accrues interest over time, 
bridgeable across chains via Chainlink CCIP. Users deposit ETH into a Vault 
and receive rebase tokens that grow in value linearly with time.

## Overview

Three core contracts power the protocol:
- **RebaseToken** — ERC20 token with per-user interest rates that accrue linearly 
  over time. Each user inherits the global interest rate at deposit time.
- **Vault** — accepts ETH deposits, mints rebase tokens 1:1, handles redemptions 
  by burning tokens and returning ETH including accrued interest.
- **RebaseTokenPool** — Chainlink CCIP custom token pool that handles cross-chain 
  transfers. On the source chain it burns tokens (`lockOrBurn`), on the destination 
  chain it mints tokens with the user's original interest rate preserved (`releaseOrMint`).

The global interest rate can only decrease over time — protecting early depositors 
who locked in higher rates.

## Tech Stack

- **Solidity** ^0.8.24
- **Foundry** — build, test, deploy
- **Chainlink CCIP** — cross-chain token transfers via custom TokenPool
- **Chainlink Local Simulator** — fork-based cross-chain testing
- **OpenZeppelin** — ERC20, Ownable, AccessControl

## Architecture
```
src/
  RebaseToken.sol              # Core rebase token with linear interest accrual
  RebaseTokenPool.sol          # CCIP custom pool (lockOrBurn / releaseOrMint)
  Vault.sol                    # ETH deposit/redeem vault
  interfaces/
    IRebaseToken.sol           # Interface for cross-chain compatibility
script/
  Deployer.s.sol               # TokenAndPoolDeployer + VaultDeployer
  BridgeTokens.s.sol           # CCIP bridge script
  ConfigurePool.s.sol          # Pool chain configuration script
test/
  RebaseTokenTest.t.sol        # Unit & fuzz tests
  CrossChainTest.t.sol         # Fork-based CCIP integration tests
```

## Key Design Decisions

**Interest rate preserved across chains**
When bridging, `lockOrBurn` encodes the user's interest rate into `destPoolData`. 
On the destination chain, `releaseOrMint` decodes it and mints tokens with the 
original rate — users don't lose their rate when bridging.

**Per-user interest rates**
Each user inherits the global interest rate at deposit time. When transferring 
tokens, the recipient inherits the sender's rate — no one can game a higher rate 
through transfers.

**Linear interest accrual**
Interest is calculated as `principalBalance * (1 + rate * timeElapsed)`. 
Fully predictable and gas efficient — no compounding.

**Interest rate can only decrease**
`setInterestRate` reverts if the new rate >= current rate. Early depositors 
are permanently protected.

**Role-based access control**
`mint` and `burn` are restricted to `MINT_AND_BURN_ROLE` via OpenZeppelin 
AccessControl. Only the Vault and the TokenPool can mint or burn.

## Tests
```bash
# Unit & fuzz tests
forge test --match-path test/RebaseTokenTest.t.sol

# Cross-chain fork tests (requires RPC URLs in .env)
forge test --match-path test/CrossChainTest.t.sol --fork-url $SEPOLIA_RPC_URL
```

Unit test coverage:
- Fuzz tests on deposit, redeem, and time-based interest accrual
- Linear growth assertion over multiple time periods
- Transfer interest rate inheritance verification
- Access control tests for mint/burn and interest rate changes
- Interest rate monotonic decrease invariant

Cross-chain integration tests:
- Bridge all tokens Sepolia → Arbitrum
- Bridge all tokens back Arbitrum → Sepolia
- Bridge twice with interest accrual between bridges
- Interest rate preserved after bridging

Coverage: 95%+ on core contracts (RebaseToken, Vault, RebaseTokenPool).

## Deployment
```bash
# Deploy token + pool on each chain
forge script script/Deployer.s.sol:TokenAndPoolDeployer \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify

# Deploy vault on source chain
forge script script/Deployer.s.sol:VaultDeployer \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast

# Configure pool
forge script script/ConfigurePool.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast

# Bridge tokens
forge script script/BridgeTokens.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast
```

## What I Learned

- Building a custom Chainlink CCIP TokenPool with `lockOrBurn` / `releaseOrMint`
- Preserving per-user state (interest rate) across chain bridges via CCIP pool data
- Writing fork-based cross-chain integration tests with CCIPLocalSimulatorFork
- Implementing linear interest accrual with per-user state in Solidity
- Using AccessControl vs Ownable for granular role management