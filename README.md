# Hamster Hour (HAMSTER)

A fixed-supply ERC-20 token for the IdentityMD custom-token launch on Ethereum.

| Property | Value |
| --- | --- |
| Name | Hamster Hour |
| Symbol | HAMSTER |
| Decimals | 18 |
| Total supply | 1,000,000,000 HAMSTER = `1000000000000000000000000000` minor units (1e27) |
| Solidity contract | `HamsterHourToken` in `src/HamsterHourToken.sol` |
| Constructor arguments | none |
| Compiler | solc 0.8.26, optimizer on (200 runs), EVM version cancun, `bytecode_hash = "none"` |

The whole supply is minted once, in the constructor, to `msg.sender`. Nothing can mint afterwards.

## What the token does

- Standard ERC-20: `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `allowance`, `transfer`,
  `approve`, `transferFrom`, with the `Transfer` and `Approval` events.
- `transfer` and `transferFrom` always return `true` on success and revert otherwise.
- An allowance of `type(uint256).max` is unlimited and is not decreased on use.
- Reverts use ERC-6093 custom errors: `ERC20InsufficientBalance`, `ERC20InsufficientAllowance`,
  `ERC20InvalidSender`, `ERC20InvalidReceiver`, `ERC20InvalidSpender`.

## What the token does not do

- No owner, no admin role, no pause, no blocklist, no freeze, no seize, no upgrade path.
- No mint after the constructor. `totalSupply()` is a compile-time constant.
- No burn. Transfers to the zero address revert, so the supply never shrinks either.
- No fee, tax or reflection on transfer: every flow moves exactly the amount it says.
- No external calls, no `delegatecall`, no `selfdestruct`, no fallback and no `receive`. The contract
  cannot hold ETH.
- No inherited library. The contract is self-contained, so there is nothing to vendor and no linked
  library in the bytecode.

Because there is no privileged role, the token needs no key after deployment and nobody, including
the deployer, can interfere with a holder's balance.

## Launch parameters

These are decided by the launch and are listed here for reference; they are not set in the contract.

| Parameter | Value |
| --- | --- |
| Chain | Ethereum, chain id 1 |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Pool fee | 12500 (1.25%) |
| Tick spacing | 60 |
| Pool share | 80% of the supply (`poolBps` 8000) |
| Opening market cap | 4,500 IMD for the whole supply (`initialMarketCapWei` 4500000000000000000000) |
| Remainder recipient | `0x18e0a43cb0236c3e2e6f6f229fc2ca36299a4636` |
| Swarm share | 10% of the supply, taken by the factory to the launch's MerkleDistributor |

The manifest (`launch.json`) is written by the manifest step after this work is accepted, not by this
repository. Its token entry is: contract `HamsterHourToken`, name `Hamster Hour`, symbol `HAMSTER`,
decimals 18, constructorArgs `[]`, totalSupply `1000000000000000000000000000`.

## Deployment

The IdentityMD factory deploys the token through `ProjectFactory.launchCustom` from the bytecode as
built with this `foundry.toml`. The constructor takes no arguments and mints the supply to the factory
(`msg.sender`), which then forwards the swarm's share to the distributor, seeds the Uniswap v4 pool
with 80% of the supply, and sends the remaining 10% to the remainder recipient above.

There is no deploy script and no transaction to sign in this repository. If the token is ever
deployed elsewhere by hand, whoever sends the creation transaction receives the full supply:

```sh
forge create src/HamsterHourToken.sol:HamsterHourToken --rpc-url <rpc> --private-key <key>
```

## After launch

Nothing to configure. The token has no settable values, no owner and no post-deployment step.

## Operational responsibilities

- **Requester**: custody of the wallet at the remainder recipient address, which receives 10% of the
  supply at launch. Lost keys for that wallet cannot be recovered by anyone; the token has no
  recovery path.
- **IMD deployer and launch policy**: deploying through the factory, seeding the pool, and source
  verification on the block explorer (`forge verify-contract`) after deployment.
- **Holders**: approvals are the only way another address can move a holder's tokens. Approve exact
  amounts where possible; an unlimited approval stays in force until the holder changes it.

## Assumptions

- The requester wants a plain token: the brief asks for a name, a symbol and a one-time mint of the
  full supply to the deployer, and nothing else. No burn, tax, vesting or governance feature was
  requested, so none is included.
- The deployer at launch is the factory, as the launch defines. The constructor does not take or
  check launch addresses because the token exempts nobody from anything: there is no fee to exempt
  from.
- 18 decimals and a supply of one billion whole tokens are the brief's numbers; nothing else in the
  token is a chosen constant.

## Security notes

Checked against the eth-security checklist:

- Access control: there are no privileged functions.
- Reentrancy: the contract makes no external calls.
- Decimals and integer math: the only arithmetic is balance and allowance bookkeeping, guarded by
  explicit checks before the unchecked subtraction; the supply is below 2^256, so additions cannot
  wrap.
- Input validation: zero-address receivers, senders and spenders are rejected.
- Events: every balance and allowance change emits an event.
- Proxies, delegatecall, oracles, swaps and signatures: not used.
- The test `test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct` scans the runtime bytecode for
  `DELEGATECALL`, `CALLCODE` and `SELFDESTRUCT`.

Passing tests are not an audit. The launch policy's independent review covers the token before it
is deployed.

## Tests

`test/HamsterHourToken.t.sol` covers:

- Success paths: metadata, the one-time mint and its `Transfer` event, transfers (ordinary, whole
  balance, zero amount, self, chained) with conservation of the supply, approvals (set, replace,
  clear), `transferFrom` with partial, exact and unlimited allowances.
- Failure paths: transfer over balance (by zero and by one unit), transfer to the zero address,
  approval of the zero spender, `transferFrom` without, over and beyond the owner's balance,
  `transferFrom` from or to the zero address.
- No admin surface: ten mint and ownership selectors and twelve pause, blocklist, freeze and seize
  selectors all revert from a stranger and from the deployer, the deployer cannot pull from a
  holder, there is no `owner()`, no fallback and no payable path, and the runtime bytecode contains
  no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.
- Fuzz: transfers of any amount up to the supply to any address conserve the supply; transfers
  over the balance revert with the exact error; `transferFrom` succeeds or fails exactly at the
  allowance boundary.

The tests talk to Foundry's cheatcode address through a small interface in `test/utils/TestBase.sol`
rather than through forge-std, so the project has no dependencies at all. They read no environment
variables and do not depend on the caller's address, so they pass in any order and in parallel.

```sh
forge build
forge test
forge fmt --check
```
