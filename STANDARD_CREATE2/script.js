// tests/script.js
require("dotenv").config();
const ethers = require("ethers");    // ethers v6

async function main() {
  // ─── Config ────────────────────────────────────────────────────────────────
  const RPC_URL          = process.env.RPC_URL
                         || "https://westend-asset-hub-eth-rpc.polkadot.io";
  const CHAIN_ID         = 420420421;
  const PRIVATE_KEY      = process.env.PRIVATE_KEY;
  const REGISTRY_ADDRESS = "0x9d9bfcd5bd51463e0533ef5bc8fbcc520e9c708d";

  if (!PRIVATE_KEY) {
    console.error("❌ Set PRIVATE_KEY in your .env");
    process.exit(1);
  }

  // ─── Provider & Wallet ────────────────────────────────────────────────────
  const provider = new ethers.JsonRpcProvider(RPC_URL, {
    chainId: CHAIN_ID,
    name:    "asset-hub-westend"
  });
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  // ─── Attach to the registry ─────────────────────────────────────────────────
  const registryAbi = [
    "function account(address,bytes32,uint256,address,uint256) view returns (address)",
    "function createAccount(address,bytes32,uint256,address,uint256) returns (address)"
  ];
  const registry = new ethers.Contract(REGISTRY_ADDRESS, registryAbi, wallet);

  // ─── Choose test parameters ────────────────────────────────────────────────
  const salt          = ethers.encodeBytes32String("demo-salt-1"); // v6
  const tokenContract = REGISTRY_ADDRESS; // any address works for testing
  const tokenId       = 42;

  // ─── 1) Predict the clone address ───────────────────────────────────────────
  const predicted = await registry.account(
    ethers.ZeroAddress,
    salt,
    CHAIN_ID,
    tokenContract,
    tokenId
  );
  console.log("🔮 Predicted clone address:", predicted);

  // ─── 2) Deploy + initialize (if not already) ────────────────────────────────
  console.log("⛓️  Sending createAccount()…");
  const tx = await registry.createAccount(
    ethers.ZeroAddress,
    salt,
    CHAIN_ID,
    tokenContract,
    tokenId,
    { gasLimit: 3_000_000 }
  );
  console.log("→ tx hash:", tx.hash);
  await tx.wait();
  console.log("✅ createAccount mined; clone is at:", predicted);

  // ─── 3) Read back clone’s stored token info ────────────────────────────────
  const accountAbi = [
    "function token() view returns (uint256 chainId, address tokenContract, uint256 tokenId)"
  ];
  const account = new ethers.Contract(predicted, accountAbi, provider);
  const info    = await account.token();
  console.log("🎫 account.token() →", {
    chainId:       info.chainId.toString(),
    tokenContract: info.tokenContract,
    tokenId:       info.tokenId.toString(),
  });
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
