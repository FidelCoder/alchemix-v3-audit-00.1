// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITransmuter} from "./interfaces/ITransmuter.sol";
import {IVeloRouter} from "./interfaces/IVelo.sol";

// Added interface for price oracle
interface IPriceOracle {
    // Returns the price of token0 in terms of token1 with 18 decimals of precision
    function getPrice(address token0, address token1) external view returns (uint256);
}

// NOTE: Permissioned functions use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract FixedStrategyOp is BaseStrategy {
    using SafeERC20 for ERC20;

    ITransmuter public transmuter;
    // NOTE : since the asset is ALETH, we need to set the underlying to WETH
    ERC20 public underlying; 
    address public router;
    
    // Added oracle and minimum profit percentage variables
    IPriceOracle public priceOracle;
    uint256 public minProfitBps = 300; // 3% minimum profit by default
    
    // Added events for better monitoring and transparency
    event ClaimAndSwap(uint256 amountClaimed, uint256 amountReceived, uint256 expectedMinimum);
    event PriceOracleUpdated(address oldOracle, address newOracle);
    event MinProfitBpsUpdated(uint256 oldMinProfit, uint256 newMinProfit);

    constructor(
        address _asset,
        address _transmuter,
        address _priceOracle,
        string memory _name
    ) BaseStrategy(_asset, _name) {
        transmuter = ITransmuter(_transmuter);
        require(transmuter.syntheticToken() == _asset, "Asset does not match transmuter synthetic token");
        underlying = ERC20(transmuter.underlyingToken());
        asset.safeApprove(address(transmuter), type(uint256).max);
        
        // Initialize the price oracle
        priceOracle = IPriceOracle(_priceOracle);
        
        _initStrategy();
    }

    /**
     * @dev Sets the price oracle address
     * @param _priceOracle The address of the price oracle
     */
    function setPriceOracle(address _priceOracle) external onlyManagement {
        address oldOracle = address(priceOracle);
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleUpdated(oldOracle, _priceOracle);
    }
    
    /**
     * @dev Sets the minimum profit basis points for swaps
     * @param _minProfitBps The minimum profit in basis points (e.g., 300 = 3%)
     */
    function setMinProfitBps(uint256 _minProfitBps) external onlyManagement {
        require(_minProfitBps > 0, "Min profit must be greater than 0");
        uint256 oldMinProfit = minProfitBps;
        minProfitBps = _minProfitBps;
        emit MinProfitBpsUpdated(oldMinProfit, _minProfitBps);
    }

    /**
     * @dev Function called by keeper to claim WETH from transmuter & swap to alETH at premium
     * we ensure that we are always swapping at a premium (i.e. keeper cannot swap at a loss)
     * @param _amountClaim The amount of WETH to claim from the transmuter
     * @param _minOut The minimum amount of alETH to receive after swap
     * @param _path The path to swap WETH to alETH (via Velo Router)
     */
    function claimAndSwap(uint256 _amountClaim, uint256 _minOut, IVeloRouter.route[] calldata _path) external onlyKeepers {
        // Get the fair market price from the oracle
        uint256 fairMarketRate = priceOracle.getPrice(address(underlying), address(asset));
        
        // Calculate the expected minimum output with the required profit margin
        uint256 expectedMinimum = (_amountClaim * fairMarketRate * (10000 + minProfitBps)) / 10000 / 1e18;
        
        // Ensure the provided minOut is at least the expected minimum
        require(_minOut >= expectedMinimum, "Minimum output too low based on oracle price");
        
        // Claim the underlying tokens from the transmuter
        transmuter.claim(_amountClaim, address(this));
        uint256 balBefore = asset.balanceOf(address(this));

        // Perform the swap
        _swapUnderlyingToAsset(_amountClaim, _minOut, _path);
        
        uint256 balAfter = asset.balanceOf(address(this));
        uint256 received = balAfter - balBefore;
        
        // Verify the actual output meets our requirements
        require(received >= _minOut, "Slippage too high");
        
        // Emit an event with detailed information about the swap
        emit ClaimAndSwap(_amountClaim, received, expectedMinimum);
        
        // Deposit the received tokens back into the transmuter
        transmuter.deposit(asset.balanceOf(address(this)), address(this));
    }

    /**
     * @dev Internal function for swapping WETH to alETH via Velo Router
     */
    function _swapUnderlyingToAsset(uint256 _amount, uint256 minOut, IVeloRouter.route[] calldata _path) internal {
        // Verification is now done in the calling function using the oracle price
        // We still maintain this check as a second layer of protection
        require(minOut > _amount, "minOut too low");

        uint256 underlyingBalance = underlying.balanceOf(address(this));
        require(underlyingBalance >= _amount, "not enough underlying balance");
        
        // Execute the swap via the DEX router
        IVeloRouter(router).swapExactTokensForTokens(_amount, minOut, _path, address(this), block.timestamp);
    }
    
    // Rest of the contract remains the same...
} 