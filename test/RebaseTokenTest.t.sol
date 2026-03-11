// SPDX-License-Identifier

pragma solidity ^0.8.24;

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log(startBalance);
        assertEq(startBalance, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 newBalance = rebaseToken.balanceOf(user);
        console.log(newBalance);
        assertGt(newBalance, startBalance);
        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 finalBalance = rebaseToken.balanceOf(user);
        console.log(finalBalance);
        assertGt(finalBalance, newBalance);

        assertApproxEqAbs(finalBalance - newBalance, newBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        // 2. redeem right away
        vault.redeem(type(uint256).max);
        assertEq(address(user).balance, amount);
        // 3. check our rebase token balance
        uint256 finalBalance = rebaseToken.balanceOf(user);
        assertEq(finalBalance, 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        // 1. deposit
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();
        assertEq(rebaseToken.balanceOf(user), depositAmount);
        // 2. warp time
        vm.warp(block.timestamp + time);
        uint256 balance = rebaseToken.balanceOf(user);
        // And add some rewards to the vault to simulate interest
        vm.deal(owner, balance - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balance - depositAmount);
        // 3. redeem right away
        vm.prank(user);
        vault.redeem(type(uint256).max);
        // 4. check our rebase token balance
        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balance);
        // 5. check that we have more ETH than we started with
        assertGt(ethBalance, depositAmount);
    }

    function testTransferUpdatesInterestRate(uint256 amount, uint256 amoundToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amoundToSend = bound(amoundToSend, 1e5, amount - 1e5);
        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address recipient = makeAddr("recipient");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 recipientBalance = rebaseToken.balanceOf(recipient);
        assertEq(userBalance, amount);
        assertEq(recipientBalance, 0);

        //  owner reduces interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // 2. transfer
        vm.prank(user);
        rebaseToken.transfer(recipient, amoundToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 recipientBalanceAfterTransfer = rebaseToken.balanceOf(recipient);
        assertEq(userBalanceAfterTransfer, userBalance - amoundToSend);
        assertEq(recipientBalanceAfterTransfer, recipientBalance + amoundToSend);

        // check the user interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(recipient), 5e10);
    }

    function testCannotSetInterestRateIfNotOwner(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurnIfNotOwner() public {
        uint256 interestRate = rebaseToken.getInterestRate();
        
        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, 100, interestRate);
        
        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, 100);
    }

    function testgetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        // 2. check our rebase token balance
        uint256 principleAmount = rebaseToken.principleBalanceOf(user);
        assertEq(principleAmount, amount);

        vm.warp(block.timestamp + 1 hours);
        uint256 newPrincipleAmount = rebaseToken.principleBalanceOf(user);
        assertEq(newPrincipleAmount, amount);
    }

    function testGetRebasTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecresease.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
