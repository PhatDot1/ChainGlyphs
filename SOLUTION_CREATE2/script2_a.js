// tests/script-optionA.js
require("dotenv").config();
const { ethers } = require("ethers");

async function main() {
  const RPC_URL          = process.env.RPC_URL || "https://westend-asset-hub-eth-rpc.polkadot.io";
  const CHAIN_ID         = 420420421;
  const PRIVATE_KEY      = process.env.PRIVATE_KEY;
  const REGISTRY_ADDRESS = "0xbf48a74626f7e610d70c8772e9ad93292ccbd25b";

  if (!PRIVATE_KEY) {
    console.error("❌ Set PRIVATE_KEY in your .env"); process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: "asset-hub-westend" });
  const wallet   = new ethers.Wallet(PRIVATE_KEY, provider);

  const balance = await provider.getBalance(wallet.address);
  console.log("💰 Balance:", balance.toString(), "Planck");

  const registryAbi = [
    "function predictNextClone() view returns (address)",
    "function createAccount(address,bytes32,uint256,address,uint256) returns (address)",
    "function account(address,bytes32,uint256,address,uint256) view returns (address)"
  ];
  const registry = new ethers.Contract(REGISTRY_ADDRESS, registryAbi, wallet);

  const salt          = ethers.encodeBytes32String("demo-salt-1");
  const tokenContract = REGISTRY_ADDRESS;
  const tokenId       = 42;

  const predicted = await registry.predictNextClone();
  console.log("🔮 Predicted:", predicted);

  const existentialDeposit = 100_000_000_000_000_000n;
  const gasLimit           = 600_000_000_000_000;
  const feeData = await provider.getFeeData();
  let   gasPrice = feeData.gasPrice ?? feeData.maxFeePerGas ?? feeData.maxPriorityFeePerGas;
  gasPrice = BigInt(gasPrice);

  console.log("⏱️ gasLimit:", gasLimit, "⚙️ gasPrice:", gasPrice.toString());

  // direct contract call keeps the data
  const tx = await registry.createAccount(
    ethers.ZeroAddress,
    salt,
    CHAIN_ID,
    tokenContract,
    tokenId,
    {
      gasLimit,
      gasPrice,
      value:               existentialDeposit,
      storageDepositLimit: existentialDeposit
    }
  );
  console.log("→ tx hash:", tx.hash);
  await tx.wait();
  console.log("✅ mined");

  const actual = await registry.account(ethers.ZeroAddress, salt, CHAIN_ID, tokenContract, tokenId);
  console.log("🪄 account:", actual);
}

main().catch(e => { console.error(e); process.exit(1); });
