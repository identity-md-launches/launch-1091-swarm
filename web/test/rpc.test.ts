import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { encode, word, uintAt, addressAt, stringAt, parseAmount, formatAmount, ethPerToken, minOutput, validateConfig, ZERO, MAX_INPUT, httpRpc } from "../src/rpc.ts";
import { config, brand } from "../src/config.ts";

const here = new URL(".", import.meta.url);

test("amount parsing preserves 18 decimals and rejects ambiguous input", () => {
  assert.equal(parseAmount("1.000000000000000001"), 1000000000000000001n);
  assert.equal(parseAmount("0.000000000000000001"), 1n);
  for (const invalid of ["", "0", "-1", "1e18", "01", ".1", "1.", "0.0000000000000000001", " 1", "Infinity"]) {
    assert.throws(() => parseAmount(invalid));
  }
  assert.throws(() => parseAmount((MAX_INPUT / 10n ** 18n + 1n).toString()));
});

test("display does not use floating point or hide small nonzero balances", () => {
  assert.equal(formatAmount(10n ** 27n), "1,000,000,000");
  assert.equal(formatAmount(1000000000000000001n, 18), "1.000000000000000001");
  assert.equal(formatAmount(1n), "<0.000001");
  assert.equal(formatAmount(0n), "0");
});

test("ETH per token uses the native ETH currency0 orientation", () => {
  assert.equal(ethPerToken((1n << 96n) * 10000n), 10_000_000_000n);
  assert.equal(formatAmount(ethPerToken((1n << 96n) * 10000n), 12), "0.00000001");
  assert.throws(() => ethPerToken(0n));
});

test("minimum output rounds down and can never be zero", () => {
  assert.equal(minOutput(1000n, 50), 995n);
  assert.equal(minOutput(1001n, 100), 990n);
  assert.throws(() => minOutput(1n, 50));
  assert.throws(() => minOutput(100n, 10000));
});

test("static ABI round trips and bounds", () => {
  assert.equal(uintAt("0x" + word(MAX_INPUT)), MAX_INPUT);
  assert.equal(addressAt("0x" + word(ZERO)), ZERO);
  assert.equal(encode("approve", [ZERO, 1n]), "0x095ea7b3" + "0".repeat(64) + word(1));
  assert.equal(encode("swap", [3000, 60, ZERO, true, 1n, 1n, 123]).length, 10 + 7 * 64);
  assert.throws(() => word(-1n));
  assert.throws(() => word(1n << 256n));
  assert.throws(() => uintAt("0x"));
  assert.throws(() => addressAt("0x" + word(1n << 160n)));
});

test("dynamic text decoding validates offsets and length", () => {
  const encoded = "0x" + word(32) + word(5) + Buffer.from("swarm").toString("hex").padEnd(64, "0");
  assert.equal(stringAt(encoded), "swarm");
  assert.throws(() => stringAt("0x" + word(64) + word(5) + word(0)));
  assert.throws(() => stringAt("0x" + word(32) + word(1000)));
});

test("the published configuration matches the verified launch record and fails closed otherwise", () => {
  assert.doesNotThrow(() => validateConfig(config));
  assert.equal(config.chainId, 1);
  assert.match(config.token ?? "", /^0x[0-9a-f]{40}$/);
  assert.match(config.swap ?? "", /^0x[0-9a-f]{40}$/);
  assert.match(config.pool.hooks ?? "", /^0x[0-9a-f]{40}$/);
  assert.notEqual(config.pool.hooks, ZERO, "the launch pool key carries the platform's initialization guard hook");
  assert.throws(() => validateConfig({ ...config, chainId: 8453 }), /mainnet/);
  assert.throws(() => validateConfig({ ...config, token: null }), /Launch pending/);
  assert.throws(() => validateConfig({ ...config, token: ZERO }));
  assert.throws(() => validateConfig({ ...config, pool: { ...config.pool, tickSpacing: 0 } }));
  assert.throws(() => validateConfig({ ...config, pool: { ...config.pool, hooks: null } }), /Launch pending/);
  assert.throws(() => validateConfig({ ...config, pool: { ...config.pool, hooks: ZERO } }), /pool configuration/);
});

test("the token list and web manifest describe the SWARM contract and point at the shipped logo", () => {
  const list = JSON.parse(readFileSync(new URL("../public/swarm.tokenlist.json", here), "utf8"));
  const [entry] = list.tokens;
  assert.equal(list.tokens.length, 1);
  assert.equal(entry.chainId, config.chainId);
  assert.equal(entry.address, config.token);
  assert.equal(entry.symbol, brand.symbol);
  assert.equal(entry.name, brand.name);
  assert.equal(entry.decimals, brand.decimals);
  assert.equal(entry.logoURI, "./assets/logo.png");
  const manifest = JSON.parse(readFileSync(new URL("../public/manifest.webmanifest", here), "utf8"));
  assert.deepEqual(manifest.icons.map((icon: { src: string }) => icon.src).sort(), ["./assets/logo.png", "./assets/logo.svg"]);
  assert.equal(manifest.name, brand.appName);
  assert.equal(manifest.related_contracts?.[0]?.address, config.token);
});

test("RPC errors are surfaced rather than displayed as market data", async () => {
  const original = globalThis.fetch;
  try {
    globalThis.fetch = (async () => ({ ok: true, json: async () => ({ error: { message: "unavailable" } }) })) as unknown as typeof fetch;
    await assert.rejects(httpRpc("https://example.invalid", "eth_chainId"), /unavailable/);
    globalThis.fetch = (async () => ({ ok: true, json: async () => ({ result: "0x1" }) })) as unknown as typeof fetch;
    assert.equal(await httpRpc("https://example.invalid", "eth_chainId"), "0x1");
  } finally { globalThis.fetch = original; }
});
