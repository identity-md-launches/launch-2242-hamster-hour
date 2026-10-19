// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {HamsterHourToken} from "../src/HamsterHourToken.sol";
import {TestBase} from "./utils/TestBase.sol";

/// @notice Drives the token with random sequences of transfers, approvals and transferFroms between a
///         fixed set of actors, on both the success and the failure paths. Every call is checked as it
///         happens (exact balance and allowance movement, exact revert data, nothing moved by a
///         revert), and ghost copies of every balance and allowance are kept for the invariants.
contract HamsterHourHandler is TestBase {
    HamsterHourToken public immutable token;
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address[] internal actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    /// @notice How many calls of each kind went through, so a run that exercised nothing is visible.
    mapping(bytes32 => uint256) public calls;

    constructor(HamsterHourToken token_, address deployer, address[] memory others) {
        token = token_;
        actors.push(deployer);
        for (uint256 i = 0; i < others.length; i++) {
            actors.push(others[i]);
        }
        // The token's own address can receive (and, as an address, send) like any other.
        actors.push(address(token_));
        ghostBalance[deployer] = SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Biases amounts toward the edges: zero, one, the whole balance, and anything in between.
    function _amountUpTo(uint256 seed, uint256 max) internal pure returns (uint256) {
        uint256 pick = seed % 8;
        if (pick == 0) return 0;
        if (pick == 1) return max == 0 ? 0 : 1;
        if (pick == 2) return max;
        return bound(seed, 0, max);
    }

    /*//////////////////////////////////////////////////////////////
                                SUCCESS
    //////////////////////////////////////////////////////////////*/

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = _amountUpTo(amountSeed, fromBefore);

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "transfer returned false");

        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore, "self-transfer changed the balance");
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount, "sender not debited exactly");
            assertEq(token.balanceOf(to), toBefore + amount, "receiver not credited exactly");
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
        }
        calls["transfer"]++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (amount % 5 == 0) amount = type(uint256).max;

        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        assertTrue(ok, "approve returned false");
        assertEq(token.allowance(owner, spender), amount, "allowance not set exactly");
        ghostAllowance[owner][spender] = amount;
        calls["approve"]++;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(from, spender);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 cap = allowed < fromBefore ? allowed : fromBefore;
        uint256 amount = _amountUpTo(amountSeed, cap);

        vm.prank(spender);
        bool ok = token.transferFrom(from, to, amount);
        assertTrue(ok, "transferFrom returned false");

        if (allowed == type(uint256).max) {
            assertEq(token.allowance(from, spender), allowed, "unlimited allowance was spent");
        } else {
            assertEq(token.allowance(from, spender), allowed - amount, "allowance not spent exactly");
            ghostAllowance[from][spender] = allowed - amount;
        }
        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore, "self-transferFrom changed the balance");
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount, "owner not debited exactly");
            assertEq(token.balanceOf(to), toBefore + amount, "receiver not credited exactly");
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
        }
        calls["transferFrom"]++;
    }

    /*//////////////////////////////////////////////////////////////
                                FAILURE
    //////////////////////////////////////////////////////////////*/

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = token.balanceOf(from);
        uint256 amount = balance + bound(excessSeed, 1, type(uint256).max - balance);
        bytes memory expected =
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, from, balance, amount);

        _expectRevert(from, abi.encodeCall(HamsterHourToken.transfer, (to, amount)), expected);
        calls["transferOverBalance"]++;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        bytes memory expected = abi.encodeWithSelector(HamsterHourToken.ERC20InvalidReceiver.selector, address(0));

        _expectRevert(from, abi.encodeCall(HamsterHourToken.transfer, (address(0), amount)), expected);
        calls["transferToZero"]++;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        bytes memory expected = abi.encodeWithSelector(HamsterHourToken.ERC20InvalidSpender.selector, address(0));

        _expectRevert(owner, abi.encodeCall(HamsterHourToken.approve, (address(0), amount)), expected);
        calls["approveZeroSpender"]++;
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excessSeed)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(from, spender);
        if (allowed == type(uint256).max) return; // unlimited: nothing exceeds it
        uint256 amount = allowed + bound(excessSeed, 1, type(uint256).max - allowed);
        bytes memory expected =
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientAllowance.selector, spender, allowed, amount);

        _expectRevert(spender, abi.encodeCall(HamsterHourToken.transferFrom, (from, to, amount)), expected);
        calls["transferFromOverAllowance"]++;
    }

    /// @dev The allowance covers the amount but the owner's balance does not: the balance check must
    ///      refuse it, and the allowance must survive the failed call untouched.
    function transferFromOverBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excessSeed)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = token.balanceOf(from);
        uint256 amount = balance + bound(excessSeed, 1, SUPPLY);

        if (token.allowance(from, spender) < amount) {
            vm.prank(from);
            token.approve(spender, amount);
            ghostAllowance[from][spender] = amount;
        }
        bytes memory expected =
            abi.encodeWithSelector(HamsterHourToken.ERC20InsufficientBalance.selector, from, balance, amount);

        _expectRevert(spender, abi.encodeCall(HamsterHourToken.transferFrom, (from, to, amount)), expected);
        calls["transferFromOverBalance"]++;
    }

    /// @dev Sends `data` from `caller`, requires it to revert with exactly `expected`, and requires
    ///      every balance and the caller's relevant allowances to be what they were.
    function _expectRevert(address caller, bytes memory data, bytes memory expected) internal {
        uint256[] memory before = _balances();

        vm.prank(caller);
        (bool ok, bytes memory reason) = address(token).call(data);
        assertTrue(!ok, "a call that must fail succeeded");
        assertEq(reason, expected, "wrong revert data");

        uint256[] memory afterwards = _balances();
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(afterwards[i], before[i], "a reverted call moved a balance");
        }
    }

    function _balances() internal view returns (uint256[] memory out) {
        out = new uint256[](actors.length);
        for (uint256 i = 0; i < actors.length; i++) {
            out[i] = token.balanceOf(actors[i]);
        }
    }
}

