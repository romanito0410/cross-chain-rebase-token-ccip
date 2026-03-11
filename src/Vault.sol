// SPDX-License-Identifier

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract Vault {
    // we need to pass the token address to the constructor
    // create a deposit function that will mint the tokens to the user equal to the amount of ETH the user has sent
    // create z redeem function that will burn the tokens from the user and sends the user ETH
    // create a way to add rewards to the vault
    error Vault__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @dev Deposit ETH into the vault and mint rebase tokens.
     */
    function deposit() external payable {
        // mint the user tokens equal to the amount deposited
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Redeem rebase tokens for ETH.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // burn the user tokens
        i_rebaseToken.burn(msg.sender, _amount);
        // send the user ETH equal to the amount of tokens burned
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
