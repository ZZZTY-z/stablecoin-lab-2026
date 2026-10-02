// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";


contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap
    // ==================================================================

    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        uint256 amount = uint256(raw) % 1_000_000e6;
        vm.assume(amount > 0);

        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);

        uint256 supplyBefore = stable.totalSupply();

        vm.prank(alice);
        vault.deposit(amount);

        uint256 supplyAfter = stable.totalSupply();

        assertEq(supplyAfter - supplyBefore, amount, "supply must increase by exactly amount");
    }

    function test_Ex2_DecimalsTrap() public {
        uint256 amount = 1000e18; // 10^21 raw units

        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);

        uint256 supplyBefore = stable.totalSupply();

        vm.prank(alice);
        vault.deposit(amount);

        uint256 supplyAfter = stable.totalSupply();
        uint256 minted = supplyAfter - supplyBefore;

        emit log_named_uint("raw minted units", minted);
        emit log_named_uint("minted as USDC (divide by 1e6)", minted / 1e6);

        assertEq(minted, amount, "raw supply increase equals raw deposit amount");
    }

    // ==================================================================
    // Ex4 · permissions and pausing
    // ==================================================================

    function test_Ex4_Mint_RevertsForNonMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                stable.MINTER_ROLE()
            )
        );
        vm.prank(attacker);
        stable.mint(attacker, 1000e6);
    }

    function test_Ex4_Pause_BlocksTransfers() public {
        // 先给 alice 一些 sUSD
        uint256 amount = 1000e6;
        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        // admin 持有 PAUSER_ROLE，然后暂停
        stable.grantRole(stable.PAUSER_ROLE(), admin);
        stable.pause();

        // 暂停后普通转账必须 revert
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        stable.transfer(attacker, 1e6);
    }

    function test_Ex4_Pause_BlocksRedeem() public {
        uint256 amount = 1000e6;
        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        stable.grantRole(stable.PAUSER_ROLE(), admin);
        stable.pause();

        // 暂停后赎回也被冻结，因为 redeem 会 burn sUSD，触发 _update
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.redeem(amount);
    }

    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        // 先给 alice 一些 sUSD
        uint256 amount = 1000e6;
        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        // attacker 没有 MINTER_ROLE，不能烧 alice 的余额
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                stable.MINTER_ROLE()
            )
        );
        vm.prank(attacker);
        stable.burn(alice, amount);
    }

    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        // 先给 alice 一些 sUSD
        uint256 amount = 1000e6;
        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        assertEq(stable.balanceOf(alice), amount);

        // vault 持有 MINTER_ROLE，所以可以烧任何人的余额
        vm.prank(address(vault));
        stable.burn(alice, amount);

        assertEq(stable.balanceOf(alice), 0);
    }
}