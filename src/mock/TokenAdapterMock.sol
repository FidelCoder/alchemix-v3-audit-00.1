pragma solidity ^0.8.13;

interface IYieldToken {
    function price() external view returns (uint256);
    function underlying() external view returns (address);
    function deposit(uint256 _amount, address _recipient) external;
    function redeem(uint256 _amount, address _recipient) external;

}
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenAdapterMock {
    address public token;
    using SafeERC20 for IERC20;

    constructor(address _token) {
        token = _token;
    }

    function price() external view returns (uint256) {
        return IYieldToken(token).price();
    }

    function underlyingToken() external view returns (address) {
        return IYieldToken(token).underlying();
    }

    function wrap(uint256 _amount, address _recipient) external returns (uint256) {
        IERC20(IYieldToken(token).underlying()).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(IYieldToken(token).underlying()).safeApprove(token, _amount);

        IYieldToken(token).deposit(_amount, _recipient);
        //IYieldToken(token).underlying().transfer(_recipient, _amount);
        return(_amount);
    }

    function unwrap(uint256 _amount, address _recipient) external returns (uint256){
        uint256 balBefore = IERC20(IYieldToken(token).underlying()).balanceOf(address(this));
        IERC20(token).transferFrom(msg.sender, address(this), _amount);
        IYieldToken(token).redeem(_amount, _recipient);
        uint256 balAfter = IERC20(IYieldToken(token).underlying()).balanceOf(address(this));
        IERC20(IYieldToken(token).underlying()).transfer(msg.sender, balAfter);
        return(_amount);
    }

}