/// @notice Invariants over random call sequences driven by `HamsterHourHandler`.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract HamsterHourTokenInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant DEPLOYER = address(0xDE91);
    address internal constant OUTSIDER = address(0x0B5E7);

    HamsterHourToken internal token;
    HamsterHourHandler internal handler;
    address[] internal targets;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new HamsterHourToken();

        address[] memory others = new address[](4);
        others[0] = address(0xA11CE);
        others[1] = address(0xB0B);
        others[2] = address(0xCA41);
        others[3] = address(0xD0D0);
        handler = new HamsterHourHandler(token, DEPLOYER, others);
        targets.push(address(handler));
    }

    /// @dev Read by forge's invariant runner: only the handler is called at random.
    function targetContracts() public view returns (address[] memory) {
        return targets;
    }

    function invariant_supplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY, "totalSupply changed");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY changed");
    }

    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            sum += token.balanceOf(handler.actorAt(i));
        }
        assertEq(sum, SUPPLY, "the actors' balances no longer sum to the supply");
        assertEq(token.balanceOf(address(0)), 0, "the zero address holds tokens");
        assertEq(token.balanceOf(OUTSIDER), 0, "an address nobody paid holds tokens");
        assertEq(token.balanceOf(address(handler)), 0, "the handler holds tokens");
    }

    function invariant_balancesMatchGhosts() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            address a = handler.actorAt(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a), "a balance drifted from its ledger");
        }
    }

    function invariant_allowancesMatchGhosts() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            address owner = handler.actorAt(i);
            for (uint256 j = 0; j < n; j++) {
                address spender = handler.actorAt(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.ghostAllowance(owner, spender),
                    "an allowance drifted from its ledger"
                );
            }
            assertEq(token.allowance(owner, OUTSIDER), 0, "an allowance nobody granted exists");
        }
    }

    function invariant_metadataAndEtherFixed() public view {
        assertEq(token.name(), "Hamster Hour", "name");
        assertEq(token.symbol(), "HAMSTER", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
        assertEq(address(token).balance, 0, "the token holds ether");
    }
}
