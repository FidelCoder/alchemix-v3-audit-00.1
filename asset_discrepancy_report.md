# Vulnerability Report: Asset Discrepancy Between Reported and Available Funds

## Summary
The Alchemix v3 strategy contracts exhibit a critical vulnerability in their asset accounting mechanism where the `_harvestAndReport` function reports total assets that include claimable balances, but these balances are not automatically claimed and converted to the base asset during normal operations. This creates a significant discrepancy between reported assets and actually available funds, potentially leading to withdrawal failures and bad debt during periods of high redemption demand.

## Vulnerability Details

### Issue
In the various strategy contracts (`StrategyOp.sol`, `StrategyMainnet.sol`, `StrategyArb.sol`), the `_harvestAndReport` function:

1. Counts claimable tokens from the transmuter as part of `totalAssets`
2. Does not actually claim these tokens during the report function, as shown by the commented-out code
3. Creates a mismatch between the strategy's reported total value and the actually available funds

```solidity
function _harvestAndReport()
    internal
    override
    returns (uint256 _totalAssets)
{
    uint256 claimable = transmuter.getClaimableBalance(address(this));        
    uint256 unexchanged = transmuter.getUnexchangedBalance(address(this));

    // NOTE : possible some dormant WETH that isn't swapped yet
    uint256 underlyingBalance = underlying.balanceOf(address(this));

    _totalAssets = unexchanged + asset.balanceOf(address(this)) + underlyingBalance;

    if (claimable > 0) {
        // transmuter.claim(claimable, address(this));
    }
}
```

While simultaneously, the `availableWithdrawLimit` function only includes immediately available assets:

```solidity
function availableWithdrawLimit(
    address /*_owner*/
) public view override returns (uint256) {
    // NOTE: Withdraw limitations such as liquidity constraints should be accounted for HERE
    //  rather than _freeFunds in order to not count them as losses on withdraws.

    // NOTE : claimable balance can only be included if we are actually allowing swaps to happen on withdrawals
    //uint256 claimable = transmuter.getClaimableBalance(address(this));
    
    return asset.balanceOf(address(this)) + transmuter.getUnexchangedBalance(address(this));
}
```

This discrepancy between `totalAssets` (which includes claimable balances) and `availableWithdrawLimit` (which does not) creates several issues:

### Impact
This vulnerability can lead to several critical issues:

1. **Withdrawal Failures**: During high redemption periods, users may be unable to withdraw their funds because the strategy reports having more assets than it can actually access.

2. **Liquidity Crises**: If many users attempt to withdraw simultaneously, the strategy won't be able to fulfill all requests, potentially leading to a bank run scenario.

3. **Bad Debt**: If some users manage to withdraw before others, later users may find their funds unavailable or delayed.

4. **Trust Issues**: The mismatch between reported and actual available funds could lead to trust issues with the protocol.

5. **Operational Overhead**: Manual keeper intervention is required to claim and swap assets to fulfill withdrawals, creating operational risks.

## Proof of Concept
1. Users deposit assets into the strategy.
2. The strategy acquires claimable balances over time.
3. During a report, the strategy reports these claimable balances as part of `totalAssets`.
4. Users attempt to withdraw based on their share of the reported `totalAssets`.
5. The strategy cannot fulfill all withdrawals because the claimable funds are not automatically claimed and swapped.

This scenario is demonstrated in the `HarvestReportAssetDiscrepancyTest.sol` test file, which shows exactly how the discrepancy between reported and available assets can lead to withdrawal failures.

## Recommended Mitigation
There are several possible mitigations for this issue:

1. **Auto-Claim During Reporting**: Complete the implementation of the `_harvestAndReport` function to automatically claim tokens:
```solidity
function _harvestAndReport()
    internal
    override
    returns (uint256 _totalAssets)
{
    uint256 claimable = transmuter.getClaimableBalance(address(this));        
    uint256 unexchanged = transmuter.getUnexchangedBalance(address(this));

    // NOTE : possible some dormant WETH that isn't swapped yet
    uint256 underlyingBalance = underlying.balanceOf(address(this));

    _totalAssets = unexchanged + asset.balanceOf(address(this)) + underlyingBalance;

    if (claimable > 0) {
        transmuter.claim(claimable, address(this));
        // Additionally, consider swapping claimed tokens to the base asset
    }
}
```

2. **Consistent Asset Accounting**: Ensure that the same accounting method is used in both `_harvestAndReport` and `availableWithdrawLimit`:
   - Either include claimable balances in both functions
   - Or exclude them from both functions

3. **Withdrawal Queue**: Implement a withdrawal queue system for large withdrawals that require claiming and swapping.

4. **Reserve Requirement**: Maintain a minimum reserve of the base asset to handle regular withdrawal demands.

5. **Automatic Claiming Threshold**: Implement a mechanism to automatically claim and swap when claimable balances exceed a certain threshold.

## Related Issues
This vulnerability is related to the incomplete harvest implementation identified in the `harvest_vulnerability_report.md` but focuses specifically on the discrepancy between reported and available assets rather than the general implementation problems. 