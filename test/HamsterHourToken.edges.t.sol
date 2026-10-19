// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HamsterHourToken} from "../src/HamsterHourToken.sol";
import {TestBase} from "./utils/TestBase.sol";

/// @notice The log-recording cheatcodes, declared here because only this file uses them.
interface VmLogs {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

/// @notice Stands in for the launch factory: deploys the token in one call so the factory itself is
///         the deployer, then forwards shares exactly as the launch does.
contract FactoryStandIn {
    HamsterHourToken public token;

    function launch(bytes32 salt) external returns (HamsterHourToken deployed) {
        deployed = new HamsterHourToken{salt: salt}();
        token = deployed;
    }

    function forward(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @notice Edges and orderings the main suite does not pin: who is checked first when several
///         things are wrong, the exact boundary of an "unlimited" allowance, spending one's own
///         allowance, zero-amount calls, the launch flows moving exact amounts, and fuzzed properties.
contract HamsterHourTokenEdgesTest is TestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);

    VmLogs internal constant vmLogs = VmLogs(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    bytes32 internal constant APPROVAL_TOPIC = keccak256("Approval(address,address,uint256)");
    bytes32 internal constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");

    address internal constant DEPLOYER = address(0xDE91);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    HamsterHourToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new HamsterHourToken();
    }

    /*//////////////////////////////////////////////////////////////
                              ERROR ORDER
    //////////////////////////////////////////////////////////////*/

    function test_transferToZeroOverBalanceReportsReceiverFirst() public {
        vm.expectRevert(abi.encodeWithSelector(HamsterHourToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transfer(address(0), 1);
    }

    function test_transferFromChecksAllowanceBeforeReceiver() public {
        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientAllowance.selector, ALICE, uint256(0), uint256(5))
        );
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, address(0), 5);
    }

