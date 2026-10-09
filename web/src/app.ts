import { config, brand } from "./config.ts";
import {
  encode, uintAt, addressAt, stringAt, parseAmount, formatAmount, ethPerToken, minOutput,
  validateConfig, httpRpc, isAddress, type AbiValue,
} from "./rpc.ts";
import logoSvg from "../../assets/logo.svg";
import logoPng from "../../assets/logo.png";

interface Eip1193Provider {
  request(args: { method: string; params?: unknown[] }): Promise<unknown>;
  on?(event: string, listener: () => void): void;
}
declare global { interface Window { ethereum?: Eip1193Provider } }

interface Quote {
  trader: string; amount: bigint; buy: boolean; minimum: bigint; deadline: number; created: number; epoch: number;
}
interface Transaction { from: string; to: string; data: string; value?: string; gas?: string }

function $<T extends HTMLElement = HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`Missing element #${id}`);
  return element as T;
}
const amountInput = $<HTMLInputElement>("amount");
const directionSelect = $<HTMLSelectElement>("direction");
const slippageSelect = $<HTMLSelectElement>("slippage");
const reviewButton = $<HTMLButtonElement>("review");
const executeButton = $<HTMLButtonElement>("execute");
const connectButton = $<HTMLButtonElement>("connect");

let account: string | null = null, quote: Quote | null = null, ready = false, busy = false, epoch = 0;

const poolArgs = (): AbiValue[] => {
  validateConfig(config);
  return [config.pool.fee, config.pool.tickSpacing, config.pool.hooks];
};
const readRpc = (method: string, params: unknown[] = []) => httpRpc(config.rpcUrl, method, params);
const call = (to: string, name: string, args: AbiValue[] = [], block = "latest") =>
  readRpc("eth_call", [{ to, data: encode(name, args) }, block]) as Promise<string>;
const wallet = (): Eip1193Provider => {
  if (!window.ethereum) throw new Error("Install an Ethereum wallet, then connect it to trade.");
  return window.ethereum;
};
const walletRpc = (method: string, params: unknown[] = []) => wallet().request({ method, params });
const message = (id: string, text: string, error = false) => {
  const element = $(id);
  element.textContent = text;
  element.classList.toggle("error", error);
};
const isBuy = () => directionSelect.value === "buy";

/** Token selector: the pay and receive rows follow the chosen direction and carry the SWARM logo. */
const tokens = {
  SWARM: { symbol: brand.symbol, name: brand.name, logo: logoSvg },
  ETH: { symbol: "ETH", name: "Ether", logo: null },
} as const;
function renderToken(prefix: "pay" | "receive", key: keyof typeof tokens) {
  const token = tokens[key];
  const icon = $<HTMLImageElement>(`${prefix}-icon`);
  const glyph = $(`${prefix}-glyph`);
  icon.hidden = token.logo === null;
  glyph.hidden = token.logo !== null;
  if (token.logo) { icon.src = token.logo; icon.alt = `${token.symbol} logo`; }
  $(`${prefix}-symbol`).textContent = token.symbol;
  $(`${prefix}-name`).textContent = token.name;
}
function syncSelector() {
  renderToken("pay", isBuy() ? "ETH" : "SWARM");
  renderToken("receive", isBuy() ? "SWARM" : "ETH");
}

function controls() {
  reviewButton.disabled = !ready || busy;
  executeButton.disabled = busy || !quote;
  connectButton.disabled = busy;
  for (const control of [amountInput, directionSelect, slippageSelect]) control.disabled = busy;
}

function invalidate() {
  epoch++;
  quote = null;
  $("quote").textContent = "—";
  $("minimum").textContent = "—";
  executeButton.hidden = true;
  reviewButton.hidden = false;
  controls();
}

async function checkWallet(): Promise<string> {
  if (BigInt(await walletRpc("eth_chainId") as string) !== 1n) throw new Error("Switch your wallet to Ethereum mainnet.");
  const accounts = await walletRpc("eth_accounts") as string[];
  const [first] = accounts;
  if (!first || !account || first.toLowerCase() !== account.toLowerCase()) {
    throw new Error("Wallet changed. Connect again and request a fresh quote.");
  }
  return first;
}

