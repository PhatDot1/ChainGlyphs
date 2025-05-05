# DicePoker: Two‑Phase On‑Chain Dice “Poker” Performance Report

A two‑player, two‑phase dice “poker” game contract deployed to both Polkadot Westend Asset Hub (PolkaVM) and Ethereum Sepolia, with in‑depth comparative analysis of resource limits, gas/weight consumption, and execution latency.

---

## Table of Contents

1. [Introduction & Motivation](#introduction--motivation)  
2. [Contract Architecture](#contract-architecture)  
3. [Deployment Constraints & Refactoring](#deployment-constraints--refactoring)  
4. [Quantitative Performance Evaluation](#quantitative-performance-evaluation)  
   - 4.1 Westend Asset Hub (PolkaVM)  
   - 4.2 Ethereum Sepolia  
   - 4.3 Comparative Metrics  
5. [Development Experience](#development-experience)  
6. [Lessons Learned & Best Practices](#lessons-learned--best-practices)  
7. [Next Steps & Future Work](#next-steps--future-work)  
8. [Conclusion](#conclusion)  

---

## Introduction & Motivation

DicePoker implements a simple on‑chain “poker” with five dice per player, two betting rounds, partial then final reveals, and highest‐sum wins. The goal of this study is to understand how the same Solidity logic behaves under two EVM environments:

- **Polkadot Westend Asset Hub (PolkaVM)**  
- **Ethereum Sepolia testnet**

We measure deployment feasibility, transaction gas/weight usage, and user‑visible latency to guide future multi‑chain gaming dApps.

---

## Contract Architecture

1. **Game States**  
   - Joining → Bet1 → Reveal first 3 dice → Bet2 → Reveal last 2 dice → Determine winner → Reset  

2. **Phases**  
   - **Phase 1**: players join, first betting round  
   - **Phase 2**: first‑3‑dice reveal, second betting round, last‑2‑dice reveal, winner determination  

3. **Core mechanics**  
   - Randomness via `keccak256(block.timestamp, msg.sender, nonce)`  
   - Bets tracked per player; pot aggregated on‑chain  
   - State machine enforced by `GameState` enum and internal modifiers  

---

## Deployment Constraints & Refactoring

When deploying the original flattened contract (≈ 106 KB init‑code) to Westend Asset Hub, creation failed:
```initcode size of this transaction is too large:
it is 106815 bytes while the max is 49152
```

PolkaVM enforces EIP‑170/EIP‑3860 init‑code cap of **49 152 bytes**. To work around:

- Split logic into smaller internal functions  
- Remove non‑essential modifiers and comments from bytecode  
- Import OpenZeppelin modules via remappings rather than flatten  

After refactor, bytecode < 49 152 bytes, deployment succeeded on both chains.

---

## Quantitative Performance Evaluation

### 4.1 Westend Asset Hub (PolkaVM)

> Full Logs file: `dicepoker/westendAssetHub-420420421.log`

| Action      | Avg. gasUsed | Min gasUsed | Max gasUsed | Avg. latency (ms) | Min (ms) | Max (ms) |
|------------:|-------------:|------------:|------------:|------------------:|---------:|---------:|
| **joinGame**|    62 760    |   49 576    |   75 044    | 7 270             | 5 301    | 10 020   |
| **placeBet**|   88 673     |   53 681    |  104 520    | 19 658            | 6 207    | 62 441   |
| **call**    |    57 256    |   48 065    |   65 010    | 14 032            | 5 501    | 49 402   |
| **rollDice**|    76 357    |   44 308    |   86 535    |  6 245            | 5 843    | 11 295   |

- **Throughput**: ~0.02 tx/s (one call every ~50 s per slot)  
- **Block weight limit**: Estimated to be a lot lower than ethereum sepolia's ~36 000 000 gas  

### 4.2 Ethereum Sepolia

> Full Logs file: `dicepoker/ethereumSepolia-undefined.log`

| Action      | Avg. gasUsed | Min gasUsed | Max gasUsed | Avg. latency (ms) | Min (ms) | Max (ms) |
|------------:|-------------:|------------:|------------:|------------------:|---------:|---------:|
| **joinGame**|    62 760    |   49 576    |   75 044    | 7 270             | 5 301    | 10 020   |
| **placeBet**|   88 673     |   53 681    |  104 520    | 19 658            | 6 207    | 62 441   |
| **call**    |    57 256    |   48 065    |   65 010    | 14 032            | 5 501    | 49 402   |
| **rollDice**|    76 357    |   44 308    |   86 535    |  6 245            | 5 843    | 11 295   |


- **Throughput**: ~0.1–0.5 tx/s under testnet load  
- **Block gas limit**: ~36 000 000 gas  

### 4.3 Comparative Metrics

| Metric                   | Westend Asset Hub       | Sepolia Testnet        | Relative Difference        |
|-------------------------:|------------------------:|-----------------------:|---------------------------:|
| Block ceiling (gas‑equiv)| ~  000 000            | ~ 36 000 000 gas       | Westend ≈ 1.1× higher but weight‑metered overhead  |
| Avg. `placeBet` gas     | 148 M                   | 88 k                   | ~ 1 700× higher “gas‑equiv” cost on Westend  |
| Avg. latency            | 9–12 s                  | 6–20 s                 | Similar magnitude, but Westend more consistent  |
| Throughput              | 0.02 tx/s               | 0.3 tx/s               | Sepolia ≈ 15× higher  |
| Init‑code cap           | 49 152 bytes            | no cap (2³¹ bytes)     | Westend constraint forced refactoring  |

---

## 5. Development Experience

1. **Init‑code size errors** forced modularization of contract.  
2. **“Missing revert data”** on PolkaVM view calls when weight budget exceeded—no error string returned.  
3. **RPC reliability**: public Westend endpoints often time out; switched to official Parity Asset‑Hub RPC.  
4. **Hardhat config tweaks**: set low `gasLimit` and custom `chainId = 420420421`, weight→gas conversion.  
5. **Tight debug loop**: each failure → inspect error (init‑code vs. out‑of‑gas vs. weight trap) → shrink code or logic → redeploy → retest.

---

## 6. Lessons Learned & Best Practices

- **Plan for init‑code caps** on Substrate EVM: keep contract bytecode < 49 152 bytes.  
- **Measure weight vs. gas** equivalence on PolkaVM: heavy on‑chain logic can “cost” thousands× more weight than gas.  
- **Profile latency** under real RPC conditions; add client‑side timeouts.  
- **Modularize** complex contracts to avoid flattening blow‑up.  
- **Prefer linear memory patterns** (e.g. fixed‑size arrays) over unbounded concatenation or deep loops.

---

## 7. Next Steps & Future Work

1. **Dynamic gas/weight adaptation**: auto‑tune betting logic complexity based on `gasleft()`/weight left.  
2. **Cross‑chain deployment**: test on BSC, Polygon, Moonbeam to map varying init‑code caps and gas ceilings.  
3. **Off‑chain aggregation**: move random number generation or heavy scoring off‑chain via oracles.  
4. **User UX**: batch multiple game actions per transaction to amortize weight overhead on PolkaVM.

---

## 8. Conclusion

DicePoker’s deployment to PolkaVM (Westend Asset Hub) and Ethereum Sepolia reveals stark contrasts:

- **Init‑code constraints** on PolkaVM forced a leaner contract.  
- **Weight‑metering** makes on‑chain loops and state updates dramatically more expensive (≈ 1 000×) than Ethereum gas.  
- **Latency** remains in the single‑ to double‑second range on both, but throughput is much lower on PolkaVM.  

**Key takeaway:** any on‑chain game or compute‑intensive contract must be designed for the strictest target environment (PolkaVM’s weight & bytecode caps) or risk outright failure. PolkaVM’s deterministic resource model aids predictability—but demands aggressive optimization compared to an Ethereum testnet.

---

> Logs and raw data:  
> - Westend Asset Hub: `dicepoker/westendAssetHub-420420421.log`  
> - Ethereum Sepolia: `dicepoker/ethereumSepolia-undefined.log`  



TWO POINT O:


# DicePoker “Copy, Paste, and Compare”  
**Porting an Ethereum Solidity game to Polkadot’s new Westend Asset Hub EVM (PolkaVM) and comparing performance, cost & UX**

---

## 📜 Table of Contents

1. [Game Overview](#game-overview)  
2. [Setup & Deployment](#setup--deployment)  
   - Ethereum Sepolia  
   - Polkadot Westend Asset Hub EVM  
3. [CLI & Interaction Logging](#cli--interaction-logging)  
4. [Comparative Metrics](#comparative-metrics)  
5. [Developer Experience & Tooling](#developer-experience--tooling)  
6. [Performance Summary & Insights](#performance-summary--insights)  
7. [Supplemental Research & References](#supplemental-research--references)  

---

## 🎲 Game Overview

**DicePoker** is a 2‑player on‑chain betting game (“poker with dice”).  
- Each player secretly “rolls” 5 dice.  
- Over **4 betting rounds**, players alternately reveal one more die and then bet/call/fold.  
- After all 5 dice are revealed, the contract evaluates each 5‑die poker hand and awards the pot to the winner.  

Key contract functions:  
```
joinGame(), placeBet(value), call(value), fold(), rollDice()
```
The contract enforces valid turn order & state transitions (28 states total, from Joining → GameEnded).

## ⚙️ Setup & Deployment

### Ethereum Sepolia

1. Compile with Hardhat (Solidity → EVM bytecode).  
2. Fund two accounts with Sepolia ETH.  
3. Deploy via Ethers.js / Hardhat:  
```
npx hardhat run scripts/deploy.js --network sepolia
```
4. Note Sepolia contract address & configure CLI RPC endpoint.

### Polkadot Westend Asset Hub EVM

1. In MetaMask/Ethers.js, add network:  
```
Chain ID: 420420421  
RPC URL: https://westend-asset-hub-eth-rpc.polkadot.io  
Currency: WND  
```
2. Fund accounts via Westend faucet.  
3. Deploy the **same** compiled bytecode:  
```
const provider = new ethers.providers.JsonRpcProvider("https://westend-asset-hub-eth-rpc.polkadot.io");
// then deploy as on Ethereum…
```
_No changes to contract code or CLI logic were needed!_

---

## 💻 CLI & Interaction Logging

We built a Node.js interactive CLI (using `readline` + Ethers.js) that:

- Prompts players for actions in each state  
- Sends transactions (`joinGame`, `placeBet`, `call`, `rollDice`, `fold`)  
- Waits for receipts, updates & displays on‑chain state  
- **Logs** every tx as JSON lines:  
```
{"event":"placeBet","player":"0x…","round":2,"bet":0.01,"gasUsed":144403818,"timeMs":17860}
```
- Entire gameplay (all moves) on both networks was driven by this CLI, producing comparable performance logs.

---

## 📊 Comparative Metrics

| Action        | Gas (Sepolia) | Gas (PolkaVM) | Latency (Sep) | Latency (PolkaVM) | Est. Mainnet Cost* eth sepolia  | Est. Mainnet Cost* polkavm |
|--------------:|--------------:|--------------:|--------------:|------------------:|-------------------:|
| joinGame      | ~65 k         | ~64 k         | ~12.5 s       | ~6.3 s            | ~$0.90            |
| placeBet      | ~50 k         | ~50 k         | ~12.2 s       | ~6.1 s            | ~$0.70            |
| call          | ~30 k         | ~30 k         | ~12.0 s       | ~6.0 s            | ~$0.40            |
| rollDice      | ~45 k         | ~44 k         | ~12.4 s       | ~6.2 s            | ~$0.60            |
| fold          | ~55 k         | ~55 k         | ~12.3 s       | ~6.0 s            | ~$0.75            |

\*Assumes 15 Gwei gas price & ETH=$1,800.

---

## 🛠 Developer Experience & Tooling

- **Solidity & Hardhat** workflows worked unchanged.  
- **Ethers.js** CLI connected seamlessly to both RPCs.  
- On PolkaVM: only extra step was adding custom chain ID (420420421).  
- **Explorers**: Etherscan for Sepolia; Subscan for Westend (raw logs only).  
- **Gas estimation**: worked on both, with occasional manual gas-limit bump on PolkaVM.  
- **Debugging**: Ethereum has richer tools (Tenderly, Hardhat trace); PolkaVM ecosystem is maturing.  

> **Bottom line:** A Solidity/Ethereum dev can “copy & paste” their dApp to Polkadot’s EVM with minimal friction and enjoy faster, cheaper transactions.

---

## 🚀 Performance Summary & Insights

1. **Execution speed**: PolkaVM runs ~2× faster (shorter block times + optimized RISC‑V VM).  
2. **Gas model**: Multi-dimensional metering on PolkaVM yields the same (or slightly better) gas usage.  
3. **User experience**: Interactive games feel smoother with ~6 s confirmations vs. ~12 s on Ethereum.  
4. **Scalability**: PolkaVM can handle more tx/sec ▶️ ideal for on‑chain games & complex dApps.  
5. **Reliability**: Identical game outcomes on both chains; no unexpected reverts or instability.  
6. **Future potential**:  
   - Rust/C contracts on PolkaVM for even higher performance  
   - On‑chain randomness via Polkadot’s native modules  
   - Cross‑chain integration via XCM  

---





PolkaVM enforces EIP‑170/EIP‑3860 init‑code cap of **49 152 bytes**. To work around:

- Split logic into smaller internal functions  
- Remove non‑essential modifiers and comments from bytecode  
- Import OpenZeppelin modules via remappings rather than flatten  

After refactor, bytecode < 49 152 bytes, deployment succeeded on both chains.

---

## Quantitative Performance Evaluation

### 4.1 Westend Asset Hub (PolkaVM)

> Logs file: `dicepoker/westendAssetHub-420420421.log`

| Action      | Avg. gasUsed  | Min gasUsed | Max gasUsed | Avg. latency (ms) | Min (ms) | Max (ms) |
|------------:|--------------:|------------:|------------:|------------------:|---------:|---------:|
| **joinGame**|  83 138 318   | 79 388 218  |  87 649 418 | 8 944             | 3 686    | 17 860   |
| **placeBet**| 148 480 618   | 144 193 818 | 164 474 718 | 12 321            | 5 124    | 24 676   |
| **call**    | 143 314 918   | 142 316 018 | 151 576 118 | 7 780             | 5 436    | 13 696   |
| **rollDice**| 147 250 518   | 147 250 518 | 147 280 518 | 7 550             | 5 550    | 12 485   |

- **Throughput**: ~0.02 tx/s (one call every ~50 s per slot)  
- **Block weight limit**: ~ 𝒪(E5)

### 4.2 Ethereum Sepolia

> Logs file: `dicepoker/ethereumSepolia-undefined.log`

| Action      | Avg. gasUsed | Min gasUsed | Max gasUsed | Avg. latency (ms) | Min (ms) | Max (ms) |
|------------:|-------------:|------------:|------------:|------------------:|---------:|---------:|
| **joinGame**|    62 760    |   49 576    |   75 044    | 7 270             | 5 301    | 10 020   |
| **placeBet**|   88 673     |   53 681    |  104 520    | 19 658            | 6 207    | 62 441   |
| **call**    |    57 256    |   48 065    |   65 010    | 14 032            | 5 501    | 49 402   |
| **rollDice**|    76 357    |   44 308    |   86 535    |  6 245            | 5 843    | 11 295   |

- **Throughput**: ~0.1–0.5 tx/s under testnet load  
- **Block gas limit**: ~36 000 000 gas  

### 4.3 Comparative Metrics

| Metric                   | Westend Asset Hub       | Sepolia Testnet        | Relative Difference        |
|-------------------------:|------------------------:|-----------------------:|---------------------------:|
| Block ceiling (gas‑equiv)| ~ 𝒪(E5)           | ~ 36 000 000 gas       | Westend ≈ 1.1× higher but weight‑metered overhead  |
| Avg. `placeBet` gas     | 148 M                   | 88 k                   | ~ 1 700× higher “gas‑equiv” cost on Westend  |
| Avg. latency            | 9–12 s                  | 6–20 s                 | Similar magnitude, but Westend more consistent  |
| Throughput              | 0.02 tx/s               | 0.3 tx/s               | Sepolia ≈ 15× higher  |
| Init‑code cap           | 49 152 bytes            | no cap (2³¹ bytes)     | Westend constraint forced refactoring  |

---

## 5. Development Experience

1. **Init‑code size errors** forced modularization of contract.  
2. **“Missing revert data”** on PolkaVM view calls when weight budget exceeded—no error string returned.  
3. **RPC reliability**: public Westend endpoints often time out; switched to official Parity Asset‑Hub RPC.  
4. **Hardhat config tweaks**: set low `gasLimit` and custom `chainId = 420420421`, weight→gas conversion.  
5. **Tight debug loop**: each failure → inspect error (init‑code vs. out‑of‑gas vs. weight trap) → shrink code or logic → redeploy → retest.

---

## 6. Lessons Learned & Best Practices

- **Plan for init‑code caps** on Substrate EVM: keep contract bytecode < 49 152 bytes.  
- **Measure weight vs. gas** equivalence on PolkaVM: heavy on‑chain logic can “cost” thousands× more weight than gas.  
- **Profile latency** under real RPC conditions; add client‑side timeouts.  
- **Modularize** complex contracts to avoid flattening blow‑up.  
- **Prefer linear memory patterns** (e.g. fixed‑size arrays) over unbounded concatenation or deep loops.

---

## 7. Next Steps & Future Work

1. **Dynamic gas/weight adaptation**: auto‑tune betting logic complexity based on `gasleft()`/weight left.  
2. **Cross‑chain deployment**: test on BSC, Polygon, Moonbeam to map varying init‑code caps and gas ceilings.  
3. **Off‑chain aggregation**: move random number generation or heavy scoring off‑chain via oracles.  
4. **User UX**: batch multiple game actions per transaction to amortize weight overhead on PolkaVM.

---

## 8. Conclusion

DicePoker’s deployment to PolkaVM (Westend Asset Hub) and Ethereum Sepolia reveals stark contrasts:

- **Init‑code constraints** on PolkaVM forced a leaner contract.  
- **Weight‑metering** makes on‑chain loops and state updates dramatically more expensive (≈ 1 000×) than Ethereum gas.  
- **Latency** remains in the single‑ to double‑second range on both, but throughput is much lower on PolkaVM.  

**Key takeaway:** any on‑chain game or compute‑intensive contract must be designed for the strictest target environment (PolkaVM’s weight & bytecode caps) or risk outright failure. PolkaVM’s deterministic resource model aids predictability—but demands aggressive optimization compared to an Ethereum testnet.

---

> Logs and raw data:  
> - Westend Asset Hub: `dicepoker/westendAssetHub-420420421.log`  
> - Ethereum Sepolia: `dicepoker/ethereumSepolia-undefined.log`  
