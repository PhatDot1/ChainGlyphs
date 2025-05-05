# DicePoker: Two‑Phase On‑Chain Dice “Poker” Performance Report

A two‑player, two‑phase dice “poker” game contract deployed to both Polkadot Westend Asset Hub (PolkaVM) and Ethereum Sepolia, with in‑depth comparative analysis of:

- EVM init‑code size constraints  
- Gas vs. weight consumption  
- End‑to‑end transaction latency  
- Developer tooling and UX implications  

This report guides dApp teams porting Solidity contracts across heterogeneous EVM environments.


## 📜 Table of Contents

1. [Game Overview](#game-overview)  
2. [Contract Architecture](#contract-architecture)  
3. [Setup & Deployment](#setup--deployment)  
4. [CLI & Interaction Logging](#cli--interaction-logging)  
5. [Quantitative Performance Evaluation](#quantitative-performance-evaluation)  
   - 5.1 Westend Asset Hub (PolkaVM)  
   - 5.2 Ethereum Sepolia Testnet  
   - 5.3 Comparative Metrics  
6. [Developer Experience & Tooling](#developer-experience--tooling)  
7. [Lessons Learned & Best Practices](#lessons-learned--best-practices)  
8. [Next Steps & Future Work](#next-steps--future-work)  
9. [Conclusion](#conclusion)  
10. [References & Logs](#references--logs)  


## 1. Game Overview

**DicePoker** is a minimal “poker with dice” game implemented entirely on‑chain in Solidity.  

- **Players**: exactly two  
- **Dice**: each player “rolls” five 6‑sided dice via pseudo‑randomness  
- **Rounds**: four betting rounds interleaved with partial reveals  
  1. Both roll, keep all dice secret  
  2. Bet1: stake or fold  
  3. Reveal first 3 dice  
  4. Bet2: stake or fold  
  5. Reveal last 2 dice  
  6. Compare 5‑dice sums, award pot  
- **Actions**:  
  - `joinGame()`  
  - `placeBet(uint256 amount)`  
  - `call(uint256 amount)`  
  - `fold()`  
  - `rollDice()`  

**Why two‑phase?** splitting the reveal incentivizes strategic betting based on partial information, akin to draw poker.



## 2. Contract Architecture

1. **Game States**  
   - Joining → Bet1 → Reveal first 3 dice → Bet2 → Reveal last 2 dice → Determine winner → Reset  

2. **Phases**  
   - **Phase 1**: players join, first betting round  
   - **Phase 2**: first‑3‑dice reveal, second betting round, last‑2‑dice reveal, winner determination  

3. **Mechanics**  
   - Randomness via `keccak256(block.timestamp, msg.sender, nonce)`  
   - Bets tracked per player; pot aggregated on‑chain  
   - State machine enforced by `GameState` enum and internal modifiers  


## 3. Setup & Deployment

1. Compile with Hardhat (Solidity → EVM bytecode).  
2. Fund two accounts with Sepolia ETH//WND on polkadot westend asset hub  
3. Deploy via Ethers.js / Hardhat:  
```
westendAssetHub: {
  url: "https://westend-asset-hub-eth-rpc.polkadot.io",
  chainId: 420420421,
  accounts: [...]
}
```
   ```
   npx hardhat run scripts/deploy.js --network sepolia
```
   ```
   npx hardhat run scripts/deploy.js --network westendAssetHub
```
4. Note contract address RPC to add to CLI script.


## 4. Initial Challenges


Before diving into performance metrics and developer UX, we ran into a number of surprising “gotchas” while getting started and deciding project's direction in the Polkadot‑EVM ecosystem—these shaped our initial decision making, refactoring, and deployment approach.

### 4.1 Existential Deposit & Factory‑Contract Friction  
- **Substrate existential deposit (ED)** must be met for every new account or contract.  
- Using a factory contract to spawn child games failed unless each child account was pre‑funded above the ED.  
- **Workaround**: top up factory‑deployed addresses, or subsidize via a “faucet” step in your factory logic.  

### 4.2 Hardhat Plugin Visibility & Tooling Gaps  
- Polkadot’s docs and community almost exclusively point to the **Remix EVM‑on‑Substrate plugin**.  
- The Hardhat plugin for PolkaVM, we found was barely mentioned—hard to discover in official docs or tutorials compared to remix.  
- **Remix drawback**: its wallet enforced the 49 152‑byte init‑code limit client‑side, making large contracts effectively undeployable in Remix.  

### 4.3 Explorer & NFT Visibility Limitations  
- Native Westend Asset‑Hub explorer does **not** display ERC‑721/ERC‑1155 transfers or balances.  
- NFT contracts appear deployed, but tokens and metadata seemed invisible unless you decode events yourself.  
- **Desired**: all pallet‑assets and balance transfers should be indexable via the eth‑RPC endpoint so explorers can reconstruct account state.  


## 5. CLI & Interaction Logging

### 5.1 Implementation

- Node.js script uses `readline` for prompts  
- `ethers.Contract` instance for on‑chain calls  
- Await `tx.wait()` to measure confirmation latency  

### 5.2 Sample Log Entry

```json
{
  "timestamp": "2025-05-05T14:23:12.345Z",
  "action": "placeBet",
  "player": "0x…",
  "round": 2,
  "amount": "0.01 ETH",
  "gasUsed": 88673,
  "latencyMs": 19658,
  "chain": "Sepolia"
}
```

### 5.3 End‑to‑End Flow
1. CLI prompts “Player 1: joinGame or exit?”

2. User enters joinGame → transaction sent → log JSON

3. CLI displays updated state

4. Repeat for each action until showdown


## 6. Quantitative Performance Evaluation

### 6.1 Westend Asset Hub (PolkaVM)

> Logs: `dicepoker/westendAssetHub-420420421.log`

| Action      | Avg. weight‑equiv | Min      | Max      | Avg. latency (ms) | Min (ms) | Max (ms) |
|------------:|------------------:|---------:|---------:|------------------:|---------:|---------:|
| joinGame    | 83 138 318        | 79 388 218 | 87 649 418 | 8 944           | 3 686    | 17 860   |
| placeBet    | 148 480 618       | 144 193 818| 164 474 718| 12 321          | 5 124    | 24 676   |
| call        | 143 314 918       | 142 316 018| 151 576 118| 7 780           | 5 436    | 13 696   |
| rollDice    | 147 250 518       | 147 250 518| 147 280 518| 7 550           | 5 550    | 12 485   |

- **Block weight limit**: ~ 5×10⁵ weight units  
- **Avg block time**: ~6 s  
- **Effective throughput**: ~0.02 tx/s  

### 6.2 Ethereum Sepolia Testnet

> Logs: `dicepoker/ethereumSepolia-undefined.log`

| Action      | Avg. gasUsed | Min     | Max      | Avg. latency (ms) | Min (ms) | Max (ms) |
|------------:|-------------:|--------:|---------:|------------------:|---------:|---------:|
| joinGame    | 62 760       | 49 576  | 75 044   | 7 270             | 5 301    | 10 020   |
| placeBet    | 88 673       | 53 681  | 104 520  | 19 658            | 6 207    | 62 441   |
| call        | 57 256       | 48 065  | 65 010   | 14 032            | 5 501    | 49 402   |
| rollDice    | 76 357       | 44 308  | 86 535   | 6 245             | 5 843    | 11 295   |

- **Block gas limit**: ~36 000 000  
- **Avg block time**: ~12 s  
- **Throughput**: ~0.1–0.5 tx/s  

### 6.3 Comparative Metrics

| Metric                   | PolkaVM                    | Sepolia                 | Ratio / Δ                   |
|-------------------------:|---------------------------:|------------------------:|-----------------------------:|
| Block resource ceiling   | ~ 5×10⁵ weight             | ~ 36 000 000 gas        | PolkaVM ≈ 0.014× (but weight‑metered) |
| Avg. `placeBet` cost     | 148 M weight‑equiv         | 88 k gas                | ≈ 1 700× “cost” on PolkaVM   |
| Avg. latency             | 7–12 s                     | 6–20 s                  | Similar; PolkaVM more stable |
| Throughput               | 0.02 tx/s                  | 0.3 tx/s                | Sepolia ≈ 15× higher         |
| Init‑code cap            | 49 152 bytes (strict)      | no practical cap        | PolkaVM constraint forced refactor |


## 7. Developer Experience & Tooling

| Aspect             | Ethereum Sepolia               | PolkaVM Westend Asset Hub       |
|-------------------:|-------------------------------:|--------------------------------:|
| Hardhat deploy    | identical scripts              | identical scripts + chainId tweak |
| Gas/weight estimate| reliable                        | occasional manual gasLimit bump |
| Explorers         | Etherscan (rich UI & logs)     | Subscan (basic logs only)       |
| Debugging         | Hardhat trace, Tenderly        | limited; rely on error codes    |
| RPC reliability   | high availability               | public endpoints sometimes slow |
| Community support | extensive tooling ecosystem     | maturing rapidly                |

> **Takeaway:** Outside of initial limitations ethereum‑native workflows “just work” on PolkaVM with minimal config changes.


## 8. Lessons Learned & Best Practices

1. **Bytecode budgeting**  
   - Enforce < 49 152 bytes init‑code on PolkaVM.  
   - Reduce flattening; use imports/remappings.

2. **Fixed‑size loops**  
   - Avoid unbounded loops; prefer static arrays for on‑chain logic.

3. **Weight vs. gas profiling**  
   - Profile on PolkaVM early—costs can be thousands× higher.

4. **Latency tuning**  
   - Batch where possible; consider client‑side parallelism.

5. **RPC fallback**  
   - Maintain multiple RPC endpoints; detect & switch on timeouts.

6. **Randomness design**  
   - For production, integrate verifiable oracles (Chainlink VRF, Substrate randomness).


## 9. Next Steps & Future Work

1. **Adaptive logic**  
   - Dynamically adjust betting complexity based on `gasleft()`/weight.

2. **Multi‑chain matrix**  
   - Benchmark on Arbitrum, BSC, Polygon, Moonbeam, Avalanche.

3. **Off‑chain compute**  
   - Move scoring or randomness off‑chain via Light‑Client oracles.

4. **UX enhancements**  
   - Bundle multi‑action transactions (meta‑tx batching).

5. **Contract variants**  
   - Reimplement in Rust/WASM for PolkaVM native performance.


## 10. Conclusion

Our cross‑chain port of DicePoker demonstrates that:

- **PolkaVM enforces strict init‑code caps**, necessitating modularization.  
- **Weight‑metering** dramatically increases “cost” of on‑chain loops vs. Ethereum gas.  
- **End‑to‑end latency** is comparable, though PolkaVM offers more consistent block times (~6 s).  
- **Developer ergonomics** remain strong: existing Solidity/Hardhat/Ethers.js toolchains work with minimal change.  

## 11. References & Logs

- **Westend Asset Hub (PolkaVM)** logs:  
  `dicepoker/westendAssetHub-420420421.log`  

- **Ethereum Sepolia** logs:  
  `dicepoker/ethereumSepolia-undefined.log`  

- **OpenZeppelin Contracts**  
- **Hardhat Documentation**  
- **Polkadot JS API & MetaMask PolkaVM Guide**  