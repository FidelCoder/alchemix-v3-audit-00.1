// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITransmuter} from "./interfaces/ITransmuter.sol";
import {IRamsesRouter} from "./interfaces/IRamses.sol";

// NOTE: Permissioned functions use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract StrategyArb is BaseStrategy {
    using SafeERC20 for ERC20;

    ITransmuter public transmuter;
    // since the asset is ALETH, we need to set the underlying to WETH
    ERC20 public underlying; 
    address public router;

    constructor(
        address _asset,
        address _transmuter,
        string memory _name
    ) BaseStrategy(_asset, _name) {
        transmuter = ITransmuter(_transmuter);
        require(transmuter.syntheticToken() == _asset, "Asset does not match transmuter synthetic token");
        underlying = ERC20(transmuter.underlyingToken());
        asset.safeApprove(address(transmuter), type(uint256).max);
        
        _initStrategy();
    }
    /**
     * @dev Initializes the strategy with the router address & approves WETH to be swapped via router
    */
    function _initStrategy() internal {
        
        router = 0xAAA87963EFeB6f7E0a2711F397663105Acb1805e;
        underlying.safeApprove(address(router), type(uint256).max);
        
    }


    function setRouter(address _router) external onlyManagement {
        router = _router;
        underlying.safeApprove(router, type(uint256).max);
    }

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     * Here alETH is deposited directly to the transmuter
     * Note we could also swap WEETH to alETH here if available to claim but making this call permissioned due to sandwiching risk
     */
    function _deployFunds(uint256 _amount) internal override {
        transmuter.deposit(_amount, address(this));
    }

    /**
     * @dev Function called by keeper to claim WETH from transmuter & swap to alETH at premium
     * we ensure that we are always swapping at a premium (i.e. keeper cannot swap at a loss)
        * @param _amountClaim The amount of WETH to claim from the transmuter
        * @param _minOut The minimum amount of alETH to receive after swap
        * @param _path The path to swap WETH to alETH (via Ramses Router)
    */
    function claimAndSwap(uint256 _amountClaim, uint256 _minOut, IRamsesRouter.route[] calldata _path) external onlyKeepers {
        transmuter.claim(_amountClaim, address(this));
        uint256 balBefore = asset.balanceOf(address(this));
        _swapUnderlyingToAsset(_amountClaim, _minOut, _path);
        uint256 balAfter = asset.balanceOf(address(this));
        require((balAfter - balBefore) >= _minOut, "Slippage too high");
        transmuter.deposit(asset.balanceOf(address(this)), address(this));
    }


    function _swapUnderlyingToAsset(uint256 _amount, uint256 minOut, IRamsesRouter.route[] calldata _path) internal {
        // TODO : we swap WETH to ALETH -> need to check that price is better than 1:1 
        // uint256 oraclePrice = 1e18 * 101 / 100;
        require(minOut > _amount, "minOut too low");
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        require(underlyingBalance >= _amount, "not enough underlying balance");
        IRamsesRouter(router).swapExactTokensForTokens(_amount, minOut, _path, address(this), block.timestamp);
    }


    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        uint256 totalAvailabe = transmuter.getUnexchangedBalance(address(this));
        if (_amount > totalAvailabe) {
            transmuter.withdraw(totalAvailabe, address(this));
        } else {
            transmuter.withdraw(_amount, address(this));
        }
    }


    function balanceDeployed() public view returns (uint256) {
        return transmuter.getUnexchangedBalance(address(this)) + underlying.balanceOf(address(this)) + asset.balanceOf(address(this));
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {

        uint256 claimable = transmuter.getClaimableBalance(address(this));

        if (claimable > 0) {
            // transmuter.claim(claimable, address(this));
        }

        // NOTE : we can do this in harvest or can do seperately in tend 
        // if (underlying.balanceOf(address(this)) > 0) {
        //     _swapUnderlyingToAsset(underlying.balanceOf(address(this)));
        // }
        
        uint256 unexchanged = transmuter.getUnexchangedBalance(address(this));

        // NOTE : possible some dormant WETH that isn't swapped yet 
        uint256 underlyingBalance = underlying.balanceOf(address(this));

        _totalAssets = unexchanged + asset.balanceOf(address(this)) + underlyingBalance;
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies.
     *
     *   EX:
     *       return asset.balanceOf(yieldSource);
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */

    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        // NOTE: Withdraw limitations such as liquidity constraints should be accounted for HERE
        //  rather than _freeFunds in order to not count them as losses on withdraws.

        // TODO: If desired implement withdraw limit logic and any needed state variables.

        // EX:
        // if(yieldSource.notShutdown()) {
        //    return asset.balanceOf(address(this)) + asset.balanceOf(yieldSource);
        // }
        // NOTE : claimable balance can only be included if we are actually allowing swaps to happen on withdrawals
        //uint256 claimable = transmuter.getClaimableBalance(address(this));
        
        return asset.balanceOf(address(this)) + transmuter.getUnexchangedBalance(address(this));
    }

    function claimableBalance() public view returns (uint256) {
        return transmuter.getClaimableBalance(address(this));
    }

    function unexchangedBalance() public view returns (uint256) {
        return transmuter.getUnexchangedBalance(address(this));
    }
    

    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        TODO: If desired Implement deposit limit logic and any needed state variables .
        
        EX:    
            uint256 totalAssets = TokenizedStrategy.totalAssets();
            return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    }
    */

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function _tendTrigger() internal view override returns (bool) {}
    */

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
    function _emergencyWithdraw(uint256 _amount) internal override {
        TODO: If desired implement simple logic to free deployed funds.

        EX:
            _amount = min(_amount, aToken.balanceOf(address(this)));
            _freeFunds(_amount);
    }

    */
}
