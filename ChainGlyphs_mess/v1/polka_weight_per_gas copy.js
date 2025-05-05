
const { ApiPromise, WsProvider } = require('@polkadot/api');

async function main() {
  // Connect to Westend Asset‑Hub
  const wsProvider = new WsProvider('wss://westend-westend-asset-hub-rpc.polkadot.io:443');
  const api = await ApiPromise.create({ provider: wsProvider });

  // Read weightPerGas constant from EVM pallet
  const weightPerGas = api.consts.evm.weightPerGas;

  console.log(`weightPerGas = ${weightPerGas.toString()} weight‑units per 1 gas`);

  await api.disconnect();
}

main().catch(console.error);