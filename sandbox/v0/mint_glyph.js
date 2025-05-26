// scripts/mint_glyph.js
require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
  const [,, seedArg] = process.argv;
  if (!seedArg) {
    console.error("Usage: node mint_glyph.js <seed>");
    process.exit(1);
  }
  const seed = BigInt(seedArg);

  // ─── Configuration ─────────────────────────────────────────────────────────
  const RPC_URL     = process.env.RPC_URL     || "https://arbitrum-sepolia.infura.io/v3/YOUR_INFURA_KEY";
  const PRIVATE_KEY = process.env.PRIVATE_KEY;
  const CONTRACT    = "0x19054030669efBFc413bA3729b63eCfD3Bdc22B5";  // your deployed Autoglyphs

  if (!PRIVATE_KEY) {
    console.error("❌ Set PRIVATE_KEY in your .env");
    process.exit(1);
  }

  // ─── Setup provider & wallet ───────────────────────────────────────────────
  const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: 421613, name: "arbitrumSepolia" });
  const wallet   = new ethers.Wallet(PRIVATE_KEY, provider);

  console.log("👤 Minting from:", wallet.address);

  // ─── Attach to Autoglyphs contract ─────────────────────────────────────────
  const abi = [
    "function createGlyph(uint256 seed) payable returns (string memory)",
    "event Generated(uint256 indexed id, address indexed creator, string uri)"
  ];
  const art = new ethers.Contract(CONTRACT, abi, wallet);

  // ─── Send transaction ───────────────────────────────────────────────────────
  const price = ethers.parseEther("0.02");  
  console.log(`⛓️  Sending createGlyph(${seed}) with value=0.02 ETH…`);
  const tx = await art.createGlyph(seed, { value: price });
  console.log("→ tx hash:", tx.hash);

  const receipt = await tx.wait();
  console.log("✅ Minted in block", receipt.blockNumber);

  // ─── Decode Generated event ─────────────────────────────────────────────────
  for (const ev of receipt.events || []) {
    if (ev.event === "Generated") {
      console.log(`🎨 Glyph #${ev.args.id.toString()} URI:`);
      console.log(ev.args.uri);
    }
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
