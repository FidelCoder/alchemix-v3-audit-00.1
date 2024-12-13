pragma solidity 0.8.18;


interface ITransmuterBuffer {
    function exchange(address _underlyingToken) external;
    function depositFunds(address _underlyingToken, uint256 _amount) external;
    function KEEPER() external view returns (bytes32);
}