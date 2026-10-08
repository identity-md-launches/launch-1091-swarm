// Replace nulls only with values from the finalized, verified mainnet launch record.
// No application build step or third-party CDN is required.
export const config = Object.freeze({
  chainId: 1,
  rpcUrl: "https://ethereum-rpc.publicnode.com",
  token: null,
  swap: null,
  pool: Object.freeze({
    fee: 3000,
    tickSpacing: 60,
    // The launch pool key is not hookless: the platform factory attaches its pool initialization
    // guard, and the key must match it exactly or the site reads (and trades) a different pool.
    // Publish the guard address from the launch record here. The site stays in its launch-pending
    // state while this is null, and it refuses the zero address.
    hooks: null,
  }),
});
