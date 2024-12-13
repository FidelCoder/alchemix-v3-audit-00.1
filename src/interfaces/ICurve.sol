pragma solidity 0.8.18;


interface ICurveStableSwapNG {
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy, address _receiver) external;
    function price_oracle(uint256 i) external view returns (uint256);
}

interface ICurveRouterNG {
    function exchange(address[11] calldata _route, uint256[5][5] calldata _swapParams, uint256 _amountIn, uint256 _minAmountOut, address[5] calldata _pools, address _receiver) external;
}