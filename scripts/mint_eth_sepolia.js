// scripts/5_mint.js
require("dotenv").config();
const { ethers } = require("ethers");

// simple sleep helper
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// sample tx/s over the last `sampleSize` blocks with `delayMs` between requests
async function sampleTxThroughput(provider, sampleSize = 20, delayMs = 200) {
  const latest   = await provider.getBlockNumber();
  const startNum = Math.max(0, latest - sampleSize);
  const startBlk = await provider.getBlock(startNum);
  let txCount    = 0;

  for (let i = startNum + 1; i <= latest; i++) {
    await sleep(delayMs);
    const blk = await provider.getBlock(i);
    txCount += blk.transactions.length;
  }

  const endBlk  = await provider.getBlock(latest);
  const elapsed = (endBlk.timestamp - startBlk.timestamp) || 1;
  return txCount / elapsed;
}

async function main() {
  const RPC_URL     = process.env.EVM_RPC_URL;
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  if (!RPC_URL || !PRIVATE_KEY) {
    throw new Error("❌ Missing EVM_RPC_URL or PRIVATE_KEY in .env");
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL, "sepolia");
  const wallet   = new ethers.Wallet(PRIVATE_KEY, provider);
  const nft      = new ethers.Contract(
    // your new AsciiChainEvalNFT address:
    "0x585eBA013eb7Ec2bE10C335186a4bB372B181D60",
    [
      "function mintPrice() view returns (uint256)",
      "function safeMintWithMetrics(address to) payable",
      "function safeMintWithParams(address to,uint256 time,uint256 gaslimit,uint256 baseFee,uint256 gasPrice,uint256 priorityFee,uint256 chainId,uint256 diskSize,uint256 txThroughput,uint256 archiveSize) payable",
      "function tokenURI(uint256 tokenId) view returns (string)",
      "event ChainMetrics(uint256 gaslimit,uint256 baseFee,uint256 gasPrice,uint256 chainId,address indexed caller)",
      "event Transfer(address indexed from,address indexed to,uint256 indexed tokenId)"
    ],
    wallet
  );

  // 1) fetch mint price
  const price = await nft.mintPrice();
  console.log(`Mint price: ${ethers.formatEther(price)} ETH\n`);

  // ── Phase 1: emit & capture on-chain metrics ───────────────────────────────
  console.log("▶️  Phase1: safeMintWithMetrics()");
  const startTime = Date.now();
  const tx1 = await nft.safeMintWithMetrics(wallet.address, { value: price });
  console.log("   tx1 hash:", tx1.hash);
  const r1 = await tx1.wait();
  const durationMs = Date.now() - startTime;
  console.log("✅ Phase1 mined in block", r1.blockNumber);
  console.log(`   ⏱  Phase1 duration: ${durationMs} ms`);

  // find and parse the ChainMetrics event
  const metricsEvt = r1.logs
    .map(l => {
      try { return nft.interface.parseLog(l); }
      catch { return null; }
    })
    .find(e => e && e.name === "ChainMetrics");

  if (!metricsEvt) {
    console.error("❌ ChainMetrics event not found");
    process.exit(1);
  }

  // destructure on-chain metrics
  const { gaslimit, baseFee, gasPrice, chainId } = metricsEvt.args;
  const priorityFee = gasPrice - baseFee; // bigint subtraction

  console.log("\n📊 On-chain metrics:");
  console.log("  gaslimit:   ", gaslimit.toString());
  console.log("  baseFee:    ", ethers.formatUnits(baseFee, "gwei"),   "gwei");
  console.log("  gasPrice:   ", ethers.formatUnits(gasPrice, "gwei"),   "gwei");
  console.log("  priorityFee:", ethers.formatUnits(priorityFee, "gwei"),"gwei");
  console.log("  chainId:    ", chainId.toString());

  // ── off-chain sample of tx/s ────────────────────────────────────────────────
  console.log("\n⛓  Sampling last 20 blocks for tx/s (200 ms delay)…");
  const txps = await sampleTxThroughput(provider, 20, 200);
  console.log(`   ≈ ${txps.toFixed(2)} tx/s`);

  // ── Phase 2: finalize mint with ALL params ─────────────────────────────────
  console.log("\n▶️  Phase2: safeMintWithParams()");
  const tx2 = await nft.safeMintWithParams(
    wallet.address,
    durationMs,            // real Phase1 duration
    gaslimit,
    baseFee,
    gasPrice,
    priorityFee,
    chainId,
    0,                     // diskSize (hard-coded)
    Math.floor(txps),      // txThroughput
    0,                     // archiveSize (hard-coded)
    { value: price }
  );
  console.log("   tx2 hash:", tx2.hash);
  const r2 = await tx2.wait();
  console.log("✅ Phase2 mined in block", r2.blockNumber);

  // pull out your new tokenId from the Transfer event
  const transferEvt = r2.logs
    .map(l => {
      try { return nft.interface.parseLog(l); }
      catch { return null; }
    })
    .find(e => e && e.name === "Transfer");

  if (!transferEvt) {
    console.error("❌ Transfer event not found");
    process.exit(1);
  }
  const tokenId = transferEvt.args.tokenId;
  console.log("\n🎟  New tokenId:", tokenId.toString());

  // fetch & display metadata
  const uri  = await nft.tokenURI(tokenId);
  console.log("\n🖼  tokenURI:", uri);
  const b64  = uri.split(",")[1];
  const meta = JSON.parse(Buffer.from(b64, "base64").toString());
  console.log("\n📜 Metadata JSON:\n", JSON.stringify(meta, null, 2));

  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
