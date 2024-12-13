pragma solidity 0.8.18;

interface IVeloRouter {

    struct route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

}