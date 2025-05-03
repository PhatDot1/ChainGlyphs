1. 
Create2 issue- 


2. ChainGlyphs: Live‑Data NFT's Forged by Blockchain Performance
EVM sepolia:

Polkadot:
The EVM gas limit seems very restrictive - I estimated it to be right next to the default‐test value of 20 000 (compared to sepolia's 30 000 000)
41 × 82 dynamic string + Base64 loop consumed well over 786 432 gas

Due to this, had to compromise the contract, restricting it further and further until its deployable
Reduced contract ->
≈ 34× fewer cell‑computations

≈ 340× fewer string‑concats

≈ 1 000–1 500× lower total gas/memory footprint


3. DicePoker: A simple on-chain dice poker game