    function test_transferFromChecksAllowanceBeforeZeroSender() public {
        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientAllowance.selector, ALICE, uint256(0), uint256(1))
        );
        vm.prank(ALICE);
        token.transferFrom(address(0), BOB, 1);
    }

    function test_transferMaxUintRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                HamsterHourToken.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max
            )
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                               ALLOWANCES
    //////////////////////////////////////////////////////////////*/

    function test_allowanceJustBelowMaxIsSpent() public {
        uint256 almost = type(uint256).max - 1;
        vm.prank(DEPLOYER);
        token.approve(ALICE, almost);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 7);
        assertEq(token.allowance(DEPLOYER, ALICE), almost - 7, "only exactly max is unlimited");
    }

    function test_unlimitedAllowanceSurvivesFullSupplyPull() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, SUPPLY);
        assertEq(token.balanceOf(BOB), SUPPLY, "whole supply pulled");
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max, "unlimited stays unlimited");

        vm.expectRevert(
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, DEPLOYER, uint256(0), uint256(1))
        );
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
    }

    function test_ownerNeedsAllowanceToTransferFromItself() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                HamsterHourToken.ERC20InsufficientAllowance.selector, DEPLOYER, uint256(0), uint256(1)
            )
        );
        vm.prank(DEPLOYER);
        token.transferFrom(DEPLOYER, ALICE, 1);

        vm.prank(DEPLOYER);
        token.approve(DEPLOYER, 3);
        vm.prank(DEPLOYER);
        token.transferFrom(DEPLOYER, ALICE, 3);
        assertEq(token.balanceOf(ALICE), 3, "self-allowance spent");
        assertEq(token.allowance(DEPLOYER, DEPLOYER), 0, "self-allowance exhausted");
    }

    function test_transferFromToOwnerSpendsAllowanceButKeepsBalance() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, DEPLOYER, 4);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "balance unchanged");
        assertEq(token.allowance(DEPLOYER, ALICE), 6, "allowance still spent");
    }

    function test_zeroAmountTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(DEPLOYER, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 0), "zero transferFrom returns true");
        assertEq(token.allowance(DEPLOYER, ALICE), 0, "no allowance appeared");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "nothing moved");
    }

    function test_approvalNeedsNoBalance() public {
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "approval is independent of balance");
    }

    /// @dev transferFrom emits exactly one event, a Transfer: the allowance change is not announced
    ///      with an Approval (the same choice OpenZeppelin v5 makes).
    function test_transferFromEmitsOnlyTransfer() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10);

        vmLogs.recordLogs();
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 4);
        VmLogs.Log[] memory logs = vmLogs.getRecordedLogs();

        assertEq(logs.length, 1, "one event");
        assertEq(logs[0].emitter, address(token), "from the token");
        assertTrue(logs[0].topics[0] == TRANSFER_TOPIC, "it is a Transfer");
        assertTrue(logs[0].topics[0] != APPROVAL_TOPIC, "not an Approval");
        assertEq(abi.decode(logs[0].data, (uint256)), 4, "amount");
    }

    /// @dev A reverted call leaves no event behind and changes nothing.
    function test_failedCallsEmitNothing() public {
        vmLogs.recordLogs();
        (bool ok,) = address(token).call(abi.encodeCall(HamsterHourToken.transfer, (address(0), 1)));
        assertTrue(!ok, "transfer to zero failed");
        (ok,) = address(token).call(abi.encodeCall(HamsterHourToken.approve, (address(0), 1)));
        assertTrue(!ok, "approve of zero failed");
        assertEq(vmLogs.getRecordedLogs().length, 0, "no event from a reverted call");
    }

    /*//////////////////////////////////////////////////////////////
                              LAUNCH FLOWS
    //////////////////////////////////////////////////////////////*/

    /// @dev The factory deploys and holds the supply, forwards ten percent to the distributor, which
    ///      pays it out whole, and the pool share leaves whole: no flow arrives short.
    function test_launchFlowsMoveExactAmounts() public {
        FactoryStandIn factory = new FactoryStandIn();
        HamsterHourToken launched = factory.launch(bytes32(uint256(42)));

        assertEq(launched.balanceOf(address(factory)), SUPPLY, "the factory holds the whole supply");

        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        address claimant = address(0xC1A1);
        uint256 swarm = SUPPLY / 10;
        uint256 pool = (SUPPLY * 6_000) / 10_000;

        assertTrue(factory.forward(distributor, swarm), "forward to distributor");
        assertEq(launched.balanceOf(distributor), swarm, "the swarm's share arrived whole");

        vm.prank(distributor);
        assertTrue(launched.transfer(claimant, swarm), "claim");
        assertEq(launched.balanceOf(claimant), swarm, "the claim arrived whole");
        assertEq(launched.balanceOf(distributor), 0, "the distributor kept nothing");

        assertTrue(factory.forward(poolManager, pool), "forward to pool manager");
        assertEq(launched.balanceOf(poolManager), pool, "the pool share arrived whole");

        vm.prank(poolManager);
        launched.transfer(BOB, 1 ether);
        assertEq(launched.balanceOf(BOB), 1 ether, "a buy out of the pool arrives whole");

        assertEq(launched.balanceOf(address(factory)), SUPPLY - swarm - pool, "the factory keeps the rest");
        assertEq(launched.totalSupply(), SUPPLY, "the flows changed nothing about the supply");
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveStoresAnyValue(address owner, address spender, uint256 amount) public {
        spender = spender == address(0) ? BOB : spender;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returns true");
        assertEq(token.allowance(owner, spender), amount, "stored exactly");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_unlimitedAllowanceNeverDecreases(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, a);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, b);
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max, "unlimited");
        assertEq(token.balanceOf(BOB), a + b, "received both");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_selfTransferNeverChangesBalance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);

        if (amount > held) {
            vm.expectRevert(
                abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, ALICE, held, amount)
            );
            vm.prank(ALICE);
            token.transfer(ALICE, amount);
        } else {
            vm.prank(ALICE);
            token.transfer(ALICE, amount);
        }
        assertEq(token.balanceOf(ALICE), held, "self-transfer is a no-op either way");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromChecksBalanceAfterAllowance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, type(uint256).max);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(BOB, amount);

        vm.expectRevert(abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, BOB), amount, "the failed call spent no allowance");
        assertEq(token.balanceOf(ALICE), held, "nothing moved");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_whoeverDeploysReceivesTheSupply(address deployer) public {
        vm.prank(deployer);
        HamsterHourToken fresh = new HamsterHourToken();
        assertEq(fresh.balanceOf(deployer), SUPPLY, "deployer receives everything");
        assertEq(fresh.totalSupply(), SUPPLY, "fixed supply");
    }
}
