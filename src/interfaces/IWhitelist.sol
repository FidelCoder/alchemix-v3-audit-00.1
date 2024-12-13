pragma solidity 0.8.18;

interface IWhitelist {
    function isWhitelisted(address _address) external view returns (bool);
    function add(address _address) external;
    function remove(address _address) external;
    function owner() external view returns (address);
}