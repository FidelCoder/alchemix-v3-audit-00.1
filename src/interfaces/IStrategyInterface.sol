// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IVeloRouter} from "./IVelo.sol";
import {IRamsesRouter} from "./IRamses.sol";

interface IStrategyInterface is IStrategy {
    //TODO: Add your specific implementation interface in here.
    function claimableBalance() external view returns (uint256);   
    function unexchangedBalance() external view returns (uint256);
    function claimAndSwap(
            uint256 _amountClaim, 
            uint256 _minOut,
            uint256 _routeNumber
    ) external;    
    function setCurvePool(address _curvePool, int128 _assetIndex, int128 _underlyingIndex) external;
    function setVeloRouter(address _router, address[] memory _path) external;
    function addRoute(
        address[11] calldata _route,
        uint256[5][5] calldata _swapParams,
        address[5] calldata _pools) external;
}

interface IStrategyInterfaceVelo is IStrategy {
    function claimAndSwap(uint256 _amountClaim, uint256 _minOut, IVeloRouter.route[] calldata _path ) external;
}

interface IStrategyInterfaceRamses is IStrategy {
    function claimAndSwap(uint256 _amountClaim, uint256 _minOut, IRamsesRouter.route[] calldata _path ) external;
}