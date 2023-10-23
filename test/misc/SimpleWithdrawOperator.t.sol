// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import "euler-cvc/CreditVaultConnector.sol";
import "../../src/vaults/CreditVaultSimpleBorrowable.sol";
import "../../src/operators/SimpleWithdrawOperator.sol";

contract SimpleWithdrawOperatorTest is Test {
    ICVC cvc;
    MockERC20 asset;
    CreditVaultSimpleBorrowable vault;
    SimpleWithdrawOperator withdrawOperator;

    function setUp() public {
        cvc = new CreditVaultConnector();
        asset = new MockERC20("Asset", "ASS", 18);
        vault = new CreditVaultSimpleBorrowable(cvc, asset, "Vault", "VAU");
        withdrawOperator = new SimpleWithdrawOperator(cvc);
    }

    function test_SimpleWithdrawOperator(address alice, address bot) public {
        vm.assume(
            alice != address(0) &&
                alice != address(cvc) &&
                bot != address(cvc) &&
                !cvc.haveCommonOwner(alice, address(withdrawOperator))
        );
        address alicesSubAccount = address(uint160(alice) ^ 1);

        asset.mint(alice, 100e18);

        // alice deposits into her main account and a subaccount
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint).max);
        vault.deposit(50e18, alice);
        vault.deposit(50e18, alicesSubAccount);

        // for simplicity, let's ignore the fact that nobody borrows from a vault

        // alice authorizes the operator to act on behalf of her subaccount
        cvc.setAccountOperator(
            alicesSubAccount,
            address(withdrawOperator),
            type(uint).max
        );
        vm.stopPrank();

        assertEq(asset.balanceOf(address(alice)), 0);
        assertEq(vault.maxWithdraw(alice), 50e18);
        assertEq(vault.maxWithdraw(alicesSubAccount), 50e18);

        // assume that a keeper bot is monitoring the chain. when alice authorizes the operator,
        // the bot can call withdrawOnBehalf() function, withdraw on behalf of alice and get tipped
        vm.prank(bot);
        withdrawOperator.withdrawOnBehalf(address(vault), alicesSubAccount);

        assertEq(asset.balanceOf(alice), 49.5e18);
        assertEq(asset.balanceOf(bot), 0.5e18);
        assertEq(vault.maxWithdraw(alice), 50e18);
        assertEq(vault.maxWithdraw(alicesSubAccount), 0);

        // however, the bot cannot call withdrawOnBehalf() on behalf of alice's main account
        // because she didn't authorize the operator
        vm.prank(bot);
        vm.expectRevert(
            abi.encodeWithSelector(
                CreditVaultConnector.CVC_NotAuthorized.selector
            )
        );
        withdrawOperator.withdrawOnBehalf(address(vault), alice);
    }
}
