import { defineConfig } from "vite";

// The export is served from a gateway subpath or an ENS name, so every URL is relative.
// Brand files keep stable, unhashed names because the web manifest and token list point at them.
const stableAssets = new Set(["logo.svg", "logo.png"]);

export default defineConfig({
  base: "./",
  publicDir: "public",
  build: {
    outDir: "../dist",
    emptyOutDir: true,
    target: "es2022",
    sourcemap: false,
    rollupOptions: {
      output: {
        assetFileNames: (info) => {
          const name = info.names?.[0] ?? "";
          return stableAssets.has(name) ? "assets/[name][extname]" : "assets/[name]-[hash][extname]";
        },
      },
    },
  },
});
