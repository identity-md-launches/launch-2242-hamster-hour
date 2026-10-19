// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The Foundry cheatcodes these tests use, declared directly so the project vendors nothing.
///         The signatures are Foundry's own; the address is the cheatcode address every forge
///         version answers at.
interface Vm {
    function prank(address msgSender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function assume(bool condition) external pure;
}

/// @notice A minimal test base: the cheatcode handle and assertions that fail the test by reverting
///         with the given message.
abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool condition, string memory err) internal pure {
        if (!condition) {
            revert(err);
        }
    }

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        if (a != b) {
            revert(err);
        }
    }

    function assertEq(address a, address b, string memory err) internal pure {
        if (a != b) {
            revert(err);
        }
    }

    function assertEq(string memory a, string memory b, string memory err) internal pure {
        if (keccak256(bytes(a)) != keccak256(bytes(b))) {
            revert(err);
        }
    }
}
