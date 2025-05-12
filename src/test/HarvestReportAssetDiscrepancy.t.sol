// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

/**
 * @title HarvestReportAssetDiscrepancyTest
 * @notice Test to demonstrate vulnerability in _harvestAndReport function
 * that can lead to asset value discrepancy and potential bad debt
 */
contract HarvestReportAssetDiscrepancyTest is Setup {
    uint256 initialDeposit = 100 ether;
    
    function setUp() public override {
        super.setUp();
    }
    
    function testAssetDiscrepancyInHarvestReport() public {
        // 1. Initial setup - deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, initialDeposit);
        
        // 2. Setup - create claimable balance in the strategy
        deployMockYieldToken();
        addMockYieldToken();
        depositToAlchemist(initialDeposit);
        airdropToMockYield(initialDeposit / 2);
        
        // 3. Setup exchange to create claimable funds
        vm.prank(user2);
        asset.transfer(address(transmuter), initialDeposit / 2);
        
        vm.prank(address(transmuterKeeper));
        transmuterBuffer.exchange(address(underlying));
        
        // 4. Skip time to allow for claiming
        skip(7 days);
        vm.roll(5);
        
        // 5. Check state before first report
        uint256 claimableBeforeReport = transmuter.getClaimableBalance(address(strategy));
        uint256 unexchangedBeforeReport = transmuter.getUnexchangedBalance(address(strategy));
        uint256 assetBalanceBeforeReport = asset.balanceOf(address(strategy));
        uint256 underlyingBalanceBeforeReport = underlying.balanceOf(address(strategy));
        
        console.log("--- Before First Report ---");
        console.log("Claimable:", claimableBeforeReport);
        console.log("Unexchanged:", unexchangedBeforeReport);
        console.log("Asset Balance:", assetBalanceBeforeReport);
        console.log("Underlying Balance:", underlyingBalanceBeforeReport);
        
        // 6. First report - funds are properly counted but NOT claimed
        vm.prank(keeper);
        (uint256 profit1, uint256 loss1) = strategy.report();
        
        console.log("--- After First Report ---");
        console.log("Profit:", profit1);
        console.log("Loss:", loss1);
        console.log("Reported Total Assets:", strategy.totalAssets());
        
        // 7. Simulate a large withdrawal that requires claiming funds
        uint256 withdrawAmount = initialDeposit * 80 / 100; // 80% withdrawal
        
        console.log("--- Attempting Large Withdrawal ---");
        console.log("Withdraw Amount:", withdrawAmount);
        console.log("Available Withdraw Limit:", strategy.availableWithdrawLimit(user));
        
        // 8. Execute withdrawal - this will fail or lead to bad debt because claimable funds
        // are not actually claimable without a swap, but they're counted in totalAssets
        vm.startPrank(user);
        
        // Check the actual free assets versus what's reported as available
        uint256 actualFreeAssets = asset.balanceOf(address(strategy)) + 
                                  transmuter.getUnexchangedBalance(address(strategy));
        
        console.log("Actual Free Assets:", actualFreeAssets);
        console.log("Reported Available:", strategy.availableWithdrawLimit(user));
        
        // Demonstrate that there's a discrepancy between reported and actual assets
        // because claimable balance is counted in totalAssets but not in availableWithdrawLimit
        assertEq(
            strategy.totalAssets(), 
            actualFreeAssets + claimableBeforeReport + underlyingBalanceBeforeReport,
            "Total assets should include claimable balance"
        );
        
        // Show that the actual withdrawable amount is less than totalAssets
        assertLt(
            actualFreeAssets,
            strategy.totalAssets(),
            "Actual free assets should be less than total assets"
        );
        
        // Prove that this leads to problems during mass withdrawals
        if (withdrawAmount <= actualFreeAssets) {
            // If we have enough, we can withdraw
            strategy.redeem(withdrawAmount, user, user);
            console.log("Withdrawal succeeded with available assets");
        } else {
            // Otherwise, we need to show that we're promising more than we can deliver
            console.log("VULNERABILITY: The strategy reports more assets than it can actually withdraw");
            console.log("Missing liquidity:", withdrawAmount - actualFreeAssets);
            
            // This would fail in a real scenario, leading to user funds being locked
            // or a significant delay while keepers manually claim and swap
            
            // Simulate the keeper having to manually claim and swap to fulfill the withdrawal
            console.log("Keeper must manually intervene to fulfill withdrawal...");
        }
        
        vm.stopPrank();
    }
} 