async function connect() {
  const accounts = await walletRpc("eth_requestAccounts") as string[];
  const [first] = accounts;
  if (!first || !isAddress(first)) throw new Error("No wallet account selected.");
  if (BigInt(await walletRpc("eth_chainId") as string) !== 1n) {
    await walletRpc("wallet_switchEthereumChain", [{ chainId: "0x1" }]);
  }
  account = first;
  await checkWallet();
  connectButton.textContent = account.slice(0, 6) + "…" + account.slice(-4);
  connectButton.setAttribute("aria-label", "Connected wallet " + account);
  await refreshBalance();
}

async function refreshBalance() {
  if (!account || !ready) return;
  validateConfig(config);
  const forAccount = account;
  const buy = isBuy();
  const result = buy ? await readRpc("eth_getBalance", [forAccount, "latest"]) as string
    : await call(config.token, "balanceOf", [forAccount]);
  if (account !== forAccount || buy !== isBuy()) return;
  $("balance").textContent = "Balance: " + formatAmount(BigInt(result)) + (buy ? " ETH · keep some for gas" : " SWARM");
}

async function refreshStats() {
  validateConfig(config);
  if (BigInt(await readRpc("eth_chainId") as string) !== 1n) throw new Error("The configured connection is not Ethereum mainnet.");
  const block = await readRpc("eth_blockNumber") as string;
  const [name, symbol, decimals, supply, burned, state, swapToken, swapManager, manager] = await Promise.all([
    call(config.token, "name", [], block), call(config.token, "symbol", [], block), call(config.token, "decimals", [], block),
    call(config.token, "totalSupply", [], block), call(config.token, "totalBurned", [], block),
    call(config.swap, "poolState", poolArgs(), block), call(config.swap, "token", [], block),
    call(config.swap, "manager", [], block), call(config.token, "poolManager", [], block),
  ]);
  if (stringAt(name) !== brand.name || stringAt(symbol) !== brand.symbol || uintAt(decimals) !== BigInt(brand.decimals)
    || uintAt(supply) !== 1_000_000_000n * 10n ** 18n || addressAt(swapToken) !== config.token.toLowerCase()
    || addressAt(swapManager) !== addressAt(manager)) throw new Error("The published contracts do not match this launch.");
  const price = ethPerToken(uintAt(state));
  $("metadata").textContent = stringAt(name) + " / " + stringAt(symbol);
  $("supply").textContent = formatAmount(uintAt(supply));
  $("burned").textContent = formatAmount(uintAt(burned));
  $("burn-note").textContent = "SWARM · automatic transfer burns";
  $("price").textContent = formatAmount(price, 12);
  message("data-status", "Live on Ethereum · block " + BigInt(block).toLocaleString() + " · updated " + new Date().toLocaleTimeString());
  ready = true;
  controls();
  await refreshBalance();
}

async function waitReceipt(hash: string) {
  const link = $<HTMLAnchorElement>("transaction");
  link.href = config.explorer + "/tx/" + hash;
  link.hidden = false;
  for (let attempt = 0; attempt < 120; attempt++) {
    const receipt = await readRpc("eth_getTransactionReceipt", [hash]) as { status: string } | null;
    if (receipt) {
      if (BigInt(receipt.status) !== 1n) throw new Error("Transaction reverted. Funds were not swapped; network gas was spent.");
      return receipt;
    }
    await new Promise((resolve) => setTimeout(resolve, 3000));
  }
  throw new Error("Still pending. Check the transaction link before submitting another transaction.");
}

async function send(tx: Transaction): Promise<string> {
  await checkWallet();
  const actionEpoch = epoch;
  const gas = BigInt(await walletRpc("eth_estimateGas", [tx]) as string);
  await checkWallet();
  if (epoch !== actionEpoch) throw new Error("Wallet or trade changed. Review again.");
  return walletRpc("eth_sendTransaction", [{ ...tx, gas: "0x" + (gas * 120n / 100n).toString(16) }]) as Promise<string>;
}

