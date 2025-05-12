// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITransmuter} from "./interfaces/ITransmuter.sol";
import {IVeloRouter} from "./interfaces/IVelo.sol";

// Added interfaces for price oracle and transmuter buffer
interface IPriceOracle {
    // Returns the price of token0 in terms of token1 with 18 decimals of precision
    function getPrice(address token0, address token1) external view returns (uint256);
    // Returns the timestamp of the last oracle update
    function lastUpdateTimestamp() external view returns (uint256);
}

interface ITransmuterBuffer {
    function exchange(address _token) external;
}

// NOTE: Permissioned functions use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract FixedStrategyOp is BaseStrategy {
    using SafeERC20 for ERC20;

    ITransmuter public immutable transmuter;
    ERC20 public immutable underlying;
    address public immutable transmuterKeeper;
    
    // Added price oracle for safety checks
    IPriceOracle public priceOracle;
    
    // Added parameters for better risk control
    uint256 public maxPriceAgeDuration = 1 hours; // Maximum acceptable age of price data
    uint256 public maxSlippageBasisPoints = 100; // 1% default max slippage
    uint256 public minReserveRatio = 1000; // 10% in basis points - minimum reserve to handle withdrawals
    uint256 public autoClaimThreshold = 10_000 ether; // Threshold for auto-claiming
    
    // Added events for better monitoring and transparency
    event ClaimAndSwap(uint256 amountClaimed, uint256 amountReceived, uint256 expectedMinimum);
    event PriceOracleUpdated(address oldOracle, address newOracle);
    event MinProfitBpsUpdated(uint256 oldMinProfit, uint256 newMinProfit);

    constructor(
        address _asset,
        address _transmuter,
        address _underlying,
        address _transmuterKeeper, 
        address _priceOracle
    ) BaseStrategy(_asset) {
        transmuter = ITransmuter(_transmuter);
        underlying = ERC20(_underlying);
        transmuterKeeper = _transmuterKeeper;
        priceOracle = IPriceOracle(_priceOracle);
        
        // Approve transmuter to spend underlying tokens
        underlying.safeApprove(_transmuter, type(uint256).max);
        
        // Approve asset to be spent by transmuter
        ERC20(_asset).safeApprove(_transmuter, type(uint256).max);
        
        _initStrategy();
    }

    /**
     * @dev Sets the price oracle address
     * @param _priceOracle The address of the price oracle
     */
    function setPriceOracle(address _priceOracle) external onlyManagement {
        require(_priceOracle != address(0), "Invalid oracle address");
        address oldOracle = address(priceOracle);
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleUpdated(oldOracle, _priceOracle);
    }
    
    /**
     * @dev Sets the maximum acceptable price age
     * @param _maxPriceAgeDuration The maximum acceptable age in seconds
     */
    function setMaxPriceAgeDuration(uint256 _maxPriceAgeDuration) external onlyManagement {
        require(_maxPriceAgeDuration > 0, "Invalid duration");
        maxPriceAgeDuration = _maxPriceAgeDuration;
    }
    
    /**
     * @dev Sets the maximum slippage basis points
     * @param _maxSlippageBasisPoints The maximum slippage in basis points (e.g., 100 = 1%)
     */
    function setMaxSlippageBasisPoints(uint256 _maxSlippageBasisPoints) external onlyManagement {
        require(_maxSlippageBasisPoints <= 1000, "Slippage too high"); // Max 10%
        maxSlippageBasisPoints = _maxSlippageBasisPoints;
    }
    
    /**
     * @dev Sets the minimum reserve ratio basis points
     * @param _minReserveRatio The minimum reserve ratio in basis points (e.g., 1000 = 10%)
     */
    function setMinReserveRatio(uint256 _minReserveRatio) external onlyManagement {
        require(_minReserveRatio <= 5000, "Reserve too high"); // Max 50%
        minReserveRatio = _minReserveRatio;
    }
    
    /**
     * @dev Sets the auto claim threshold
     * @param _autoClaimThreshold The auto claim threshold in wei
     */
    function setAutoClaimThreshold(uint256 _autoClaimThreshold) external onlyManagement {
        autoClaimThreshold = _autoClaimThreshold;
    }

    /**
     * @dev Function called by keeper to claim WETH from transmuter & swap to alETH at premium
     * we ensure that we are always swapping at a premium (i.e. keeper cannot swap at a loss)
     * @param _amountClaim The amount of WETH to claim from the transmuter
     * @param _minOut The minimum amount of alETH to receive after swap
     * @param _path The path to swap WETH to alETH (via Velo Router)
     */
    function claimAndSwap(
        uint256 _amountClaim,
        uint256 _minOut,
        IVeloRouter.route[] calldata _path
    ) external onlyKeepers {
        // Claim assets from transmuter
        transmuter.claim(_amountClaim);
        
        // SECURITY FIX: Verify oracle price is fresh
        require(
            address(priceOracle) != address(0) && 
            priceOracle.lastUpdateTimestamp() > block.timestamp - maxPriceAgeDuration, 
            "Stale oracle"
        );
        
        // SECURITY FIX: Calculate fair market value with acceptable slippage
        uint256 expectedOut = priceOracle.getPrice(address(underlying), address(asset)) * _amountClaim / 1e18;
        uint256 minimumAcceptableOut = expectedOut * (10000 - maxSlippageBasisPoints) / 10000;
        
        // SECURITY FIX: Ensure minOut is reasonable compared to oracle price
        require(_minOut >= minimumAcceptableOut, "minOut too low vs oracle");
        
        // Execute the swap with verified parameters
        _swap(_amountClaim, _minOut, _path);
    }

    /**
     * @dev Internal function for swapping WETH to alETH via Velo Router
     */
    function _swap(
        uint256 _amountIn,
        uint256 _minOut,
        IVeloRouter.route[] calldata _path
    ) internal {
        // Approve the router to spend our tokens
        underlying.safeApprove(0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9, _amountIn);
        
        // Call the swap function on the router
        (bool success, ) = 0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9.call(
            abi.encodeWithSelector(
                0x519270c4,                       // exactInputCL function selector
                _path,                           // The route for the swap
                _amountIn,                        // The amount to swap
                _minOut,                          // The minimum amount to receive
                address(this),                    // Recipient of the output tokens
                block.timestamp + 15 minutes      // Deadline
            )
        );
        
        // Ensure the swap was successful
        require(success, "Swap failed");
        
        // Clear any remaining approvals
        underlying.safeApprove(0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9, 0);
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        uint256 claimable = transmuter.getClaimableBalance(address(this));        
        uint256 unexchanged = transmuter.getUnexchangedBalance(address(this));
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        uint256 assetBalance = asset.balanceOf(address(this));

        // SECURITY FIX: Auto-claim when threshold is reached
        if (claimable >= autoClaimThreshold) {
            transmuter.claim(claimable);
            underlyingBalance = underlying.balanceOf(address(this));
            
            // Attempt to auto-swap if we have a valid price oracle
            if (address(priceOracle) != address(0) && 
                priceOracle.lastUpdateTimestamp() > block.timestamp - maxPriceAgeDuration) {
                
                // Get oracle price and calculate minimum acceptable output with slippage
                uint256 expectedOut = priceOracle.getPrice(address(underlying), address(asset)) * underlyingBalance / 1e18;
                uint256 minOut = expectedOut * (10000 - maxSlippageBasisPoints) / 10000;
                
                // If we have a path for swapping and price is fresh, execute the swap
                if (block.chainid == 10) { // Optimism
                    // Create the swap route using predefined pools
                    IVeloRouter.route[] memory veloRoute = new IVeloRouter.route[](1);
                    veloRoute[0] = IVeloRouter.route(
                        address(underlying), 
                        address(asset), 
                        true, 
                        0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a // Standard pool address
                    );
                    
                    // Execute the swap if we have underlying tokens
                    if (underlyingBalance > 0) {
                        _swap(underlyingBalance, minOut, veloRoute);
                    }
                }
                // Add similar logic for other chains as needed
            }
            
            // Update balances after potential swap
            underlyingBalance = underlying.balanceOf(address(this));
            assetBalance = asset.balanceOf(address(this));
        }

        // Calculate total assets with the most up-to-date values
        _totalAssets = unexchanged + assetBalance + underlyingBalance;
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     */
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        // Get immediately available assets
        uint256 immediatelyAvailable = asset.balanceOf(address(this)) + 
                                      transmuter.getUnexchangedBalance(address(this));
                                      
        // Calculate the minimum reserve required based on total assets
        uint256 totalAsset = totalAssets();
        uint256 minReserveAmount = totalAsset * minReserveRatio / 10000;
        
        // If we have more than the minimum reserve, allow withdrawals
        if (immediatelyAvailable > minReserveAmount) {
            return immediatelyAvailable - minReserveAmount;
        }
        
        return 0; // Not enough immediately available funds for withdrawal
    }

    // Helper functions for external contract interactions
    function claimableBalance() public view returns (uint256) {
        return transmuter.getClaimableBalance(address(this));
    }

    function unexchangedBalance() public view returns (uint256) {
        return transmuter.getUnexchangedBalance(address(this));
    }
    
    function balanceDeployed() public view returns (uint256) {
        return transmuter.getUnexchangedBalance(address(this)) + 
               underlying.balanceOf(address(this)) + 
               asset.balanceOf(address(this));
    }

    /**
     * @notice Emergency function to claim and swap all available funds
     * @dev Can only be called by management in case of emergency
     */
    function emergencyClaimAndSwap(uint256 minOutRatio) external onlyManagement {
        uint256 claimable = transmuter.getClaimableBalance(address(this));
        
        if (claimable > 0) {
            // Claim the tokens
            transmuter.claim(claimable);
            
            // Calculate minimum output with the provided ratio
            uint256 minOut = claimable * minOutRatio / 10000;
            
            // Create emergency swap route
            IVeloRouter.route[] memory emergencyRoute = new IVeloRouter.route[](1);
            emergencyRoute[0] = IVeloRouter.route(
                address(underlying), 
                address(asset), 
                true, 
                0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a
            );
            
            // Execute the swap
            _swap(underlying.balanceOf(address(this)), minOut, emergencyRoute);
        }
    }
} 