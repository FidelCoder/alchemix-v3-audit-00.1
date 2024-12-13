pragma solidity 0.8.18;

interface IAlchemist {

    struct YieldTokenConfig {
        // The adapter used by the system to interop with the token.
        address adapter;
        // The maximum percent loss in expected value that can occur before certain actions are disabled measured in
        // units of basis points.
        uint256 maximumLoss;
        // The maximum value that can be held by the system before certain actions are disabled measured in the
        // underlying token.
        uint256 maximumExpectedValue;
        // The number of blocks that credit will be distributed over to depositors.
        uint256 creditUnlockBlocks;
    }

    function admin() external view returns (address);
    function depositUnderlying(address yieldToken, uint256 amount, address rec, uint256 minOut) external;
    function mint(uint256 _amount, address _recipient) external;
    function repay(address _underlying, uint256 _amount, address _recipient) external;
    function whitelist() external view returns (address);
    function burn(uint256 _amount, address _recipient) external;
    function addYieldToken(address yieldToken, YieldTokenConfig calldata config) external;
    function harvest(address yieldToken, uint256 amount) external;
    function setYieldTokenEnabled(address yieldToken, bool flag) external ;
}
