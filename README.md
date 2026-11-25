# Damn Vulnerable DeFi v4 — Security Writeups & Solutions

![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C?style=flat-square&logo=ethereum)
![Solidity](https://img.shields.io/badge/Solidity-0.8.25-363636?style=flat-square&logo=solidity)
![Progress](https://img.shields.io/badge/Solved-17%20Challenges-2ea44f?style=flat-square)

Detailed vulnerability writeups, audit methodologies, mitigations, and full Foundry test solutions for **[Damn Vulnerable DeFi v4](https://www.damnvulnerabledefi.xyz/)**.

> **Repository Scope:** This repository contains my Foundry `test/` suites (including helper contracts and fixture JSONs) alongside a structured security breakdown for each solved challenge — covering **challenge description**, **how to spot the bug during an audit**, **root cause mechanics**, **solution walkthrough**, and **code-level mitigations**.  
> *(Note: Challenge #13 `Wallet Mining` is omitted until completed.)*

---

## Repository Structure

```text
damn-vulnerable-defi-v4-solutions/
├── README.md                  # Master audit writeups, mitigation patterns & challenge index
└── test/                      # Complete Foundry solution tests & required fixture data
    ├── unstoppable/           # Unstoppable.t.sol + LoanReceiver.t.sol
    ├── naive-receiver/        # NaiveReceiver.t.sol
    ├── truster/               # Truster.t.sol
    ├── side-entrance/         # SideEntrance.t.sol
    ├── the-rewarder/          # TheRewarder.t.sol + DVT/WETH Merkle distribution JSONs
    ├── selfie/                # Selfie.t.sol
    ├── compromised/           # Compromised.t.sol
    ├── puppet/                # Puppet.t.sol
    ├── puppet-v2/             # PuppetV2.t.sol
    ├── free-rider/            # FreeRider.t.sol
    ├── backdoor/              # Backdoor.t.sol
    ├── climber/               # Climber.t.sol
    ├── puppet-v3/             # PuppetV3.t.sol
    ├── abi-smuggling/         # ABISmuggling.t.sol
    ├── shards/                # Shards.t.sol
    ├── curvy-puppet/          # CurvyPuppet.t.sol
    └── withdrawal/            # Withdrawal.t.sol + withdrawals.json
```

---

## Challenge Index

| # | Challenge | Core Vulnerability | Primary Mechanism | Solution |
| :-: | :--- | :--- | :--- | :--- |
| 1 | [Unstoppable](#1-unstoppable) | Strict Balance Equality DoS | ERC-4626 `totalSupply` vs `balanceOf` mismatch | [Unstoppable.t.sol](./test/unstoppable/Unstoppable.t.sol) |
| 2 | [Naive Receiver](#2-naive-receiver) | Missing Initiator Check & Meta-Tx Spoofing | Unchecked `onFlashLoan` + ERC-2771 `Multicall` | [NaiveReceiver.t.sol](./test/naive-receiver/NaiveReceiver.t.sol) |
| 3 | [Truster](#3-truster) | Arbitrary External Call | `target.functionCall(data)` on token contract | [Truster.t.sol](./test/truster/Truster.t.sol) |
| 4 | [Side Entrance](#4-side-entrance) | Cross-Function Accounting Mismatch | Repaying flash loan via `deposit()` | [SideEntrance.t.sol](./test/side-entrance/SideEntrance.t.sol) |
| 5 | [The Rewarder](#5-the-rewarder) | Deferred Bitmap State Update | Reusing identical Merkle claim within a batch | [TheRewarder.t.sol](./test/the-rewarder/TheRewarder.t.sol) |
| 6 | [Selfie](#6-selfie) | Live Vote Balance Governance | Flash-loaned ERC20Votes voting power | [Selfie.t.sol](./test/selfie/Selfie.t.sol) |
| 7 | [Compromised](#7-compromised) | Leaked Oracle Signer Keys | 2-of-3 median price oracle manipulation | [Compromised.t.sol](./test/compromised/Compromised.t.sol) |
| 8 | [Puppet](#8-puppet) | AMM Spot Price Oracle | Thin Uniswap V1 reserve skew | [Puppet.t.sol](./test/puppet/Puppet.t.sol) |
| 9 | [Puppet V2](#9-puppet-v2) | AMM Spot Reserve Quote | Uniswap V2 `getReserves()` single-tx manipulation | [PuppetV2.t.sol](./test/puppet-v2/PuppetV2.t.sol) |
| 10 | [Free Rider](#10-free-rider) | Loop `msg.value` Reuse & Payment Order | Buying multiple NFTs with 1x payment + paying buyer | [FreeRider.t.sol](./test/free-rider/FreeRider.t.sol) |
| 11 | [Backdoor](#11-backdoor) | Pre-Callback Setup `delegatecall` | Safe `setup()` module approval before registry check | [Backdoor.t.sol](./test/backdoor/Backdoor.t.sol) |
| 12 | [Climber](#12-climber) | CEI Violation in Timelock | `execute()` runs calls before state verification | [Climber.t.sol](./test/climber/Climber.t.sol) |
| 14 | [Puppet V3](#14-puppet-v3) | Thin Concentrated Liquidity TWAP | Pushing narrow Uniswap V3 pool out of tick range | [PuppetV3.t.sol](./test/puppet-v3/PuppetV3.t.sol) |
| 15 | [ABI Smuggling](#15-abi-smuggling) | Hardcoded Calldata Offset | Dynamic ABI pointer vs fixed `calldataload` offset | [ABISmuggling.t.sol](./test/abi-smuggling/ABISmuggling.t.sol) |
| 16 | [Shards](#16-shards) | Precision Truncation & Formula Mismatch | Rounding down to 0 on fill + inflated cancel refund | [Shards.t.sol](./test/shards/Shards.t.sol) |
| 17 | [Curvy Puppet](#17-curvy-puppet) | Curve Read-Only Reentrancy | `get_virtual_price()` inflated mid-`remove_liquidity` | [CurvyPuppet.t.sol](./test/curvy-puppet/CurvyPuppet.t.sol) |
| 18 | [Withdrawal](#18-withdrawal) | Bridge Failure Catching & Operator Trust | Catching failed calls in `L1Forwarder` + `totalDeposits` | [Withdrawal.t.sol](./test/withdrawal/Withdrawal.t.sol) |

---

## Detailed Security Writeups

### 1. Unstoppable

> **Solution:** [Unstoppable.t.sol](./test/unstoppable/Unstoppable.t.sol) & [LoanReceiver.t.sol](./test/unstoppable/LoanReceiver.t.sol)

#### 📋 Description
`UnstoppableVault` is an ERC-4626 tokenized vault holding **1,000,000 DVT** that offers zero-fee flash loans during a 30-day grace period. An `UnstoppableMonitor` contract periodically tests flash loan liveness via `checkFlashLoan()` and pauses the vault if it reverts. Starting with **10 DVT**, halt the vault's flash loan functionality so the monitor pauses the vault.

#### 🔍 How to Find It
- Look for any **strict equality (`==` or `!=`)** invariant involving live token balances (`token.balanceOf(address(this))` or `address(this).balance`).
- Notice `totalAssets()` reads `asset.balanceOf(address(this))`, whereas `totalSupply` only changes when users mint/deposit/burn/withdraw through vault functions. Anyone can send ERC-20 tokens directly via `transfer()`, bypassing vault accounting.

#### ⚠️ Vulnerability (Root Cause)
Inside `UnstoppableVault.flashLoan()`:
```solidity
uint256 balanceBefore = totalAssets();
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();
```
Sending even 1 wei of DVT directly to the vault raises `balanceBefore` without minting shares (`totalSupply`), permanently breaking `convertToShares(totalSupply) == balanceBefore` and triggering a denial-of-service (`InvalidBalance()`) on all future flash loans.

#### 💡 Solution Walkthrough
1. In `test_unstoppable()`, transfer `1e18` DVT directly to `address(vault)` using `token.transfer(address(vault), 1e18)`.
2. When `_isSolved()` runs `monitorContract.checkFlashLoan(100e18)`, `flashLoan()` reverts on `InvalidBalance()`, causing the monitor to emit `FlashLoanStatus(false)`, call `vault.setPause(true)`, and return ownership to `deployer`.

#### 🛡️ Mitigation
Never rely on strict equality between internal share accounting and `asset.balanceOf(address(this))`, or track vault-managed reserves in an explicit state variable instead of raw ERC-20 balance lookups.
```solidity
// Safe pattern: track accounted reserves separately or check `balanceBefore >= expected`
```

[↑ Back to Index](#challenge-index)

---

### 2. Naive Receiver

> **Solution:** [NaiveReceiver.t.sol](./test/naive-receiver/NaiveReceiver.t.sol)

#### 📋 Description
`NaiveReceiverPool` holds **1,000 WETH**, charges a flat **1 WETH** flash loan fee (even for 0-amount loans), and supports EIP-2771 meta-transactions via `BasicForwarder` alongside `Multicall`. A `FlashLoanReceiver` contract holds **10 WETH**. Rescue all **1,010 WETH** into `recovery` in at most 2 transactions.

#### 🔍 How to Find It
- Check flash loan receivers for **caller and initiator validation**: `onFlashLoan()` must verify *who* started the flash loan, not just that `msg.sender` is the pool.
- Check contracts inheriting **both `ERC2771Context` / custom `_msgSender()` suffix parsing and `Multicall`**: `multicall` uses `delegatecall`, preserving `msg.sender == trustedForwarder` while running arbitrary inner calldata payloads whose trailing 20 bytes can be controlled by the caller.

#### ⚠️ Vulnerability (Root Cause)
1. **Unprotected Flash Loan Receiver:** `FlashLoanReceiver.onFlashLoan()` checks `msg.sender == pool` but ignores `initiator`, allowing any external caller to force `receiver` to borrow `0 WETH` ten times and bleed `10 WETH` in fixed fees into `deployer`'s pool deposit balance.
2. **EIP-2771 + Multicall Sender Spoofing:** In `NaiveReceiverPool._msgSender()`:
   ```solidity
   if (msg.sender == trustedForwarder && msg.data.length >= 20) {
       return address(bytes20(msg.data[msg.data.length - 20:]));
   }
   ```
   When `BasicForwarder` invokes `pool.multicall(callDatas)`, each subcall executes via `delegatecall`, keeping `msg.sender == address(forwarder)` while inspecting the trailing 20 bytes of each subcall's `msg.data` — letting an attacker spoof `deployer` inside `withdraw()`.

#### 💡 Solution Walkthrough
1. Build an 11-element `bytes[] memory callDatas` array in `test_naiveReceiver()`:
   - Entries `0..9`: `abi.encodeCall(NaiveReceiverPool.flashLoan, (receiver, address(weth), 0, "0x"))` to move `10 WETH` from `receiver` to `deployer`'s pool accounting.
   - Entry `10`: `abi.encodePacked(abi.encodeCall(NaiveReceiverPool.withdraw, (1010e18, payable(recovery))), bytes32(uint256(uint160(deployer))))` so `_msgSender()` reads `deployer` from the trailing 20 bytes and withdraws the full `1,010 WETH` to `recovery`.
2. Encode as `pool.multicall(callDatas)`, sign an EIP-712 `BasicForwarder.Request` using `playerPk`, and execute via `forwarder.execute(request, signature)`.

#### 🛡️ Mitigation
- Always verify `initiator == expectedOwner` inside `onFlashLoan()`.
- Never combine raw `msg.data` suffix `_msgSender()` parsing with `Multicall` `delegatecall`s without stripping/forwarding the verified sender per subcall (such as OpenZeppelin's `ERC2771Context` compatibility fixes).

[↑ Back to Index](#challenge-index)

---

### 3. Truster

> **Solution:** [Truster.t.sol](./test/truster/Truster.t.sol)

#### 📋 Description
`TrusterLenderPool` holds **1,000,000 DVT** and offers free flash loans. Starting with zero tokens, rescue all pool funds into `recovery` in a single transaction.

#### 🔍 How to Find It
- Spot generic `address target, bytes calldata data` parameters passed straight into `target.functionCall(data)` or `.call(data)` inside a contract holding tokens or privileges.
- Ask: *"What happens if `target` is the pool's own ERC-20 token contract?"*

#### ⚠️ Vulnerability (Root Cause)
`TrusterLenderPool.flashLoan()` executes:
```solidity
token.transfer(borrower, amount);
target.functionCall(data);
if (token.balanceOf(address(this)) < balanceBefore) revert RepayFailed();
```
Because `target` is unconstrained, a caller can borrow `0` tokens (trivially passing the balance check) while directing the pool to call `token.approve(attacker, type(uint256).max)` as `msg.sender == address(pool)`.

#### 💡 Solution Walkthrough
In [Truster.t.sol](./test/truster/Truster.t.sol), `test_truster()` deploys `AttackFlashLoan` (executing in 1 transaction via constructor):
1. Calls `pool.flashLoan(0, address(this), address(token), abi.encodeWithSignature("approve(address,uint256)", address(this), type(uint256).max))`.
2. Calls `token.transferFrom(address(pool), recovery, 1_000_000e18)` to sweep the approved vault balance.

#### 🛡️ Mitigation
Restrict flash loan execution callbacks strictly to a designated receiver contract (`borrower.onFlashLoan(...)`) instead of calling an arbitrary user-supplied `target`.

[↑ Back to Index](#challenge-index)

---

### 4. Side Entrance

> **Solution:** [SideEntrance.t.sol](./test/side-entrance/SideEntrance.t.sol)

#### 📋 Description
`SideEntranceLenderPool` holds **1,000 ETH**, allows deposits and withdrawals, and offers free ETH flash loans. Starting with **1 ETH**, rescue all **1,000 ETH** into `recovery`.

#### 🔍 How to Find It
- Whenever a flash loan validates repayment using **raw contract balance** (`address(this).balance >= balanceBefore`), check all other functions that increase the contract's balance (`deposit()`, `stake()`, `mint()`).
- Verify whether `ReentrancyGuard` protects *all* state-sharing functions, not just one.

#### ⚠️ Vulnerability (Root Cause)
`SideEntranceLenderPool` checks `if (address(this).balance < balanceBefore) revert RepayFailed();` at the end of `flashLoan()`. Neither `flashLoan()` nor `deposit()` has a reentrancy lock. Inside the `execute()` callback, a borrower can repay the loaned ETH by calling `pool.deposit{value: msg.value}()`, restoring `address(this).balance` while simultaneously crediting `balances[msg.sender] += msg.value`.

#### 💡 Solution Walkthrough
In `AttackSideEntrance`:
1. `attackSideEntrace()` invokes `pool.flashLoan(1000e18)`.
2. Inside `execute() external payable`, it forwards `msg.value` to `pool.deposit{value: msg.value}()`.
3. After `flashLoan()` finishes, it calls `pool.withdraw()` and forwards the `1000e18` ETH to `recovery`.

#### 🛡️ Mitigation
Apply `nonReentrant` across `flashLoan()`, `deposit()`, and `withdraw()`, or isolate flash loan accounting from user deposit ledgers.

[↑ Back to Index](#challenge-index)

---

### 5. The Rewarder

> **Solution:** [TheRewarder.t.sol](./test/the-rewarder/TheRewarder.t.sol), [dvt-distribution.json](./test/the-rewarder/dvt-distribution.json) & [weth-distribution.json](./test/the-rewarder/weth-distribution.json)

#### 📋 Description
`TheRewarderDistributor` distributes **10 DVT** and **1 WETH** across 1,000 beneficiaries using Merkle roots and claimed-status bitmaps, supporting multi-token batched claims in a single call. Save as much DVT and WETH as possible to `recovery`.

#### 🔍 How to Find It
- Audit batched loops carefully: check **when** state updates (`_setClaimed`) happen relative to token transfers (`transfer()`).
- Look for loop-level optimizations that accumulate bitmasks (`bitsSet |= ...`) across multiple iterations before committing storage. Ask what happens if the user passes the *same valid leaf* multiple times consecutively.

#### ⚠️ Vulnerability (Root Cause)
In `TheRewarderDistributor.claimRewards()`, storage update `_setClaimed()` is deferred until either `token` changes (`token != inputTokens[inputClaim.tokenIndex]`) or the loop reaches the last claim (`i == inputClaims.length - 1`). Meanwhile:
1. Repeating the exact same `(batchNumber: 0, tokenIndex: 0)` claim causes `bitsSet = bitsSet | (1 << bitPosition)` to remain identical, while `amount += inputClaim.amount` sums up.
2. Each iteration calls `MerkleProof.verify()` (which passes for the valid leaf) and immediately transfers tokens out.
3. Because `_setClaimed()` only checks `(currentWord & newBits) != 0` *once* for the whole batch at the end, a single valid leaf can claim the entire `distributions[token].remaining` balance in one array.

#### 💡 Solution Walkthrough
1. `Attacker` loads `dvtLeaves` and `wethLeaves` and uses `player`'s unclaimed leaf at index `188` (`PLAYER_DVT_CLAIM_AMOUNT` and `PLAYER_WETH_CLAIM_AMOUNT`).
2. Computes how many repetitions fit within `distributor.getRemaining(token)` (`DVT_Drain`, `WETH_Drain`), builds two `Claim[]` arrays repeating `player`'s valid claim proof, executes `claimRewards()` once per token, and transfers the claimed DVT and WETH to `recovery`.

#### 🛡️ Mitigation
Validate and update the bitmap storage bit *inside the loop on every individual claim* before executing the token transfer, and follow Checks-Effects-Interactions per iteration.

[↑ Back to Index](#challenge-index)

---

### 6. Selfie

> **Solution:** [Selfie.t.sol](./test/selfie/Selfie.t.sol)

#### 📋 Description
`SelfiePool` holds **1,500,000 DVT** (`DamnValuableVotes`, out of a 2,000,000 total supply) and offers zero-fee ERC-3156 flash loans. `SimpleGovernance` requires `> 50%` voting power to queue actions and gates `SelfiePool.emergencyExit(address)` behind a 2-day delay. Starting with 0 DVT, rescue all **1.5M DVT** into `recovery`.

#### 🔍 How to Find It
- Whenever a governance contract checks token voting weight, verify **whether it checks live current votes (`getVotes()`) or historical snapshots (`getPastVotes()`)**.
- Check whether the protocol also offers a **flash loan** of the governance token itself exceeding the quorum threshold (here 1.5M / 2M = 75% > 50%).

#### ⚠️ Vulnerability (Root Cause)
`SimpleGovernance._hasEnoughVotes()` checks live balances via `_votingToken.getVotes(who)` at proposal creation time. Because `ERC20Votes` lets any token holder immediately self-delegate (`delegate(address(this))`), borrowing 75% of the supply in a flash loan grants instantaneous governance majority within `onFlashLoan()`, allowing an arbitrary action (`emergencyExit`) to be queued and repaid in the same transaction.

#### 💡 Solution Walkthrough
In `FlashLoanReceiver`:
1. `attack()` calls `pool.flashLoan()` for all `1,500,000e18` DVT with `abi.encodeWithSignature("emergencyExit(address)", recovery)` as callback data.
2. Inside `onFlashLoan()`, delegates votes to itself via `token.delegate(address(this))`, queues `emergencyExit(recovery)` via `governance.queueAction(address(pool), 0, _data)`, and approves repayment.
3. Advances `block.timestamp` by `2 days` (`vm.warp`) and invokes `governance.executeAction(id)`.

#### 🛡️ Mitigation
Measure proposal/voting power at a **prior snapshot block** (`getPastVotes(who, block.number - 1)` or at proposal creation snapshot) so flash-loaned tokens borrowed in the current block carry zero voting power.

[↑ Back to Index](#challenge-index)

---

### 7. Compromised

> **Solution:** [Compromised.t.sol](./test/compromised/Compromised.t.sol)

#### 📋 Description
An NFT `Exchange` holds **999 ETH** and mints/buys `DamnValuableNFT` (`"DVNFT"`) using the median price reported by 3 trusted sources on `TrustfulOracle`. A leaked web server HTTP response contains two mysterious hex-encoded strings. Starting with **0.1 ETH**, rescue all **999 ETH** into `recovery` and ensure the median oracle price returns to **999 ETH**.

#### 🔍 How to Find It
- Look for **off-chain operational security clues** (raw hex/Base64 strings in prompts, config leaks, hardcoded keys) paired with privileged on-chain roles (`TRUSTED_SOURCE_ROLE`).
- Check the oracle's **aggregation quorum**: with 3 trusted sources, compromising just 2 keys gives full control over `_computeMedianPrice()`.

#### ⚠️ Vulnerability (Root Cause)
Decoding the two hex strings in the server output (`hex -> ASCII -> Base64`) reveals the private keys for 2 of the 3 trusted oracle addresses (`0x188...088` and `0xA41...9D8`). Because `TrustfulOracle.getMedianPrice()` takes the middle value of the 3 sorted source prices (`prices[1]`), controlling 2 sources completely dictates the NFT buy and sell prices on `Exchange`.

#### 💡 Solution Walkthrough
In `CompromisedChallenge` & `Attacker`:
1. Using the two compromised oracle keys, `Attacker.DrainEther()` calls `oracle.postPrice("DVNFT", 0 ether)` from both sources, dropping the median price to `0`.
2. Buys 1 NFT via `exchange.buyOne{value: 0.1 ether}()` (receiving `0.1 ether` refund back because price is `0`).
3. Restores both oracle sources to `999 ether`, approves the NFT, calls `exchange.sellOne(id)` to receive all `999 ether` from the exchange, and forwards `999 ether` to `recovery`.

#### 🛡️ Mitigation
Never expose oracle reporter keys in web service payloads or repositories; manage keys via hardware security modules (HSMs), increase quorum size, and enforce max price-deviation bounds per update.

[↑ Back to Index](#challenge-index)

---

### 8. Puppet

> **Solution:** [Puppet.t.sol](./test/puppet/Puppet.t.sol)

#### 📋 Description
`PuppetPool` holds **100,000 DVT** and lets users borrow DVT by depositing **2x** its value in ETH (`DEPOSIT_FACTOR = 2`), deriving DVT's price from a Uniswap V1 pair containing only **10 ETH and 10 DVT**. Starting with **25 ETH** and **1,000 DVT**, drain all **100,000 DVT** into `recovery` in 1 transaction.

#### 🔍 How to Find It
- Flag any lending protocol that calculates collateral value using **instantaneous AMM spot reserves** (`pair.balance / token.balanceOf(pair)`).
- Compare the player's available liquidity (`1,000 DVT`) against the oracle pool's depth (`10 DVT` — player holds **100x** the pool's entire token reserve!).

#### ⚠️ Vulnerability (Root Cause)
`PuppetPool._computeOraclePrice()` computes:
```solidity
return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
```
Swapping `1,000 DVT` into a `10 ETH / 10 DVT` Uniswap V1 pool floods the DVT reserve (`~1,010 DVT`) and drains ETH reserve (`~0.099 ETH`), collapsing the calculated DVT spot price and reducing the 2x ETH collateral needed to borrow all `100,000 DVT` below ~20 ETH.

#### 💡 Solution Walkthrough
In `Puppet.t.sol`, `test_puppet11()` deploys `Attacker`:
1. Approves and swaps all `1,000 ether` DVT for ETH via `uniswapV1Exchange.tokenToEthSwapInput()`.
2. Calls `lendingPool.borrow{value: eth_out + 25 ether}(100_000e18, recovery)` (the pool refunds excess ETH above `calculateDepositRequired`) and transfers all `100,000 DVT` straight to `recovery` in a single transaction.

#### 🛡️ Mitigation
Never rely on spot AMM pool balances as a price oracle for lending/borrowing; integrate manipulation-resistant external price feeds (e.g., Chainlink) or deep-liquidity TWAPs.

[↑ Back to Index](#challenge-index)

---

### 9. Puppet V2

> **Solution:** [PuppetV2.t.sol](./test/puppet-v2/PuppetV2.t.sol)

#### 📋 Description
`PuppetV2Pool` upgrades the previous lending pool to hold **1,000,000 DVT**, require **3x WETH** collateral, and query `UniswapV2Library.getReserves()` and `quote()` on a Uniswap V2 pair holding **10 WETH and 100 DVT**. Starting with **20 ETH** and **10,000 DVT**, drain all **1,000,000 DVT** into `recovery`.

#### 🔍 How to Find It
- Recognize that using official helper libraries (`UniswapV2Library.getReserves()` + `quote()`) does **not** make an AMM oracle safe if it still reads **current block reserves** instead of time-weighted accumulators.
- Check the reserve ratio impact: dumping `10,000 DVT` into a `100 DVT` reserve pool inflates token reserves by ~100x.

#### ⚠️ Vulnerability (Root Cause)
`PuppetV2Pool._getOracleQuote()` directly invokes `UniswapV2Library.getReserves()` and `UniswapV2Library.quote()`. Because Uniswap V2 reserves update immediately within any transaction's swap, an attacker can skew the reserve ratio (`reservesWETH / reservesToken`) before calling `borrow()`, making `1,000,000 DVT` borrowable for `< 30 WETH` instead of `300,000 WETH`.

#### 💡 Solution Walkthrough
In `test_puppetV2()`:
1. Wraps `20 ETH` into WETH via `weth.deposit()`.
2. Approves `uniswapV2Router` and swaps all `10,000e18` DVT for WETH (`swapExactTokensForTokensSupportingFeeOnTransferTokens`), receiving ~9.9 WETH (~29.9 WETH total) and crashing DVT's spot price on the pair.
3. Approves `lendingPool` on WETH, calls `lendingPool.borrow(1_000_000e18)`, and transfers all `1,000,000 DVT` to `recovery`.

#### 🛡️ Mitigation
Do not use `UniswapV2Library.getReserves()` as a price oracle. Use Uniswap V2 cumulative price accumulators (`price0CumulativeLast` / `price1CumulativeLast`) over an adequate TWAP interval or an external decentralized oracle network.

[↑ Back to Index](#challenge-index)

---

### 10. Free Rider

> **Solution:** [FreeRider.t.sol](./test/free-rider/FreeRider.t.sol)

#### 📋 Description
`FreeRiderNFTMarketplace` holds **90 ETH** and lists **6 NFTs** at **15 ETH** each, while `FreeRiderRecoveryManager` offers a **45 ETH** bounty to deliver all 6 NFTs. Starting with **0.1 ETH** and a Uniswap V2 `WETH/DVT` pool (`9,000 WETH / 15,000 DVT`), acquire all 6 NFTs, claim the bounty, and keep the profits.

#### 🔍 How to Find It
- In batch purchase functions (`buyMany`), check whether **`msg.value` is validated against the sum of all item prices** or reused unchanged inside each loop iteration.
- Always check **transfer-vs-payment ordering** when calling `ownerOf(tokenId)` dynamically instead of caching the seller in a local variable beforehand.

#### ⚠️ Vulnerability (Root Cause)
Two critical bugs inside `FreeRiderNFTMarketplace._buyOne()`:
1. **Unchecked Cumulative Payment:** `buyMany()` loops over `tokenIds` calling `_buyOne()`, where `if (msg.value < priceToPay)` compares `msg.value` against a single NFT's price (`15 ETH`) rather than tracking remaining/cumulative ETH spent. Sending `15 ETH` once passes the check for all 6 NFTs.
2. **Paying the Buyer Instead of the Seller:**
   ```solidity
   _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);
   payable(_token.ownerOf(tokenId)).sendValue(priceToPay);
   ```
   Ownership changes on the first line, so the second line reads `ownerOf(tokenId)` as **`msg.sender` (the buyer)** and sends `15 ETH * 6 = 90 ETH` from the marketplace balance right back to the buyer!

#### 💡 Solution Walkthrough
In `FlashSwapAttacker`:
1. Flash-swaps `15 ether` of WETH from `uniswapPair` (`pair.swap(..., "flashloan")`) and unwraps to native ETH.
2. Calls `marketplace.buyMany{value: 15 ether}(tokenIds)` for IDs `0..5`, receiving all 6 NFTs **plus** `90 ether` from the marketplace.
3. Wraps `15 ether + 0.3% fee` into WETH to repay the Uniswap V2 flash swap and forwards profits + NFTs to `player`.
4. `test_freeRider()` sends all 6 NFTs via `nft.safeTransferFrom(..., address(recoveryManager), i, abi.encode(player))` to trigger the `45 ether` bounty payout.

#### 🛡️ Mitigation
Track cumulative `totalPaid += priceToPay` across `buyMany()` (or reject excess/insufficient `msg.value` sums) and cache `address seller = _token.ownerOf(tokenId)` **before** executing `safeTransferFrom()`.

[↑ Back to Index](#challenge-index)

---

### 11. Backdoor

> **Solution:** [Backdoor.t.sol](./test/backdoor/Backdoor.t.sol)

#### 📋 Description
`WalletRegistry` awards **10 DVT** to each of four registered beneficiaries (Alice, Bob, Charlie, David — **40 DVT total**) when their 1-of-1 Safe wallet is deployed through `SafeProxyFactory.createProxyWithCallback()`, validating the factory, Safe singleton copy, `Safe.setup` selector, threshold, owner, and fallback handler. Rescue all **40 DVT** into `recovery` in a single transaction.

#### 🔍 How to Find It
- When integrating Safe wallet deployments via `createProxyWithCallback()`, inspect **every parameter inside `Safe.setup(...)`**, not just `owners`, `threshold`, and `fallbackHandler`.
- Specifically check whether `Safe.setup` parameters `to` and `data` (used for optional module initialization via `delegatecall`) are restricted, because that `delegatecall` runs inside the newly deployed Safe *before* `proxyCreated()` executes.

#### ⚠️ Vulnerability (Root Cause)
`WalletRegistry.proxyCreated()` validates `msg.sender == walletFactory`, `singleton == singletonCopy`, `bytes4(initializer[:4]) == Safe.setup.selector`, `threshold == 1`, `owners.length == 1`, `beneficiaries[owners[0]]`, and `fallbackManager == address(0)`. However, it never validates the `to` and `data` arguments passed into `Safe.setup()`, enabling an arbitrary `delegatecall` inside the new Safe during setup (for instance, approving an external spender on DVT before the registry transfers the 10 DVT reward).

#### 💡 Solution Walkthrough
In `Backdoor.t.sol`:
1. `test_backdoor()` deploys `Attacker`, which deploys `ExploitHelper` (with runtime bytecode so Safe's `isContract(to)` check passes).
2. For each of the 4 beneficiaries, `Attacker` calls `walletFactory.createProxyWithCallback()` passing `to = address(helper)` and `data = abi.encodeCall(helper.execute, (address(token), address(this)))` inside `singletonCopy.setup(...)`, granting `Attacker` `type(uint256).max` approval on the newly created Safe.
3. Once `WalletRegistry` sends `10 DVT` to the Safe proxy, `Attacker` calls `token.transferFrom(proxy, recovery, 10 ether)`.

#### 🛡️ Mitigation
Decode and validate `Safe.setup()` calldata arguments inside `proxyCreated()` to enforce `to == address(0)` and `data.length == 0` (or verify token allowances/Safe modules post-setup), and require a signature from the beneficiary before deploying on their behalf.

[↑ Back to Index](#challenge-index)

---

### 12. Climber

> **Solution:** [Climber.t.sol](./test/climber/Climber.t.sol)

#### 📋 Description
A UUPS-upgradeable `ClimberVault` holds **10,000,000 DVT** and is owned by `ClimberTimelock`, which enforces a 1-hour delay and restricts `schedule()` to `PROPOSER_ROLE`. Rescue all **10,000,000 DVT** into `recovery`.

#### 🔍 How to Find It
- Check timelock `execute()` functions for **Checks-Effects-Interactions (CEI)** ordering: does it verify operation readiness (`ReadyForExecution`) *before* executing the target calls, or *after*?
- Check if the timelock contract holds `ADMIN_ROLE` over itself (`_grantRole(ADMIN_ROLE, address(this))`).

#### ⚠️ Vulnerability (Root Cause)
Inside `ClimberTimelock.execute()`:
```solidity
for (uint8 i = 0; i < targets.length; ++i) {
    targets[i].functionCallWithValue(dataElements[i], values[i]);
}
if (getOperationState(id) != OperationState.ReadyForExecution) {
    revert NotReadyForExecution(id);
}
operations[id].executed = true;
```
Because `targets[i].functionCallWithValue(...)` runs **before** verifying `ReadyForExecution` — and because `ClimberTimelock` is self-administered — an arbitrary caller can execute an unscheduled batch that lowers `delay` to `0`, grants `PROPOSER_ROLE`, upgrades the vault, drains it, and calls back into `timelock.schedule()` for that exact batch before the readiness check executes.

#### 💡 Solution Walkthrough
In `Climber.t.sol`, `Attacker.execute()` passes a 6-step batch into `timelock.execute()`:
1. Calls `timelock.updateDelay(0)`.
2. Grants `PROPOSER_ROLE` to `timelock` and `player`.
3. Upgrades `vault` via `upgradeToAndCall()` to a custom `PwnVault` implementation.
4. Calls `PwnVault.drain(address(token), recovery)` to sweep all `10,000,000e18` DVT.
5. Calls `Attacker.SelfSchedule()` to schedule the executing batch on `timelock` before `execute()` reaches line 94's `ReadyForExecution` check.

#### 🛡️ Mitigation
Enforce Checks-Effects-Interactions in `ClimberTimelock.execute()` by validating `getOperationState(id) == OperationState.ReadyForExecution` and setting `operations[id].executed = true` *before* looping over `targets[i].functionCallWithValue()`.

[↑ Back to Index](#challenge-index)

---

### 14. Puppet V3

> **Solution:** [PuppetV3.t.sol](./test/puppet-v3/PuppetV3.t.sol)

#### 📋 Description
`PuppetV3Pool` holds **1,000,000 DVT** (requiring **3x WETH** collateral) and queries a Uniswap V3 pool (`100 WETH` / `100 DVT`, `0.3%` fee tier, observation cardinality 40) via `OracleLibrary.consult()` with a 10-minute (`TWAP_PERIOD = 10 minutes`) window. Starting with **1 ETH** and **110 DVT**, borrow all **1,000,000 DVT** into `recovery` in under **115 seconds**.

#### 🔍 How to Find It
- When reviewing a Uniswap V3 TWAP oracle, check **liquidity depth, active tick range, and TWAP window length** together.
- If liquidity is thin and tightly concentrated (`tickLower: -60, tickUpper: 60`), a single swap larger than the pool's token liquidity moves the pool tick completely to the boundary, rapidly pulling down even an arithmetic-mean TWAP within ~100 seconds.

#### ⚠️ Vulnerability (Root Cause)
`PuppetV3Pool._getOracleQuote()` computes the arithmetic mean tick over `600 seconds` from a thinly seeded Uniswap V3 pool (`100 WETH / 100 DVT` between ticks `-60` and `60`). Because `player` holds `110 DVT` (> total DVT in the pool), swapping `110 DVT` pushes the tick to an extreme value; letting `100` seconds elapse before `borrow()` depresses the 10-minute arithmetic mean tick low enough that 1 WETH satisfies the 3x collateral check for all `1,000,000 DVT`.

#### 💡 Solution Walkthrough
In `test_puppetV3()`:
1. Wraps `1 ETH` into WETH and approves `lendingPool`.
2. Swaps all `110e18` DVT for WETH via `ISwapRouter.exactInputSingle()`, crashing the Uniswap V3 pool price tick.
3. Advances `block.timestamp` by `100` seconds (`vm.warp(block.timestamp + 100)` — still `< 115` seconds limit).
4. Borrows all `1,000,000e18` DVT via `lendingPool.borrow()` and transfers them to `recovery`.

#### 🛡️ Mitigation
Only rely on Uniswap V3 TWAP oracles for deep, wide-range liquidity pools with long TWAP windows, and pair them with external price feeds (e.g., Chainlink) plus maximum deviation circuit breakers.

[↑ Back to Index](#challenge-index)

---

### 15. ABI Smuggling

> **Solution:** [ABISmuggling.t.sol](./test/abi-smuggling/ABISmuggling.t.sol)

#### 📋 Description
`SelfAuthorizedVault` (inheriting `AuthorizedExecutor`) guards **1,000,000 DVT** and exposes `execute(address target, bytes calldata actionData)`. Action permissions grant `player` access only to `withdraw` (`0xd9caed12`), whereas `deployer` has access to `sweepFunds` (`0x85fb709d`). Recover all **1,000,000 DVT** into `recovery`.

#### 🔍 How to Find It
- Audit any **inline assembly (`calldataload(...)`)** that reads dynamic parameters (`bytes`, `string`, arrays) using **hardcoded fixed offsets** instead of reading the dynamic pointer or slicing the Solidity-decoded `calldata` argument directly.
- Remember the Head-Tail ABI spec: Solidity follows the offset pointer word (`0x24`), ignoring filler slots placed between the Head and Tail.

#### ⚠️ Vulnerability (Root Cause)
Inside `AuthorizedExecutor.execute()`:
```solidity
uint256 calldataOffset = 4 + 32 * 3; // fixed byte 100 (0x64)
assembly {
    selector := calldataload(calldataOffset)
}
```
The check assumes canonical ABI encoding where `actionData`'s pointer at byte `0x24` is always `0x40`, putting `actionData.length` at byte `68` (`0x44`) and payload at byte `100` (`0x64`). However, an encoded call can shift the dynamic pointer to `0x80` (`132`), placing a permitted selector at byte `100` while Solidity's ABI decoder reads `actionData` from byte `132+`.

#### 💡 Solution Walkthrough
In `test_abiSmuggling()`:
1. Encodes raw calldata manually using `abi.encodePacked`:
   - `0x00`: `vault.execute.selector`
   - `0x04`: `address(vault)` (padded to 32 bytes)
   - `0x24`: `uint256(0x80)` (shifted dynamic offset pointing to byte `132`)
   - `0x44`: `uint256(0)` (filler word)
   - `0x64` (`byte 100`): permitted `withdraw` selector `0xd9caed12` padded to 32 bytes (checked by `calldataload(100)`)
   - `0x84` (`byte 132`): `sweepFundsCalldata.length` followed by `abi.encodeWithSelector(vault.sweepFunds.selector, recovery, address(token))`
2. Calls `address(vault).call(calldataPayload)`, passing the permission gate on `0xd9caed12` while executing `sweepFunds(recovery, token)`.

#### 🛡️ Mitigation
Never parse dynamic calldata arguments via hardcoded offsets; read the selector directly from Solidity's decoded slice (`bytes4(actionData[:4])`), or enforce canonical offset checks (`offset == 0x40`).
```solidity
// Safe pattern:
if (actionData.length < 4) revert InvalidActionData();
bytes4 selector = bytes4(actionData[:4]);
```

[↑ Back to Index](#challenge-index)

---

### 16. Shards

> **Solution:** [Shards.t.sol](./test/shards/Shards.t.sol)

#### 📋 Description
`ShardsNFTMarketplace` fractionalizes NFTs into ERC-1155 shards sold for DVT (collecting a 1% seller fee stored in `ShardsFeeVault`), allowing partial `fill()` and `cancel()` operations. Starting with **0 DVT**, recover as much DVT as possible into `recovery` in 1 transaction.

#### 🔍 How to Find It
- Check **every pair of entry/exit math functions** (`deposit`/`withdraw`, `fill`/`cancel`, `mint`/`burn`) for mismatched formulas, units, or rounding directions (`mulDivDown` vs `mulDivUp`).
- Verify time-lock inequality signs carefully (`>` vs `<`)!

#### ⚠️ Vulnerability (Root Cause)
Three bugs combine inside `ShardsNFTMarketplace`:
1. **Zero-Cost Truncation in `fill()`:** `want.mulDivDown(_toDVT(offer.price, _currentRate), offer.totalShards)` rounds *down*; for `want = 133`, total DVT cost truncates to `0`.
2. **Inverted Cancel Time Check:** `cancel()` checks `block.timestamp > purchase.timestamp + TIME_BEFORE_CANCEL`, inadvertently allowing cancellation *immediately* during the waiting period.
3. **Asymmetric Refund Scaling in `cancel()`:** `cancel()` computes refund as `purchase.shards.mulDivUp(purchase.rate, 1e6)` — omitting division by `offer.totalShards` and rounding *up*, paying positive DVT back for a 0-DVT fill.

#### 💡 Solution Walkthrough
In `Shards.t.sol`, `Attacker`:
1. Runs `7520` iterations of `marketplace.fill(1, 133)` (costing `0` DVT) immediately followed by `marketplace.cancel(1, index)` (receiving DVT from the marketplace's fee balance).
2. Transfers all recovered DVT to `recovery`.

#### 🛡️ Mitigation
Store the exact token payment amount recorded on `Purchase` and refund that exact amount upon `cancel()`, apply protocol-favorable rounding (`mulDivUp` on incoming funds, `mulDivDown` on refunds), and invert the waiting-period check to `block.timestamp < purchase.timestamp + TIME_BEFORE_CANCEL`.

[↑ Back to Index](#challenge-index)

---

### 17. Curvy Puppet

> **Solution:** [CurvyPuppet.t.sol](./test/curvy-puppet/CurvyPuppet.t.sol)

#### 📋 Description
`CurvyPuppetLending` allows borrowing Curve ETH/stETH LP tokens (`steCRV`) using DVT as collateral, pricing LP tokens via `oracle.getPrice(ETH) * curvePool.get_virtual_price()`. Alice, Bob, and Charlie each deposited **2,500 DVT** collateral (`$25,000`) and borrowed **1 LP token** (`~$4,387` at `1.096e18` virtual price). Using up to **200 WETH** and **6.5 LP tokens** provided by the treasury, liquidate all three positions and return all seized DVT and unused funds to `treasury`.

#### 🔍 How to Find It
- Audit every `view` oracle dependency on external AMM pools (`get_virtual_price()`): **does the AMM send native ETH before updating all balances or burning/syncing supply?**
- Note that Curve's legacy `remove_liquidity()` sends native ETH via `raw_call`, transferring execution flow to the recipient's `receive()` fallback *mid-execution* when `view` functions are unprotected by reentrancy locks.

#### ⚠️ Vulnerability (Root Cause)
Cross-contract **read-only reentrancy** in Curve's legacy `ETH/stETH` pool (`0xDC24316b9AE028F1497c275EB9192a3Ea0f67022`):
1. When calling `remove_liquidity()`, Curve burns LP tokens first (dropping `totalSupply` back to `~63,900`), then sends native ETH (`raw_call`), **before** transferring `stETH`.
2. Inside the recipient's `receive()` callback, `stETH` balances remain unwithdrawn inside the pool while `totalSupply` is already reduced.
3. Calling `curvePool.get_virtual_price()` (`D / totalSupply`) during this window computes an inflated invariant `D` against the reduced supply, spiking `virtual_price` from `1.096e18` to **`3.586e18`** — exceeding the **`3.5714e18`** threshold (`175%` collateralization check in `CurvyPuppetLending.liquidate()`).

#### 💡 Solution Walkthrough
In `CurvyPuppet.t.sol`, `Attacker`:
1. Takes nested flash loans: **37,991 WETH** from Balancer V2 Vault and **21,000 WETH + 173,000 wstETH** from Aave V3 Pool.
2. Unwraps `WETH` -> ETH and `wstETH` -> `stETH`, deposits them into Curve via `add_liquidity()`, then calls `remove_liquidity()`.
3. Inside `receive()` (triggered when Curve sends ETH mid-withdrawal), approves `Permit2` for `lending` and liquidates Bob, Alice, and Charlie while `virtual_price` reads `3.586e18`, forwarding all `7,500 DVT` to `treasury`.
4. Uses surplus native ETH from Curve's withdrawal to mint the `stETH` wrap deficit 1:1 via Lido `IStETH.submit()`, re-wraps to `wstETH`, wraps `WETH` (+ Aave premiums), repays both flash loans, and returns remaining WETH and LP tokens to `treasury`.

#### 🛡️ Mitigation
Verify that the Curve pool is **not locked inside an active reentrancy state** before reading `get_virtual_price()` (e.g., by invoking a non-reentrant state-checking helper on the pool or verifying EIP-1153 transient storage reentrancy flags).

[↑ Back to Index](#challenge-index)

---

### 18. Withdrawal

> **Solution:** [Withdrawal.t.sol](./test/withdrawal/Withdrawal.t.sol) & [withdrawals.json](./test/withdrawal/withdrawals.json)

#### 📋 Description
An L2-to-L1 token bridge (`L1Gateway`, `L1Forwarder`, `TokenBridge`) holds **1,000,000 DVT** (`totalDeposits = 1,000,000e18`) with a 7-day delay and 4 initiated withdrawal logs in `withdrawals.json`: three legitimate `10e18` DVT withdrawals and one suspicious `999,000e18` DVT withdrawal. Acting as a bridge operator (`OPERATOR_ROLE` on `L1Gateway`), finalize all four logs while keeping the bridge funds safe.

#### 🔍 How to Find It
- Check cross-chain message relayers (`L1Gateway` + `L1Forwarder`) for two behaviors:
  1. Does `L1Forwarder.forwardMessage()` swallow inner call reverts (`success == false`) and mark `failedMessages[messageId] = true` while returning cleanly?
  2. Does `L1Gateway.finalizeWithdrawal()` skip Merkle proof checks for `OPERATOR_ROLE` and mark `finalizedWithdrawals[leaf] = true` even when the underlying token transfer reverts?
- Check `TokenBridge.executeTokenWithdrawal()` arithmetic: `totalDeposits -= amount` reverts via Solidity 0.8 checked underflow whenever `totalDeposits < amount`.

#### ⚠️ Vulnerability (Root Cause)
1. **Unverified Operator Messages:** `L1Gateway.finalizeWithdrawal()` skips `MerkleProof.verify()` when called by `OPERATOR_ROLE` (`player`), letting the operator supply arbitrary messages forwarded with `l2Sender` context via `L1Forwarder`.
2. **Failure Catching in `L1Forwarder`:** When `TokenBridge.executeTokenWithdrawal()` reverts (e.g., due to `totalDeposits < amount`), `L1Forwarder.forwardMessage()` records `failedMessages[messageId] = true` instead of reverting, allowing `L1Gateway` to mark the suspicious leaf as finalized and increment `counter`.

#### 💡 Solution Walkthrough
In `test_withdrawal()`:
1. Uses `OPERATOR_ROLE` on `L1Gateway` to finalize a custom `forwardMessage` call withdrawing `900,000e18` DVT to `player`, temporarily reducing `l1TokenBridge`'s `totalDeposits` and balance to `100,000e18`.
2. Iterates through all 4 withdrawal logs parsed from `withdrawals.json` after advancing `7 days`:
   - Logs `0`, `1`, and `3` (`10e18` DVT each) succeed normally.
   - Log `2` (`999,000e18` DVT) fails inside `TokenBridge.executeTokenWithdrawal()` due to checked underflow on `totalDeposits`, causing `L1Forwarder` to catch the revert while `L1Gateway` still marks the withdrawal finalized.
3. Transfers the `900,000e18` DVT back to `l1TokenBridge`, keeping >99% of bridge funds safe with all 4 leaves marked finalized. *(Note: Because `L1Forwarder` stores the reverted call in `failedMessages`, in production a blocked message must also be invalidated so it cannot be replayed once funds return.)*

#### 🛡️ Mitigation
Never bypass Merkle proof validation or permit arbitrary `forwardMessage` spoofing via operator roles, explicitly reject/cancel flagged withdrawals rather than storing retryable `failedMessages`, and enforce invariant accounting checks across L1/L2 bridge state.

[↑ Back to Index](#challenge-index)

---

## Running Locally

1. Clone the official Damn Vulnerable DeFi v4 repository:
   ```bash
   git clone https://github.com/theredguild/damn-vulnerable-defi.git
   cd damn-vulnerable-defi
   ```
2. Replace its `test/` folder with the `test/` directory from this repository.
3. Copy `.env.sample` to `.env` and set `MAINNET_FORKING_URL` (required for mainnet-fork challenges `#14 Puppet V3` and `#17 Curvy Puppet`).
4. Run the test suite:
   ```bash
   forge test
   ```
   *(Run individual challenges with `forge test --mp test/<challenge-name>/<TestFile>.t.sol`.)*

---

> **Disclaimer:** All contracts and test cases are strictly for smart contract security education and auditing practice.
