import { config } from "./config.mjs";
import { encode, uintAt, addressAt, stringAt, parseAmount, formatAmount, ethPerToken, minOutput, validateConfig, httpRpc, isAddress } from "./rpc.mjs";

const $ = id => document.getElementById(id);
let account = null, quote = null, ready = false, busy = false, epoch = 0;
const poolArgs = () => [config.pool.fee, config.pool.tickSpacing, config.pool.hooks];
const readRpc = (method, params) => httpRpc(config.rpcUrl, method, params);
const call = (to, name, args = [], block = "latest") => readRpc("eth_call", [{ to, data: encode(name, args) }, block]);
const wallet = () => {
  if (!window.ethereum) throw new Error("Install an Ethereum wallet to connect.");
  return window.ethereum;
};
const walletRpc = (method, params = []) => wallet().request({ method, params });
const message = (id, text, error = false) => { $(id).textContent = text; $(id).classList.toggle("error", error); };

function controls() {
  $("review").disabled = !ready || busy;
  $("execute").disabled = busy || !quote;
  $("connect").disabled = busy;
  for (const id of ["amount", "direction", "slippage"]) $(id).disabled = busy;
}

function invalidate() {
  epoch++;
  quote = null;
  $("quote").textContent = "—";
  $("minimum").textContent = "—";
  $("execute").hidden = true;
  $("review").hidden = false;
  controls();
}

async function checkWallet() {
  if (BigInt(await walletRpc("eth_chainId")) !== 1n) throw new Error("Switch your wallet to Ethereum mainnet.");
  const accounts = await walletRpc("eth_accounts");
  if (!accounts.length || !account || accounts[0].toLowerCase() !== account.toLowerCase()) throw new Error("Wallet changed. Connect again and request a fresh quote.");
  return accounts[0];
}

async function connect() {
  const accounts = await walletRpc("eth_requestAccounts");
  if (!accounts.length || !isAddress(accounts[0])) throw new Error("No wallet account selected.");
  if (BigInt(await walletRpc("eth_chainId")) !== 1n) {
    await walletRpc("wallet_switchEthereumChain", [{ chainId: "0x1" }]);
  }
  account = accounts[0];
  await checkWallet();
  $("connect").textContent = account.slice(0, 6) + "…" + account.slice(-4);
  await refreshBalance();
}

async function refreshBalance() {
  if (!account || !ready) return;
  const forAccount = account;
  const buy = $("direction").value === "buy";
  const result = buy ? await readRpc("eth_getBalance", [forAccount, "latest"])
    : await call(config.token, "balanceOf", [forAccount]);
  if (account !== forAccount || buy !== ($("direction").value === "buy")) return;
  $("balance").textContent = "Balance: " + formatAmount(BigInt(result)) + (buy ? " ETH · keep some for gas" : " SWARM");
}

async function refreshStats() {
  validateConfig(config);
  if (BigInt(await readRpc("eth_chainId", [])) !== 1n) throw new Error("The configured connection is not Ethereum mainnet.");
  const block = await readRpc("eth_blockNumber", []);
  const results = await Promise.all([
    call(config.token, "name", [], block), call(config.token, "symbol", [], block), call(config.token, "decimals", [], block),
    call(config.token, "totalSupply", [], block), call(config.token, "totalBurned", [], block),
    call(config.swap, "poolState", poolArgs(), block), call(config.swap, "token", [], block),
    call(config.swap, "manager", [], block), call(config.token, "poolManager", [], block),
  ]);
  const [name, symbol, decimals, supply, burned, state, swapToken, swapManager, manager] = results;
  if (stringAt(name) !== "swarm" || stringAt(symbol) !== "SWARM" || uintAt(decimals) !== 18n
    || uintAt(supply) !== 1_000_000_000n * 10n ** 18n || addressAt(swapToken) !== config.token.toLowerCase()
    || addressAt(swapManager) !== addressAt(manager)) throw new Error("The published contracts do not match this launch.");
  const price = ethPerToken(uintAt(state));
  $("metadata").textContent = stringAt(name) + " / " + stringAt(symbol);
  $("supply").textContent = formatAmount(uintAt(supply));
  $("burned").textContent = formatAmount(uintAt(burned));
  $("burn-note").textContent = "SWARM · automatic transfer burns";
  $("price").textContent = formatAmount(price, 12);
  message("data-status", "Live on Ethereum · block " + BigInt(block).toLocaleString() + " · updated " + new Date().toLocaleTimeString());
  $("token-link").href = "https://etherscan.io/address/" + config.token;
  $("token-link").hidden = false;
  ready = true;
  controls();
  await refreshBalance();
}

async function waitReceipt(hash) {
  $("transaction").href = "https://etherscan.io/tx/" + hash;
  $("transaction").hidden = false;
  for (let attempt = 0; attempt < 120; attempt++) {
    const receipt = await readRpc("eth_getTransactionReceipt", [hash]);
    if (receipt) {
      if (BigInt(receipt.status) !== 1n) throw new Error("Transaction reverted. Funds were not swapped; network gas was spent.");
      return receipt;
    }
    await new Promise(resolve => setTimeout(resolve, 3000));
  }
  throw new Error("Still pending. Check the transaction link before submitting another transaction.");
}

