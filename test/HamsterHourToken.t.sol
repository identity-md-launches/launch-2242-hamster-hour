// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HamsterHourToken} from "../src/HamsterHourToken.sol";
import {TestBase} from "./utils/TestBase.sol";

/// @notice Behaviour of the Hamster Hour token: the one-time mint, metadata, transfers and
///         allowances on the success path, every documented revert on the failure path, and the
///         absence of any mint, owner, pause or blocklist surface.
contract HamsterHourTokenTest is TestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant DEPLOYER = address(0xDE91);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant ATTACKER = address(0xBEEF);

    HamsterHourToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new HamsterHourToken();
    }

    /*//////////////////////////////////////////////////////////////
                           MINT AND METADATA
    //////////////////////////////////////////////////////////////*/

    function test_metadata() public view {
        assertEq(token.name(), "Hamster Hour", "name");
        assertEq(token.symbol(), "HAMSTER", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY constant");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "deployer holds everything");
        assertEq(token.balanceOf(address(this)), 0, "the test contract holds nothing");
        assertEq(token.balanceOf(address(token)), 0, "the token holds nothing");
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        HamsterHourToken fresh = new HamsterHourToken();
        assertEq(fresh.balanceOf(ALICE), SUPPLY, "whoever deploys receives the supply");
    }

    function test_supplyIsOneBillionWholeTokens() public view {
        assertEq(token.totalSupply() / (10 ** uint256(token.decimals())), 1_000_000_000, "whole tokens");
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER: SUCCESS
    //////////////////////////////////////////////////////////////*/

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_234 * 10 ** 18;

        vm.expectEmit(true, true, true, true);
        emit Transfer(DEPLOYER, ALICE, amount);
        vm.prank(DEPLOYER);
        bool ok = token.transfer(ALICE, amount);

        assertTrue(ok, "transfer returns true");
        assertEq(token.balanceOf(ALICE), amount, "receiver credited");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender debited");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferWholeBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY, "receiver holds everything");
        assertEq(token.balanceOf(DEPLOYER), 0, "sender holds nothing");
    }

    function test_transferZeroAmount() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        bool ok = token.transfer(BOB, 0);
        assertTrue(ok, "zero transfer returns true");
        assertEq(token.balanceOf(BOB), 0, "nothing moved");
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(DEPLOYER, SUPPLY / 2);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "self-transfer is a no-op");
    }

    function test_transferChainConservesSupply() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.transfer(BOB, 40 ether);
        vm.prank(BOB);
        token.transfer(DEPLOYER, 10 ether);

        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 90 ether, "deployer");
        assertEq(token.balanceOf(ALICE), 60 ether, "alice");
        assertEq(token.balanceOf(BOB), 30 ether, "bob");
        assertEq(token.balanceOf(DEPLOYER) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY, "sum of balances");
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER: FAILURE
    //////////////////////////////////////////////////////////////*/

    function test_transferRevertsOnInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, ALICE, uint256(0), uint256(1))
        );
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_transferRevertsOneUnitOverBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 5 ether);

        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, ALICE, 5 ether, 5 ether + 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 5 ether + 1);

        assertEq(token.balanceOf(ALICE), 5 ether, "failed transfer moved nothing");
        assertEq(token.balanceOf(BOB), 0, "failed transfer delivered nothing");
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(HamsterHourToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), SUPPLY, "nothing can leave circulation");
    }

    /*//////////////////////////////////////////////////////////////
                       APPROVE / TRANSFERFROM: SUCCESS
    //////////////////////////////////////////////////////////////*/

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(DEPLOYER, ALICE, 7 ether);
        vm.prank(DEPLOYER);
        bool ok = token.approve(ALICE, 7 ether);

        assertTrue(ok, "approve returns true");
        assertEq(token.allowance(DEPLOYER, ALICE), 7 ether, "allowance set");
        assertEq(token.allowance(ALICE, DEPLOYER), 0, "allowance is directional");
    }

    function test_approveReplacesEarlierAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 7 ether);
        vm.prank(DEPLOYER);
        token.approve(ALICE, 2 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), 2 ether, "second approval replaces the first");
        vm.prank(DEPLOYER);
        token.approve(ALICE, 0);
        assertEq(token.allowance(DEPLOYER, ALICE), 0, "approval can be cleared");
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10 ether);

        vm.expectEmit(true, true, true, true);
        emit Transfer(DEPLOYER, BOB, 4 ether);
        vm.prank(ALICE);
        bool ok = token.transferFrom(DEPLOYER, BOB, 4 ether);

        assertTrue(ok, "transferFrom returns true");
        assertEq(token.balanceOf(BOB), 4 ether, "receiver credited");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 4 ether, "owner debited");
        assertEq(token.balanceOf(ALICE), 0, "spender holds nothing");
        assertEq(token.allowance(DEPLOYER, ALICE), 6 ether, "allowance reduced by the amount");
    }

    function test_transferFromExactAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 3 ether);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 3 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), 0, "allowance exhausted");
        assertEq(token.balanceOf(BOB), 3 ether, "receiver credited");
    }

    function test_transferFromUnlimitedAllowanceIsNotReduced() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 9 ether);
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max, "unlimited stays unlimited");
        assertEq(token.balanceOf(BOB), 9 ether, "receiver credited");
    }

    /*//////////////////////////////////////////////////////////////
                       APPROVE / TRANSFERFROM: FAILURE
    //////////////////////////////////////////////////////////////*/

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(HamsterHourToken.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientAllowance.selector, ALICE, uint256(0), uint256(1))
        );
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "nothing moved");
    }

    function test_transferFromRevertsOverAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 2 ether);
        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientAllowance.selector, ALICE, 2 ether, 2 ether + 1)
        );
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 2 ether + 1);
        assertEq(token.allowance(DEPLOYER, ALICE), 2 ether, "allowance untouched by the failed call");
    }

    function test_transferFromRevertsWhenOwnerBalanceIsShort() public {
        vm.prank(ALICE);
        token.approve(BOB, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, ALICE, uint256(0), 5 ether)
        );
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 5 ether);
        assertEq(token.allowance(ALICE, BOB), 5 ether, "allowance untouched when the balance check fails");
    }

    function test_transferFromRevertsForZeroSender() public {
        // The zero address has no allowance for a positive amount, and a zero amount is refused
        // explicitly rather than silently emitting a mint-shaped Transfer event.
        vm.expectRevert(abi.encodeWithSelector(HamsterHourToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(address(0), BOB, 0);
    }

    function test_transferFromRevertsToZeroAddress() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(HamsterHourToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, address(0), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                       NO ADMIN, MINT OR FREEZE SURFACE
    //////////////////////////////////////////////////////////////*/

    /// @dev The common ways a supply grows after launch. None exists here: each call hits a missing
    ///      selector and reverts, whether a stranger or the deployer sends it.
    function test_noMintOrAdminSelectorExists() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ATTACKER, type(uint128).max);

            vm.prank(ATTACKER);
            (bool okFromAttacker,) = address(token).call(data);
            assertTrue(!okFromAttacker, signatures[i]);

            vm.prank(DEPLOYER);
            (bool okFromDeployer,) = address(token).call(data);
            assertTrue(!okFromDeployer, signatures[i]);

            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(ATTACKER), 0, signatures[i]);
        }
    }

    /// @dev The common ways a privileged hand moves or freezes a holder. None exists: afterwards the
    ///      holder still holds what it held and can still transfer.
    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);

        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, true);
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(data);
            assertTrue(!ok, signatures[i]);
        }

        // The deployer has no allowance either.
        vm.prank(DEPLOYER);
        (bool moved,) = address(token).call(abi.encodeWithSelector(token.transferFrom.selector, ALICE, DEPLOYER, 1));
        assertTrue(!moved, "the deployer cannot pull from a holder");

        assertEq(token.balanceOf(ALICE), held, "the holder still holds what it held");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2), "the holder can still transfer");
        assertEq(token.balanceOf(BOB), held / 2, "the holder's transfer arrived whole");
    }

    function test_noOwnerAndNoFallback() public {
        (bool hasOwner,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertTrue(!hasOwner, "no owner()");
        (bool hasPaused,) = address(token).call(abi.encodeWithSignature("paused()"));
        assertTrue(!hasPaused, "no paused()");
        (bool acceptsEmptyCall,) = address(token).call("");
        assertTrue(!acceptsEmptyCall, "no fallback or receive");
        (bool acceptsEther,) = address(token).call{value: 1 wei}("");
        assertTrue(!acceptsEther, "no payable path");
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0, "runtime present");
        assertTrue(runtime.length <= 24_576, "runtime within EIP-170");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != DEPLOYER);
        amount = amount % (SUPPLY + 1);

        vm.prank(DEPLOYER);
        bool ok = token.transfer(to, amount);

        assertTrue(ok, "transfer returns true");
        assertEq(token.balanceOf(to), amount, "receiver credited");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender debited");
        assertEq(token.balanceOf(to) + token.balanceOf(DEPLOYER), SUPPLY, "conserved");
        assertEq(token.totalSupply(), SUPPLY, "supply fixed");
    }

    function testFuzz_transferOverBalanceReverts(uint256 balance, uint256 excess) public {
        balance = balance % (SUPPLY + 1);
        excess = 1 + (excess % (type(uint256).max - SUPPLY - 1));
        uint256 needed = balance + excess;

        vm.prank(DEPLOYER);
        token.transfer(ALICE, balance);

        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, ALICE, balance, needed)
        );
        vm.prank(ALICE);
        token.transfer(BOB, needed);

        assertEq(token.balanceOf(ALICE), balance, "nothing moved");
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 amount) public {
        allowed = allowed % (SUPPLY + 1);
        amount = amount % (SUPPLY + 1);

        vm.prank(DEPLOYER);
        token.approve(ALICE, allowed);

        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientAllowance.selector, ALICE, allowed, amount)
            );
            vm.prank(ALICE);
            token.transferFrom(DEPLOYER, BOB, amount);
            assertEq(token.balanceOf(BOB), 0, "nothing moved");
            assertEq(token.allowance(DEPLOYER, ALICE), allowed, "allowance untouched");
        } else {
            vm.prank(ALICE);
            token.transferFrom(DEPLOYER, BOB, amount);
            assertEq(token.balanceOf(BOB), amount, "receiver credited");
            assertEq(token.allowance(DEPLOYER, ALICE), allowed - amount, "allowance reduced");
            assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "owner debited");
        }
    }
}
