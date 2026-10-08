// Small, static ABI encoder for this project's interfaces. Amounts stay bigint throughout.
export const selectors = Object.freeze({
  name: "0x06fdde03", symbol: "0x95d89b41", decimals: "0x313ce567",
  totalSupply: "0x18160ddd", totalBurned: "0xd89135cd", balanceOf: "0x70a08231",
  allowance: "0xdd62ed3e", approve: "0x095ea7b3", poolManager: "0xdc4c90d3",
  token: "0xfc0c546a", manager: "0x481c6a75", poolState: "0xa3bc99de", swap: "0x45271c42",
});
export const ZERO = "0x0000000000000000000000000000000000000000";
export const UNIT = 10n ** 18n;
export const MAX_INPUT = (1n << 127n) - 1n;

export function isAddress(value, allowZero = false) {
  return typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value)
    && (allowZero || value.toLowerCase() !== ZERO);
}

export function word(value) {
  const n = typeof value === "boolean" ? (value ? 1n : 0n) : BigInt(value);
  if (n < 0n || n >= 1n << 256n) throw new Error("Invalid unsigned ABI value.");
  return n.toString(16).padStart(64, "0");
}

export function encode(name, args = []) {
  if (!(name in selectors)) throw new Error("Unknown method.");
  return selectors[name] + args.map(word).join("");
}

export function uintAt(data, index = 0) {
  if (!/^0x(?:[a-fA-F0-9]{64})+$/.test(data) || data.length < 2 + (index + 1) * 64) {
    throw new Error("Invalid contract response.");
  }
  return BigInt("0x" + data.slice(2 + index * 64, 2 + (index + 1) * 64));
}

export function addressAt(data) {
  const value = uintAt(data);
  if (value >= 1n << 160n) throw new Error("Invalid address response.");
  return "0x" + value.toString(16).padStart(40, "0");
}

export function stringAt(data) {
  if (uintAt(data) !== 32n) throw new Error("Invalid text response.");
  const length = Number(uintAt(data, 1));
  if (length > 128 || data.length < 130 + length * 2) throw new Error("Invalid text response.");
  return new TextDecoder().decode(Uint8Array.from(data.slice(130, 130 + length * 2).match(/../g) || [], h => parseInt(h, 16)));
}

export function parseAmount(text) {
  if (!/^(0|[1-9]\d*)(\.\d{1,18})?$/.test(text)) throw new Error("Enter a positive amount with at most 18 decimals.");
  const [whole, fraction = ""] = text.split(".");
  const amount = BigInt(whole) * UNIT + BigInt(fraction.padEnd(18, "0"));
  if (amount === 0n || amount > MAX_INPUT) throw new Error("Amount is outside the supported range.");
  return amount;
}

export function formatAmount(value, precision = 6) {
  const amount = BigInt(value);
  const whole = (amount / UNIT).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const fraction = (amount % UNIT).toString().padStart(18, "0").slice(0, precision).replace(/0+$/, "");
  if (amount > 0n && amount < 10n ** BigInt(18 - precision)) return "<0." + "0".repeat(precision - 1) + "1";
  return whole + (fraction ? "." + fraction : "");
}

export function ethPerToken(sqrtPriceX96) {
  const sqrt = BigInt(sqrtPriceX96);
  if (sqrt <= 0n) throw new Error("The pool has not opened yet.");
  return ((1n << 192n) * UNIT) / (sqrt * sqrt);
}

export function minOutput(quoted, slippageBps) {
  if (![50, 100, 200].includes(slippageBps)) throw new Error("Unsupported slippage.");
  const minimum = BigInt(quoted) * BigInt(10_000 - slippageBps) / 10_000n;
  if (minimum <= 0n) throw new Error("Amount is too small to quote safely.");
  return minimum;
}

export function validateConfig(config) {
  if (config.chainId !== 1) throw new Error("Only Ethereum mainnet is supported.");
  if (!isAddress(config.token) || !isAddress(config.swap)) throw new Error("Launch pending. Trading opens when the verified contracts are published.");
  if (!Number.isInteger(config.pool.fee) || config.pool.fee < 0 || config.pool.fee > 1_000_000
    || !Number.isInteger(config.pool.tickSpacing) || config.pool.tickSpacing <= 0 || config.pool.tickSpacing > 32767
    || !isAddress(config.pool.hooks, true)) throw new Error("Invalid published pool configuration.");
}

export async function httpRpc(url, method, params = []) {
  const response = await fetch(url, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }), signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error("The Ethereum connection is unavailable.");
  const body = await response.json();
  if (body.error || body.result === undefined) throw new Error(body.error?.message || "Invalid Ethereum response.");
  return body.result;
}