async function send(tx) {
  await checkWallet();
  const actionEpoch = epoch;
  const gas = BigInt(await walletRpc("eth_estimateGas", [tx]));
  await checkWallet();
  if (epoch !== actionEpoch) throw new Error("Wallet or trade changed. Review again.");
  return walletRpc("eth_sendTransaction", [{ ...tx, gas: "0x" + (gas * 120n / 100n).toString(16) }]);
}

async function review(event) {
  event.preventDefault();
  await action(async () => {
    invalidate();
    if (!account) await connect();
    await checkWallet();
    const actionEpoch = epoch;
    const trader = account;
    const amount = parseAmount($("amount").value.trim());
    const buy = $("direction").value === "buy";
    if (!buy) {
      const allowance = uintAt(await call(config.token, "allowance", [trader, config.swap]));
      if (allowance < amount) {
        message("swap-status", "Approve exactly " + formatAmount(amount, 18) + " SWARM in your wallet to request a sell quote.");
        const hash = await send({ from: trader, to: config.token, data: encode("approve", [config.swap, amount]) });
        message("swap-status", "Waiting for token approval…");
        await waitReceipt(hash);
      }
    }
    await checkWallet();
    if (epoch !== actionEpoch) throw new Error("Wallet or trade changed. Request a fresh quote.");
    const deadline = Math.floor(Date.now() / 1000) + 120;
    const args = [...poolArgs(), buy, amount, 1n, deadline];
    const tx = { from: trader, to: config.swap, data: encode("swap", args), value: "0x" + (buy ? amount : 0n).toString(16) };
    message("swap-status", "Simulating your swap…");
    const output = uintAt(await walletRpc("eth_call", [tx, "latest"]));
    if (epoch !== actionEpoch) throw new Error("Wallet or trade changed. Request a fresh quote.");
    const minimum = minOutput(output, Number($("slippage").value));
    const symbol = buy ? " SWARM" : " ETH";
    quote = { trader, amount, buy, minimum, deadline, created: Date.now(), epoch: actionEpoch };
    $("quote").textContent = formatAmount(output, 12) + symbol;
    $("minimum").textContent = formatAmount(minimum, 18) + symbol;
    $("execute").hidden = false;
    $("review").hidden = true;
    message("swap-status", "Quote valid for 30 seconds. Network gas is additional. Confirm to send the swap.");
  });
}

async function execute() {
  await action(async () => {
    const current = quote;
    if (!current || Date.now() - current.created > 30_000) { invalidate(); throw new Error("Quote expired. Review again."); }
    await checkWallet();
    if (current.epoch !== epoch || account !== current.trader) throw new Error("Wallet changed. Review again.");
    const args = [...poolArgs(), current.buy, current.amount, current.minimum, current.deadline];
    const tx = { from: current.trader, to: config.swap, data: encode("swap", args), value: "0x" + (current.buy ? current.amount : 0n).toString(16) };
    message("swap-status", "Confirm the swap in your wallet.");
    const hash = await send(tx);
    invalidate();
    message("swap-status", "Swap submitted. Waiting for confirmation…");
    await waitReceipt(hash);
    message("swap-status", "Swap confirmed on Ethereum.");
    await refreshStats();
  });
}

async function action(fn) {
  if (busy) return;
  busy = true;
  controls();
  try { await fn(); }
  catch (error) { invalidate(); message("swap-status", error.code === 4001 ? "Request cancelled in your wallet." : (error.message || "The request failed."), true); }
  finally { busy = false; controls(); }
}

$("connect").addEventListener("click", () => action(connect));
$("swap-form").addEventListener("submit", review);
$("execute").addEventListener("click", execute);
for (const id of ["amount", "direction", "slippage"]) $(id).addEventListener("input", () => {
  invalidate();
  $("input-symbol").textContent = $("direction").value === "buy" ? "ETH" : "SWARM";
  if (ready) message("swap-status", "Review your trade for a fresh quote.");
  refreshBalance().catch(error => message("balance", error.message, true));
});
for (const event of ["accountsChanged", "chainChanged"]) window.ethereum?.on?.(event, () => {
  invalidate(); account = null;
  $("connect").textContent = "Connect wallet";
  $("balance").textContent = "Connect a wallet to see your balance";
  message("swap-status", "Wallet changed. Connect to Ethereum mainnet and review again.");
});

async function update() {
  try { await refreshStats(); if (!account && !busy) message("swap-status", "Connect your wallet to trade."); }
  catch (error) {
    ready = false; invalidate();
    $("price").textContent = "—";
    $("burned").textContent = "—";
    message("data-status", error.message, config.token !== null);
  }
}
await update();
setInterval(() => { if (!busy && !quote) update(); }, 20_000);
setInterval(() => {
  if (quote && !busy && Date.now() - quote.created > 30_000) {
    invalidate(); message("swap-status", "Quote expired. Review again for a fresh price.");
  }
}, 1000);
