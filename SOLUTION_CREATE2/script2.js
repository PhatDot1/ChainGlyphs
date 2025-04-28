// tests/script.js
require("dotenv").config();
const { ethers } = require("ethers");    // ethers v6

async function main() {
  // ─── Config ────────────────────────────────────────────────────────────────
  const RPC_URL          = process.env.RPC_URL
                         || "https://westend-asset-hub-eth-rpc.polkadot.io";
  const CHAIN_ID         = 420420421;
  const PRIVATE_KEY      = process.env.PRIVATE_KEY;
  const REGISTRY_ADDRESS = "0xbf48a74626f7e610d70c8772e9ad93292ccbd25b";

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

  // ─── 0) Wallet balance ─────────────────────────────────────────────────────
  const balance = await provider.getBalance(wallet.address);
  console.log("💰 Wallet balance:", balance.toString(), "Planck");

  // ─── Registry interface ────────────────────────────────────────────────────
  const registryAbi = [
    "function predictNextClone() view returns (address)",
    "function createAccount(address,bytes32,uint256,address,uint256) returns (address)",
    "function account(address,bytes32,uint256,address,uint256) view returns (address)"
  ];
  const registry = new ethers.Contract(REGISTRY_ADDRESS, registryAbi, wallet);

  // ─── Test parameters ───────────────────────────────────────────────────────
  const salt          = ethers.encodeBytes32String("demo-salt-1");
  const tokenContract = REGISTRY_ADDRESS; // dummy
  const tokenId       = 42;

  // ─── 1) Predict clone address ─────────────────────────────────────────────
  const predicted = await registry.predictNextClone();
  console.log("🔮 Predicted clone address:", predicted);

  // ─── 2) Compute fees ───────────────────────────────────────────────────────
  const existentialDeposit = 100_000_000_000_000_000n; // 0.1 WND in Planck
  const gasLimit           = 300_000_000_000;      // your upper-bound

  // fetch gasPrice
  const feeData = await provider.getFeeData();
  let gasPrice = feeData.gasPrice ?? feeData.maxFeePerGas ?? feeData.maxPriorityFeePerGas;
  if (gasPrice == null) throw new Error("Could not determine gasPrice");
  gasPrice = BigInt(gasPrice);

  const totalCost = gasPrice * BigInt(gasLimit) + existentialDeposit;
  console.log("⏱️ Estimated gasLimit:", gasLimit);
  console.log("⚙️ Current gasPrice:", gasPrice.toString(), "Planck");
  console.log("💸 Total TX cost (gasLimit×gasPrice + ED):", totalCost.toString(), "Planck");

  if (balance < totalCost) {
    console.error("❌ Insufficient balance to cover gas + ED");
    process.exit(1);
  }

  // ─── 3) Send createAccount (with ED + storageDepositLimit) ────────────────
  //           ^^^^^^^^^^^^^^^^^^^^^^^^
  console.log("⛓️ Sending createAccount()…");
  const tx = await wallet.sendTransaction({
    to:                  REGISTRY_ADDRESS,
    data:                registry.interface.encodeFunctionData("createAccount", [
                           ethers.ZeroAddress, salt, CHAIN_ID, tokenContract, tokenId
                         ]),
    gasLimit,
    gasPrice,
    value:               existentialDeposit,
    storageDepositLimit: existentialDeposit    // ← tell the node how much code+storage deposit to lock
  });
  console.log("→ tx hash:", tx.hash);
  await tx.wait();
  console.log("✅ createAccount mined");

  // ─── 4) Verify mapping & clone storage ─────────────────────────────────────
  const actual = await registry.account(
    ethers.ZeroAddress, salt, CHAIN_ID, tokenContract, tokenId
  );
  console.log("🪄 registry.account() →", actual);
  console.log(
    actual.toLowerCase() === predicted.toLowerCase()
      ? "🎯 Prediction confirmed!"
      : "⚠️ Prediction mismatch!"
  );

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
