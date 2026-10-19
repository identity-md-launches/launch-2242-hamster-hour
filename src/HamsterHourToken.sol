// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Hamster Hour (HAMSTER)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 HAMSTER (18 decimals) is minted
///         once, in the constructor, to the deployer. Nothing can mint afterwards, there is no owner,
///         no pause, no blocklist, no fee and no burn: every unit is an ordinary, freely transferable
///         ERC-20 balance for as long as the chain exists.
/// @dev Self-contained: no inherited library, no external call, no delegatecall, no selfdestruct.
///      Errors follow ERC-6093 so wallets and indexers decode them the same way they decode
///      OpenZeppelin's. Balances are conserved by construction: the only writes to `_balances`
///      move `value` from one account to another, so their sum is always `TOTAL_SUPPLY`.
contract HamsterHourToken {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when `value` units move from `from` to `to`. The mint emits it with `from` zero.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when `owner` sets `spender`'s allowance to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice `sender` holds `balance` but the transfer needs `needed`.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @notice A transfer from the zero address was attempted.
    error ERC20InvalidSender(address sender);

    /// @notice A transfer to the zero address was attempted. There is no burn: nothing may leave circulation.
    error ERC20InvalidReceiver(address receiver);

    /// @notice `spender` is allowed `allowance` but the transfer needs `needed`.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @notice An approval of the zero address was attempted.
    error ERC20InvalidSpender(address spender);

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    string private constant _NAME = "Hamster Hour";
    string private constant _SYMBOL = "HAMSTER";
    uint8 private constant _DECIMALS = 18;

    /// @notice The fixed supply in minor units: 1,000,000,000 tokens at 18 decimals, 1e27.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address account => uint256) private _balances;
    mapping(address account => mapping(address spender => uint256)) private _allowances;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints the whole supply to the deployer. No arguments: on the launch, the deployer is
    ///         the factory, which then distributes the supply as the launch manifest says.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice The token's name.
    function name() external pure returns (string memory) {
        return _NAME;
    }

    /// @notice The token's symbol.
    function symbol() external pure returns (string memory) {
        return _SYMBOL;
    }

    /// @notice The number of decimals, 18.
    function decimals() external pure returns (uint8) {
        return _DECIMALS;
    }

    /// @notice The supply, which never changes after the constructor.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice `account`'s balance.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice What `spender` may still move out of `owner`'s balance.
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    /*//////////////////////////////////////////////////////////////
                                 ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Moves `value` from the caller to `to`.
    /// @dev Reverts with `ERC20InvalidReceiver` for the zero address and `ERC20InsufficientBalance` when
    ///      the caller holds less than `value`. Always returns true.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Sets `spender`'s allowance over the caller's balance to `value`, replacing any earlier one.
    /// @dev Reverts with `ERC20InvalidSpender` for the zero address. Always returns true.
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @notice Moves `value` from `from` to `to` using the caller's allowance.
    /// @dev An allowance of `type(uint256).max` is treated as unlimited and is not decreased. Reverts
    ///      with `ERC20InsufficientAllowance` when the allowance is short, then as `transfer` does.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) {
            revert ERC20InsufficientBalance(from, fromBalance, value);
        }
        unchecked {
            // `value <= fromBalance`, and the sum of all balances is `TOTAL_SUPPLY < 2**256`,
            // so neither side can wrap.
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) private {
        uint256 current = _allowances[owner][spender];
        if (current != type(uint256).max) {
            if (current < value) {
                revert ERC20InsufficientAllowance(spender, current, value);
            }
            unchecked {
                _allowances[owner][spender] = current - value;
            }
        }
    }
}
