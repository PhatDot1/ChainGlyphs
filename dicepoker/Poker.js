
// 2 rounds of betting, 3 dice reveal, 2 more rounds of betting, end. - highest wins.
// configred for HH environment

require("dotenv").config();
const hre = require("hardhat");
const { ethers, network } = hre;
const readline = require("readline");

// === CONFIGURATION ===
const CONTRACT_ADDRESS = "0x50ecc9DB42396BCd3461C41025eF3603eEBc31d6";
const ZERO_ADDRESS     = "0x0000000000000000000000000000000000000000";
const STATE_NAMES = [
  "Joining",
  "Player1Bet1",
  "Player2BetOrCall1",
  "Player1RaiseOrCall1",
  "Player2RaiseOrCall1",
  "Player1RollFirst",
  "Player2RollFirst",
  "Player1Bet2",
  "Player2BetOrCall2",
  "Player1RaiseOrCall2",
  "Player2RaiseOrCall2",
  "Player1RollLast",
  "Player2RollLast",
  "DetermineWinner",
  "Tie",
  "GameEnded"
];

async function main() {
  console.log(`\n🎲 DicePoker CLI on ${network.name}`);
  console.log("🏆 Win by highest total of your 5 dice; tie splits the pot.\n");

  // — pick your account —
  const signers = await ethers.getSigners();
  console.log("Available accounts:");
  signers.forEach((s,i) => console.log(`  [${i}] ${s.address}`));
  const rl0 = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask0 = q => new Promise(res => rl0.question(q, res));
  let idx;
  while (true) {
    const a = await ask0("Select account index: ");
    idx = parseInt(a.trim(), 10);
    if (!isNaN(idx) && idx >= 0 && idx < signers.length) break;
    console.log("Invalid, try again.");
  }
  rl0.close();
  const user = signers[idx];
  console.log(`Using account: ${user.address}\n`);

  // — attach to contract —
  const poker = await ethers.getContractAt("DicePoker", CONTRACT_ADDRESS, user);

  // helper: fetch the full 5-die array for a player
  async function getDice(playerIndex) {
    const arr = [];
    for (let j = 0; j < 5; j++) {
      const d = await poker.playerDice(playerIndex, j);
      arr.push(Number(d)); // cast BigNumber → JS number
    }
    return arr;
  }

  // helper: mask unrevealed dice
  function maskDice(arr, first, last) {
    return arr.map((d,i) => {
      if (i < 3) return first ? d : "–";
      return last ? d : "–";
    });
  }

  // — main loop —
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = q => new Promise(res => rl.question(q, res));

  while (true) {
    const state        = Number(await poker.currentState());
    const players      = [await poker.players(0), await poker.players(1)];
    const bets         = [await poker.bets(0),    await poker.bets(1)];
    const firstRolled  = [await poker.hasRolledFirst(0), await poker.hasRolledFirst(1)];
    const lastRolled   = [await poker.hasRolledLast(0),  await poker.hasRolledLast(1)];
    const raw1         = await getDice(0);
    const raw2         = await getDice(1);
    const meIdx        = players.findIndex(p => p.toLowerCase() === user.address.toLowerCase());

    console.log(`\n=== ${STATE_NAMES[state]} ===`);
    console.log(`Players: P1=${players[0]}  P2=${players[1]}`);
    console.log(`Bets:    P1=${ethers.formatEther(bets[0])} ETH  P2=${ethers.formatEther(bets[1])} ETH`);
    console.log(
      `Dice:    P1=[${maskDice(raw1, firstRolled[0], lastRolled[0]).join(", ")}]  ` +
      `P2=[${maskDice(raw2, firstRolled[1], lastRolled[1]).join(", ")}]`
    );

    // build menu
    const menu = [];
    if (state === 0 && meIdx === -1 && players.includes(ZERO_ADDRESS)) {
      menu.push({ desc: "Join Game", fn: joinGame });
    }
    if (((state >= 1 && state <= 4) || (state >= 7 && state <= 10)) && meIdx !== -1) {
      const turn = [1,3,7,9].includes(state) ? 0 : 1;
      if (meIdx === turn) {
        menu.push({ desc: "Place/Raise Bet", fn: placeBet });
        menu.push({ desc: "Call",            fn: callBet });
        menu.push({ desc: "Fold",            fn: foldGame });
      }
    }
    if ([5,6].includes(state) && meIdx !== -1) {
      const turn = state === 5 ? 0 : 1;
      if (meIdx === turn) menu.push({ desc: "Reveal 3 dice", fn: rollDice });
    }
    if ([11,12].includes(state) && meIdx !== -1) {
      const turn = state === 11 ? 0 : 1;
      if (meIdx === turn) menu.push({ desc: "Reveal 2 dice & finish", fn: rollDice });
    }
    // always allow show hands & exit
    menu.push({ desc: "Show Hands", fn: showHands });
    // **new**: if game over, allow manual reset
    if (state === STATE_NAMES.indexOf("GameEnded")) {
      menu.push({ desc: "Reset Game (if ≥5 s since end)", fn: resetGame });
    }
    menu.push({ desc: "Exit", fn: exitCLI });

    console.log("\nOptions:");
    menu.forEach((m,i) => console.log(`  ${i+1}) ${m.desc}`));
    const choice = parseInt(await ask("Choice: "), 10);
    if (isNaN(choice) || choice < 1 || choice > menu.length) {
      console.log("Invalid"); continue;
    }

    try {
      await menu[choice-1].fn();
    } catch (err) {
      console.error("⚠️", err.message || err);
    }
  }

  // — Handlers —

  async function joinGame() {
    await (await poker.joinGame()).wait();
    console.log("✅ Joined game");
  }

  async function placeBet() {
    const amt = await ask("Amount (ETH): ");
    const wei = ethers.parseEther(amt);
    await (await poker.placeBet({ value: wei })).wait();
    console.log(`✅ Bet ${amt} ETH`);
  }

  async function callBet() {
    const playersOnChain = [await poker.players(0), await poker.players(1)];
    const betsArr        = [await poker.bets(0),    await poker.bets(1)];
    const current        = await poker.currentBet();
    const me             = playersOnChain
      .map(p => p.toLowerCase())
      .indexOf(user.address.toLowerCase());
    const toCall = current - betsArr[me];
    if (toCall === 0n) return console.log("🔔 Nothing to call");
    console.log(`Calling ${ethers.formatEther(toCall)} ETH…`);
    await (await poker.call({ value: toCall })).wait();
    console.log("✅ Called");
  }

  async function foldGame() {
    await (await poker.fold()).wait();
    console.log("💥 You folded");
  }

  async function rollDice() {
    const prev = Number(await poker.currentState());
    await (await poker.rollDice()).wait();
    console.log("🎲 Dice rolled");

    // after second reveal (prev===12) show finals & winner
    if (prev === 12) {
      const h1   = await getDice(0);
      const h2   = await getDice(1);
      const sum1 = h1.reduce((a,b)=>a+b, 0);
      const sum2 = h2.reduce((a,b)=>a+b, 0);
      console.log("\n🏁 Final Hands:");
      console.log(` P1: ${h1.join(", ")}  (sum=${sum1})`);
      console.log(` P2: ${h2.join(", ")}  (sum=${sum2})`);
      if (sum1 > sum2)      console.log("🏆 Winner: P1");
      else if (sum2 > sum1) console.log("🏆 Winner: P2");
      else                  console.log("🤝 It's a tie — pot split");
    }
  }

  async function showHands() {
    const h1 = await getDice(0);
    const h2 = await getDice(1);
    console.log("P1 Dice:", h1.join(", "));
    console.log("P2 Dice:", h2.join(", "));
  }

  // **new**: call the 5s-reset
  async function resetGame() {
    console.log("Resetting game (if 5 s have passed) …");
    await (await poker.resetIfExpired()).wait();
    console.log("✅ Game reset. Back to Joining.");
  }

  function exitCLI() {
    console.log("Exiting");
    process.exit(0);
  }
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
