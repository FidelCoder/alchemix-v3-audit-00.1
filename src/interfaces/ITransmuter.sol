pragma solidity 0.8.18;


interface ITransmuter {
    function deposit(uint256 _amount, address _owner) external;
    function claim(uint256 _amount, address _owner) external;
    function withdraw(uint256 _amount, address _owner) external;

    function getClaimableBalance(address _owner) external view returns (uint256);
    function getExchangedBalance(address _owner) external view returns (uint256);
    function getUnexchangedBalance(address _owner) external view returns (uint256);
    function exchange(uint256 _amount) external;

    function totalUnexchanged() external view returns (uint256);
    function totalBuffered() external view returns (uint256);

    function syntheticToken() external view returns (address);
    function underlyingToken() external view returns (address);


}