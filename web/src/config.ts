// Values copied from the verified launch record (deployment.json, source commit a90f7546492326d5f6a43b04cf685124063ac858).
// Never replace them with addresses taken from prose. The pool key carries the platform's pool
// initialization guard as its hook; a hookless key would point the site at a different pool.
export interface PoolKeyConfig {
  readonly fee: number;
  readonly tickSpacing: number;
  readonly hooks: string | null;
}

export interface SiteConfig {
  readonly chainId: number;
  readonly rpcUrl: string;
  readonly explorer: string;
  readonly token: string | null;
  readonly swap: string | null;
  readonly pool: PoolKeyConfig;
}

export const config: SiteConfig = Object.freeze({
  chainId: 1,
  rpcUrl: "https://ethereum-rpc.publicnode.com",
  explorer: "https://etherscan.io",
  token: "0xd2aef07b4a807062c1c9f01713def52172548eca",
  swap: "0x4bc05bda38e6e4a6158b5eeb825208c1f2380360",
  pool: Object.freeze({
    fee: 12500,
    tickSpacing: 60,
    hooks: "0x784ff9a3ac5d88a30bfff6f7f2a270161fbe6000",
  }),
});

/** Token metadata shown in the header, the token selector and the published token list. */
export const brand = Object.freeze({
  name: "swarm",
  symbol: "SWARM",
  decimals: 18,
  appName: "SwarmSwap",
});
