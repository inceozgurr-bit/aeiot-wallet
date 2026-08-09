// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AEIOT} from "../src/AEIOT.sol";

contract AEIOTTest is Test {
    AEIOT token;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new AEIOT();
    }

    function test_supplyMintedToDeployer() public view {
        assertEq(token.totalSupply(), 1_150_115 ether);
        assertEq(token.balanceOf(address(this)), 1_150_115 ether);
    }

    function test_transfer() public {
        token.transfer(alice, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(address(this)), 1_150_115 ether - 100 ether);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert("AEIOT: insufficient balance");
        token.transfer(bob, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert("AEIOT: transfer to zero address");
        token.transfer(address(0), 1);
    }

    function test_transferFromRespectsAllowance() public {
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 60 ether);

        vm.prank(bob);
        token.transferFrom(alice, bob, 60 ether);
        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.allowance(alice, bob), 0);

        vm.prank(bob);
        vm.expectRevert("AEIOT: insufficient allowance");
        token.transferFrom(alice, bob, 1);
    }

    function test_infiniteAllowanceNotDecremented() public {
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(address(this), bob, 100 ether);
        assertEq(token.allowance(address(this), bob), type(uint256).max);
    }
}
