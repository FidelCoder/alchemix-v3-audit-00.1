// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract HarvestIncompleteTest is Setup {
    uint256 initialDeposit = 100 ether;
    
    function setUp() public override {
        super.setUp();
    }
    
    function testIncompleteHarvestIssue() public {
        // 1. Initial setup - deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, initialDeposit);
        
        // 2. Setup - create claimable balance in the strategy
        deployMockYieldToken();
        addMockYieldToken();
        depositToAlchemist(initialDeposit);
        airdropToMockYield(initialDeposit / 2);
        
        // Similar setup as in Operation.t.sol
        vm.prank(whale);
        asset.transfer(user2, initialDeposit);
        
        vm.prank(user2);
        asset.approve(address(transmuter), initialDeposit);
        
        vm.prank(user2);
        transmuter.deposit(initialDeposit / 2, user2);
        
        vm.roll(1);
        harvestMockYield();
        
        vm.prank(address(transmuterKeeper));
        transmuterBuffer.exchange(address(underlying));
        
        skip(7 days);
        vm.roll(5);
        
        // 3. Verify there's a claimable balance
        uint256 initialClaimable = strategy.claimableBalance();
        assertGt(initialClaimable, 0, "!initialClaimable");
        console.log("Initial claimable balance:", initialClaimable);
        
        // 4. Trigger a harvest report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        
        console.log("Profit reported:", profit);
        console.log("Loss reported:", loss);
        
        // 5. Verify that the claimable balance hasn't changed
        // Since the harvest function doesn't actually claim the available tokens
        uint256 postHarvestClaimable = strategy.claimableBalance();
        assertEq(initialClaimable, postHarvestClaimable, "Claimable balance should not change");
        console.log("Post-harvest claimable balance:", postHarvestClaimable);
        
        // 6. Show that total assets includes claimable balance which could be misleading
        uint256 totalAssets = strategy.totalAssets();
        uint256 unexchanged = strategy.unexchangedBalance();
        uint256 free = asset.balanceOf(address(strategy));
        uint256 underlyingFree = underlying.balanceOf(address(strategy));
        
        console.log("Total assets reported:", totalAssets);
        console.log("Unexchanged balance:", unexchanged);
        console.log("Free assets:", free);
        console.log("Underlying free:", underlyingFree);
        
        // The vulnerability: report() doesn't actually claim claimable tokens, but
        // totalAssets() includes the underlying balance in its calculation
        // This means users can see their share value increase, but the strategy
        // doesn't actually hold those assets until a keeper calls claimAndSwap
        
        // 7. Demonstrate the impact - try to withdraw everything
        skip(strategy.profitMaxUnlockTime());
        
        uint256 userShares = strategy.balanceOf(user);
        vm.prank(user);
        
        // This will likely fail or result in partial withdrawal since
        // the assets aren't actually available
        if (userShares > 0) {
            strategy.redeem(userShares, user, user);
            
            uint256 userAssetsAfter = asset.balanceOf(user);
            console.log("User assets after withdrawal:", userAssetsAfter);
            
            // If withdrawal succeeds, it will likely be less than expected based on share value
            assertLt(userAssetsAfter, totalAssets, "User should not receive full value");
        }
    }
} 