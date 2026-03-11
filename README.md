# 🔄 Cross-Chain Rebase Token — Chainlink CCIP

A cross-chain rebase token that automatically accrues interest over time, 
deployable across multiple chains via Chainlink CCIP. Users deposit ETH into 
a Vault and receive rebase tokens that grow in value linearly with time.

## Overview

The protocol has two components:
- **RebaseToken** — ERC20 token with per-user interest rates that accrue linearly 
  over time. Each user inherits the global interest rate at the time of their deposit.
- **Vault** — accepts ETH deposits, mints rebase tokens 1:1, and handles redemptions 
  by burning tokens and returning ETH including accrued interest.

The global interest rate can only decrease over time — protecting early depositors 
who locked in higher rates.

## Tech Stack

- **Solidity** ^0.8.24
- **Foundry** — build, test, deploy
- **Chainlink CCIP** — cross-chain token transfers
- **OpenZeppelin** — ERC20, Ownable, AccessControl

## Architecture
```
src/
  RebaseToken.sol          # Core rebase token with linear interest accrual
  Vault.sol                # ETH deposit/redeem vault
  interfaces/
    IRebaseToken.sol       # Interface for cross-chain compatibility
script/
test/
  RebaseTokenTest.t.sol    # Fuzz & unit tests
```

## Key Design Decisions

**Per-user interest rates**
Each user inherits the global interest rate at deposit time. When transferring 
tokens, the recipient inherits the sender's rate — ensuring no user can game 
a higher rate through transfers.

**Linear interest accrual**
Interest is calculated as `principalBalance * (1 + rate * timeElapsed)`. 
No compounding — fully predictable and gas efficient.

**Interest rate can only decrease**
`setInterestRate` reverts if the new rate is >= current rate. Early depositors 
are protected — their locked-in rate is preserved forever.

**Role-based access control**
`mint` and `burn` are restricted to `MINT_AND_BURN_ROLE` via OpenZeppelin 
AccessControl. Only the Vault can mint or burn tokens — not even the owner.

**CCIP cross-chain transfers**
The token implements the CCIP interface allowing it to be bridged across chains 
while preserving each user's interest rate state.

## Tests
```bash
forge test
```

Coverage: 95%+ on core contracts (RebaseToken, Vault, RebaseTokenPool). 

Test suite includes:
- Fuzz tests on deposit, redeem, and time-based interest accrual
- Linear growth assertion over multiple time periods
- Transfer interest rate inheritance verification
- Access control tests for mint/burn and interest rate changes
- Interest rate monotonic decrease invariant

## Deployment
```bash
forge script script/DeployRebaseToken.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

## What I Learned

- Implementing linear interest accrual with per-user state in Solidity
- Using AccessControl vs Ownable for granular role management
- Cross-chain token design with Chainlink CCIP
- Writing fuzz tests for time-dependent financial logic