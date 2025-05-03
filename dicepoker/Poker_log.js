
// Interactive CLI for the DicePoker contract w/ simple logging

require("dotenv").config();
const hre      = require("hardhat");
const { ethers, network } = hre;
const fs       = require("fs");
const path     = require("path");
const readline = require("readline");

// config
const CONTRACT_ADDRESS = "0x1ce43d3e45303569bafaba4c4ddef9baf1d7a73f";
const ZERO_ADDRESS     = "0x0000000000000000000000000000000000000000";
const STATE_NAMES = [
  "Joining",
  "Player1Bet1","Player2BetOrCall1","Player1RaiseOrCall1","Player2RaiseOrCall1",
  "Player1RollFirst","Player2RollFirst",
  "Player1Bet2","Player2BetOrCall2","Player1RaiseOrCall2","Player2RaiseOrCall2",
  "Player1RollLast","Player2RollLast",
  "DetermineWinner","Tie","GameEnded"
];

async function main() {
  console.log(`\n🎲 DicePoker CLI on ${network.name}`);
  console.log("🏆 Win by highest total of your 5 dice; tie splits the pot.\n");

  // ── prepare logs directory & file ──
  const logsDir = path.join(__dirname, "logs");
  fs.mkdirSync(logsDir, { recursive: true });
  const chainId = network.config.chainId;
  const logFile = path.join(logsDir, `${network.name}-${chainId}.log`);

  async function logTx(action, receipt, startMs, endMs, params = {}) {
    const entry = [
      new Date().toISOString(),
      action,
      `params=${JSON.stringify(params)}`,
      `receipt=${JSON.stringify(receipt)}`,  // Raw receipt logging, safe for later parsing
      `timeMs=${(endMs - startMs).toString()}`
    ].join(" | ") + "\n";
    
    fs.appendFileSync(logFile, entry);
  }
  
  
  

  // ── pick your account ──
  const signers = await ethers.getSigners();
  console.log("Available accounts:");
  signers.forEach((s,i) => console.log(`  [${i}] ${s.address}`));
  const rl0 = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask0 = q => new Promise(res => rl0.question(q, res));
  let idx;
  while (true) {
    const a = await ask0("Select account index: ");
    idx = parseInt(a.trim(), 10);
    if (!isNaN(idx) && idx>=0 && idx<signers.length) break;
    console.log("Invalid, try again.");
  }
  rl0.close();
  const user = signers[idx];
  console.log(`Using account: ${user.address}\n`);

  // ── attach to contract ──
  const poker = await ethers.getContractAt("DicePoker", CONTRACT_ADDRESS, user);

  // helper: fetch full 5-die array
  async function getDice(pi) {
    const arr = [];
    for (let j = 0; j < 5; j++) {
      arr.push(Number(await poker.playerDice(pi, j)));
    }
    return arr;
  }
  // helper: mask unrevealed dice
  function maskDice(arr, first, last) {
    return arr.map((d,i) => i<3 ? (first?d:"–") : (last?d:"–"));
  }

  // ── main loop ──
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
      `Dice:    P1=[${maskDice(raw1, firstRolled[0], lastRolled[0]).join(", ")}]  `+
      `P2=[${maskDice(raw2, firstRolled[1], lastRolled[1]).join(", ")}]`
    );

    // build menu
    const menu = [];
    if (state===0 && meIdx===-1 && players.includes(ZERO_ADDRESS)) {
      menu.push({desc:"Join Game", fn:joinGame});
    }
    if ((((state>=1&&state<=4)||(state>=7&&state<=10))) && meIdx!==-1) {
      const turn = [1,3,7,9].includes(state)?0:1;
      if (meIdx===turn) {
        menu.push({desc:"Place/Raise Bet", fn:placeBet});
        menu.push({desc:"Call",           fn:callBet});
        menu.push({desc:"Fold",           fn:foldGame});
      }
    }
    if ([5,6].includes(state) && meIdx!==-1) {
      const turn = state===5?0:1;
      if (meIdx===turn) menu.push({desc:"Reveal 3 dice", fn:rollDice});
    }
    if ([11,12].includes(state) && meIdx!==-1) {
      const turn = state===11?0:1;
      if (meIdx===turn) menu.push({desc:"Reveal 2 dice & finish", fn:rollDice});
    }
    menu.push({desc:"Show Hands", fn:showHands});
    if (state===STATE_NAMES.indexOf("GameEnded")) {
      menu.push({desc:"Reset Game (if ≥5s)", fn:resetGame});
    }
    menu.push({desc:"Exit", fn:exitCLI});

    console.log("\nOptions:");
    menu.forEach((m,i)=>console.log(`  ${i+1}) ${m.desc}`));
    const choice = parseInt(await ask("Choice: "),10);
    if (isNaN(choice)||choice<1||choice>menu.length) {
      console.log("Invalid"); continue;
    }
    try {
      await menu[choice-1].fn();
    } catch(err) {
      console.error("⚠️", err.message||err);
    }
  }

  // ── Handlers ──
  async function joinGame() {
    const start = Date.now();
    const tx    = await poker.joinGame();
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("joinGame", rcpt, start, end);
    console.log("✅ Joined game");
  }

  async function placeBet() {
    const amt   = await ask("Amount (ETH): ");
    const wei   = ethers.parseEther(amt);
    const start = Date.now();
    const tx    = await poker.placeBet({ value:wei });
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("placeBet", rcpt, start, end, {amount:amt});
    console.log(`✅ Bet ${amt} ETH`);
  }

  async function callBet() {
    const playersOnChain = [await poker.players(0),await poker.players(1)];
    const betsArr        = [await poker.bets(0),    await poker.bets(1)];
    const current        = await poker.currentBet();
    const me             = playersOnChain.map(p=>p.toLowerCase()).indexOf(user.address.toLowerCase());
    const toCall         = current - betsArr[me];
    if (toCall===0n) return console.log("🔔 Nothing to call");
    console.log(`Calling ${ethers.formatEther(toCall)} ETH…`);
    const start = Date.now();
    const tx    = await poker.call({ value:toCall });
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("call", rcpt, start, end, {amount:ethers.formatEther(toCall)});
    console.log("✅ Called");
  }

  async function foldGame() {
    const start = Date.now();
    const tx    = await poker.fold();
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("fold", rcpt, start, end);
    console.log("💥 You folded");
  }

  async function rollDice() {
    const prev  = Number(await poker.currentState());
    const start = Date.now();
    const tx    = await poker.rollDice();
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("rollDice", rcpt, start, end);
    console.log("🎲 Dice rolled");

    if (prev===12) {
      const h1   = await getDice(0), h2 = await getDice(1);
      const sum1 = h1.reduce((a,b)=>a+b,0), sum2 = h2.reduce((a,b)=>a+b,0);
      console.log("\n🏁 Final Hands:");
      console.log(` P1: ${h1.join(", ")}  (sum=${sum1})`);
      console.log(` P2: ${h2.join(", ")}  (sum=${sum2})`);
      console.log(sum1>sum2?"🏆 Winner: P1":sum2>sum1?"🏆 Winner: P2":"🤝 It's a tie — pot split");
    }
  }

  async function showHands() {
    const h1 = await getDice(0), h2 = await getDice(1);
    console.log("P1 Dice:",h1.join(", "));
    console.log("P2 Dice:",h2.join(", "));
  }

  async function resetGame() {
    console.log("Resetting game (if ≥5s have passed) …");
    const tx   = await poker.resetIfExpired();
    await tx.wait();
    console.log("✅ Game reset. Back to Joining.");
  }

  function exitCLI() {
    console.log("Exiting");
    process.exit(0);
  }
}

main().catch(e=>{
  console.error(e);
  process.exit(1);
});
