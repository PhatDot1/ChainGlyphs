const { ApiPromise, WsProvider, HttpProvider } = require('@polkadot/api');

async function main() {
  const endpoint = process.argv[2];
  if (!endpoint) {
    console.error('Usage: node PWPG.js <ws://… or https://… endpoint>');
    process.exit(1);
  }

  // build provider
  const provider = endpoint.startsWith('ws')
    ? new WsProvider(endpoint)
    : new HttpProvider(endpoint);

  // log WS events so we know if/when it connects
  if (provider.on) {
    provider.on('connected', () => console.log('[WS] connected'));
    provider.on('error', (err) => console.error('[WS] error', err.message));
    provider.on('disconnected', () => console.log('[WS] disconnected'));
  }

  console.log(`Connecting to ${endpoint}…`);

  // wrap create in a 10s timeout so it won’t hang forever
  const createApi = ApiPromise.create({ provider });
  const timeout = new Promise((_, rej) =>
    setTimeout(() => rej(new Error('ApiPromise.create timed out')), 10_000)
  );

  let api;
  try {
    api = await Promise.race([createApi, timeout]);
  } catch (err) {
    console.error('Failed to establish API:', err.message);
    process.exit(1);
  }

  // now wait for the API to be fully ready
  try {
    await api.isReady;
    console.log('API is ready — dumping constants:\n');
  } catch (err) {
    console.error('API failed during isReady:', err.message);
    process.exit(1);
  }

  // dump the constants so we can see exactly where weightPerGas lives
  for (const [palletName, pallet] of Object.entries(api.consts)) {
    console.log(`== ${palletName} ==`);
    for (const [cName, c] of Object.entries(pallet)) {
      console.log(`  - ${cName}: ${c.toString()}`);
    }
    console.log();
  }

  await api.disconnect();
  process.exit(0);
}

main().catch((err) => {
  console.error('Fatal error in main():', err);
  process.exit(1);
});