async function review(event: Event) {
  event.preventDefault();
  await action(async () => {
    invalidate();
    validateConfig(config);
    if (!account) await connect();
    await checkWallet();
    const actionEpoch = epoch;
    const trader = account as string;
    const amount = parseAmount(amountInput.value.trim());
    const buy = isBuy();
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
    const args: AbiValue[] = [...poolArgs(), buy, amount, 1n, deadline];
    const tx: Transaction = { from: trader, to: config.swap, data: encode("swap", args), value: "0x" + (buy ? amount : 0n).toString(16) };
    message("swap-status", "Simulating your swap…");
    const output = uintAt(await walletRpc("eth_call", [tx, "latest"]) as string);
    if (epoch !== actionEpoch) throw new Error("Wallet or trade changed. Request a fresh quote.");
    const minimum = minOutput(output, Number(slippageSelect.value));
    const symbol = buy ? " SWARM" : " ETH";
    quote = { trader, amount, buy, minimum, deadline, created: Date.now(), epoch: actionEpoch };
    $("quote").textContent = formatAmount(output, 12) + symbol;
    $("minimum").textContent = formatAmount(minimum, 18) + symbol;
    executeButton.hidden = false;
    reviewButton.hidden = true;
    message("swap-status", "Quote valid for 30 seconds. Network gas is additional. Confirm to send the swap.");
  });
}

async function execute() {
  await action(async () => {
    const current = quote;
    if (!current || Date.now() - current.created > 30_000) { invalidate(); throw new Error("Quote expired. Review again."); }
    validateConfig(config);
    await checkWallet();
    if (current.epoch !== epoch || account !== current.trader) throw new Error("Wallet changed. Review again.");
    const args: AbiValue[] = [...poolArgs(), current.buy, current.amount, current.minimum, current.deadline];
    const tx: Transaction = { from: current.trader, to: config.swap, data: encode("swap", args), value: "0x" + (current.buy ? current.amount : 0n).toString(16) };
    message("swap-status", "Confirm the swap in your wallet.");
    const hash = await send(tx);
    invalidate();
    message("swap-status", "Swap submitted. Waiting for confirmation…");
    await waitReceipt(hash);
    message("swap-status", "Swap confirmed on Ethereum.");
    await refreshStats();
  });
}

async function action(fn: () => Promise<void>) {
  if (busy) return;
  busy = true;
  controls();
  try { await fn(); }
  catch (error) {
    invalidate();
    const code = (error as { code?: number }).code;
    const text = error instanceof Error && error.message ? error.message : "The request failed.";
    message("swap-status", code === 4001 ? "Request cancelled in your wallet." : text, true);
  }
  finally { busy = false; controls(); }
}

function installBranding() {
  for (const image of document.querySelectorAll<HTMLImageElement>("img[data-logo]")) {
    image.src = image.dataset.logo === "png" ? logoPng : logoSvg;
  }
  const tokenLink = $<HTMLAnchorElement>("token-link");
  if (config.token) tokenLink.href = config.explorer + "/token/" + config.token;
  const swapLink = $<HTMLAnchorElement>("swap-link");
  if (config.swap) swapLink.href = config.explorer + "/address/" + config.swap;
}

connectButton.addEventListener("click", () => action(connect));
$<HTMLFormElement>("swap-form").addEventListener("submit", (event) => { void review(event); });
executeButton.addEventListener("click", () => { void execute(); });
for (const control of [amountInput, directionSelect, slippageSelect]) control.addEventListener("input", () => {
  invalidate();
  syncSelector();
  if (ready) message("swap-status", "Review your trade for a fresh quote.");
  refreshBalance().catch((error: Error) => message("balance", error.message, true));
});
for (const event of ["accountsChanged", "chainChanged"]) window.ethereum?.on?.(event, () => {
  invalidate(); account = null;
  connectButton.textContent = "Connect wallet";
  connectButton.removeAttribute("aria-label");
  $("balance").textContent = "Connect a wallet to see your balance";
  message("swap-status", "Wallet changed. Connect to Ethereum mainnet and review again.");
});

async function update() {
  try { await refreshStats(); if (!account && !busy) message("swap-status", "Connect your wallet to trade."); }
  catch (error) {
    ready = false; invalidate();
    $("price").textContent = "—";
    $("burned").textContent = "—";
    message("data-status", error instanceof Error ? error.message : "Unable to read the token. Try again later.", config.token !== null);
  }
}

installBranding();
syncSelector();
await update();
setInterval(() => { if (!busy && !quote) void update(); }, 20_000);
setInterval(() => {
  if (quote && !busy && Date.now() - quote.created > 30_000) {
    invalidate(); message("swap-status", "Quote expired. Review again for a fresh price.");
  }
}, 1000);
