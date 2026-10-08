// Replace nulls only with addresses from the finalized, verified mainnet launch.
// No application build step or third-party CDN is required.
export const config = Object.freeze({
  chainId: 1,
  rpcUrl: "https://ethereum-rpc.publicnode.com",
  token: null,
  swap: null,
  pool: Object.freeze({
    fee: 3000,
    tickSpacing: 60,
    // Zero is the protocol-defined no-hook value, not a deployment address placeholder.
    hooks: "0x0000000000000000000000000000000000000000",
  }),
});
