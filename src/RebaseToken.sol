// SPDX-License-Identifier

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Rebase Token
 * @author Romain CHARLES
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault
 * @notice The interest rate in the smart contract can only decrease over time
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecresease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = 5 * PRECISION_FACTOR / 1e8;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _to) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _to);
    }

    /**
     * @notice Returns the current global interest rate
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only decrease over time
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecresease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Returns the principal balance of the user (the number of tokens that have actually been minted to the user, not including interest)
     * @param _user The address of the user
     * @return The principal balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }
    /**
     * @notice Mints the user tokens when they deposit into the vault
     * @param _to The address of the user to mint tokens to
     * @param amount The amount of tokens to mint
     * @dev Before minting, we need to mint the accrued interest to the user
     */

    function mint(address _to, uint256 amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, amount);
    }

    /**
     * @notice Burns the user tokens when they withdraw from the vault
     * @param _from The address of the user to burn tokens from
     * @param _amount The amount of tokens to burn
     * @dev Before burning, we need to mint the accrued interest to the user
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculates the balance for the user including the interest that has accumulated since their last update
     * (principal balance) + some interest rate that has accrued
     * @param _user The address of the user
     * @return The balance of the user including the interest that has accumulated since their last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens that have actually been minted to the user)
        // multiply the principal balance by the interest rate accumulated since the last update
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfers tokens from one user to another
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @dev Before transferring, we need to mint the accrued interest to both the sender and the recipient
     * @dev If the recipient has a balance of 0, we set their interest rate to the sender's interest rate
     * @dev If the _amount is max uint256, we transfer the entire balance of the sender
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfers tokens from one user to another on behalf of the sender
     * @param _sender The address of the sender
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @dev Before transferring, we need to mint the accrued interest to both the sender and the recipient
     * @dev If the recipient has a balance of 0, we set their interest rate to the sender's interest rate
     * @dev If the _amount is max uint256, we transfer the entire balance of the sender
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculates the accumulated interest for a user since their last update
     * @param _user The address of the user
     * @return linearInterest The accumulated interest for the user since their last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // We need to caculate the interest that has accumulated since the last update
        // This is going to be a linear growth with time
        // 1. Calculate the time difference since the last update
        // 2. Calculate the amount of linear growth
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Mints the accrued interest to the user
     * @param _user The address of the user
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user -> principal balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including interests -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
