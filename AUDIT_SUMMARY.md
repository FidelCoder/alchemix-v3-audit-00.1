# Alchemix v3 Audit Summary

## Overview
This audit was performed on the Alchemix v3 codebase focusing on the strategy contracts and their interaction with the transmuter system. The audit identified several high-severity vulnerabilities that could lead to significant loss of funds or protocol insolvency.

## Vulnerabilities Discovered

### 1. Price Manipulation in claimAndSwap Function (High Severity)
The `claimAndSwap` function in the strategy contracts is vulnerable to price manipulation attacks. An attacker can manipulate liquidity pools, then execute a swap with unfavorable rates while still passing the minimal checks in place. The vulnerability is due to insufficient validation of the `minOut` parameter against fair market rates.

**Location:** `StrategyOp.sol`, `StrategyMainnet.sol`, `StrategyArb.sol`

**Impact:** Direct loss of funds through MEV attacks and unfavorable swaps.

**Proof of Concept:** See `src/test/PriceManipulationAttack.t.sol`

**See full report:** `vulnerability_report.md`

### 2. Incomplete Harvest Implementation (High Severity)
The `_harvestAndReport` function has commented-out code that should be claiming tokens from the transmuter. This causes a discrepancy between the harvested/reported assets and actual accessible assets, potentially leading to fund loss during mass withdrawals.

**Location:** `StrategyOp.sol` lines 161-177

**Impact:** Incorrect accounting, potential bad debt, and withdrawal failures.

**Proof of Concept:** See `src/test/HarvestIncomplete.t.sol`

**See full report:** `harvest_vulnerability_report.md`

### 3. Asset Discrepancy Between Reported and Available Funds (High Severity)
The strategy contracts exhibit a critical discrepancy between reported total assets and actually available funds. While `totalAssets()` includes claimable balances, these balances are not automatically claimed and converted during normal operations, leading to potential withdrawal failures.

**Location:** `StrategyOp.sol` (multiple functions)

**Impact:** Users may be unable to withdraw their funds during high redemption periods, potentially leading to a bank run scenario.

**Proof of Concept:** See `src/test/HarvestReportAssetDiscrepancy.t.sol`

**See full report:** `asset_discrepancy_report.md`

### 4. Oracle Manipulation Vulnerability (High Severity)
The strategy contracts rely on price oracles without sufficient checks against oracle manipulation or stale prices. This could lead to unfavorable trades being executed and asset value loss, particularly in the `claimAndSwap` function.

**Location:** All strategy contracts

**Impact:** Loss of funds through manipulation of oracle prices.

**Proof of Concept:** See `src/test/OracleManipulation.t.sol`

**See full report:** `oracle_manipulation_report.md`

## Fixed Implementation

A comprehensive fix for all identified vulnerabilities has been implemented in `FixedStrategyOp.sol`. Key improvements include:

1. **Price Oracle Integration**: Added checks for oracle freshness and price reasonability in swap operations
2. **Automated Claiming**: Implemented auto-claiming and swapping of assets during harvest
3. **Aligned Asset Accounting**: Fixed the discrepancy between reported and available assets
4. **Reserve Requirements**: Added minimum reserve ratios to ensure liquidity for withdrawals
5. **Emergency Functions**: Added emergency tools for protocol administrators

## Recommendations

1. Implement the fixes provided in `FixedStrategyOp.sol`
2. Add comprehensive tests to verify the security of the fixes
3. Consider implementing circuit breakers for extreme market conditions
4. Add real-time monitoring of claim/swap operations
5. Establish conservative slippage limits for all swap operations
6. Use multiple oracle sources with median aggregation
7. Implement a withdrawal queue system for large redemptions
8. Maintain sufficient reserves to handle regular withdrawal demands

## Conclusion
The Alchemix v3 strategy contracts contain several high-severity vulnerabilities that could lead to significant loss of funds. These issues are predominantly related to price manipulation, incomplete implementation of core functions, and asset accounting discrepancies. By implementing the proposed fixes, the protocol can significantly improve its security posture and protect user funds from these vulnerabilities. 