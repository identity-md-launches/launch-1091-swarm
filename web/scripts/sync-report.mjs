// Materialize public downloads from their authoritative repository files.
// Run before the unchanged Vite production build.
import { copyFileSync, mkdirSync } from 'node:fs';
const root = new URL('../../', import.meta.url);
const publicDir = new URL('../public/', import.meta.url);
mkdirSync(publicDir, { recursive: true });
for (const [source, destination] of [
  ['SWARM_DRAFT_CONTRACT_REPORT.md', 'SWARM_DRAFT_CONTRACT_REPORT.md'],
  ['docs/audit/swarm.listing-draft.json', 'swarm.listing-draft.json'],
]) copyFileSync(new URL(source, root), new URL(destination, publicDir));
console.log('Synced report and listing worksheet.');
