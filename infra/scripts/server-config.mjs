#!/usr/bin/env node
// Writes the server's configuration: infra/docker/server/.env (secrets and addresses) and the
// LiveKit and Egress files in infra/docker/server/generated/.
//
//   node infra/scripts/server-config.mjs --host 192.168.1.10
//
// Run by server-setup.sh / server-setup.ps1, inside a node container so the PC needs nothing
// but Docker. Secrets are generated once and kept: running it again (for a new address) never
// changes them, because a new KEK would make every video undecryptable and a new pepper would
// lock every account out.
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'docker', 'server');
const envFile = join(dir, '.env');
const generated = join(dir, 'generated');

const { values } = parseArgs({ options: { host: { type: 'string' } } });
const host = (values.host ?? '').trim();
// An IPv4 address or a host name; nothing that could break out of a YAML or .env line.
if (!/^[A-Za-z0-9.-]{1,253}$/.test(host)) {
  console.error("usage: server-config.mjs --host <this PC's address, e.g. 192.168.1.10>");
  process.exit(2);
}

/** KEY=value lines from an existing .env, so secrets survive a re-run. */
function readEnv(path) {
  if (!existsSync(path)) return {};
  const out = {};
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (m) out[m[1]] = m[2];
  }
  return out;
}

const b64 = (n) => randomBytes(n).toString('base64');
// Letters and digits only: safe inside URLs, YAML and connection strings.
const word = (n) => randomBytes(n).toString('base64url').replace(/[-_]/g, 'x');

function licenceKeys() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const der = (k, type) => k.export({ format: 'der', type }).toString('base64');
  return { priv: der(privateKey, 'pkcs8'), pub: der(publicKey, 'spki') };
}

const old = readEnv(envFile);
const keep = (name, make) => old[name] || make();
const licence = old.LICENSE_PRIVATE_KEY_BASE64 ? null : licenceKeys();

const secrets = {
  KEK_BASE64: keep('KEK_BASE64', () => b64(32)),
  LICENSE_PRIVATE_KEY_BASE64: keep('LICENSE_PRIVATE_KEY_BASE64', () => licence.priv),
  LICENSE_PUBLIC_KEY_BASE64: keep('LICENSE_PUBLIC_KEY_BASE64', () => licence.pub),
  JWT_SECRET: keep('JWT_SECRET', () => b64(48)),
  PASSWORD_PEPPER: keep('PASSWORD_PEPPER', () => b64(32)),
  INTERNAL_API_TOKEN: keep('INTERNAL_API_TOKEN', () => word(48)),
  LIVE_TICKET_SECRET: keep('LIVE_TICKET_SECRET', () => b64(48)),
  POSTGRES_PASSWORD: keep('POSTGRES_PASSWORD', () => word(24)),
  STORAGE_ACCESS_KEY: keep('STORAGE_ACCESS_KEY', () => `tihe${word(8)}`),
  STORAGE_SECRET_KEY: keep('STORAGE_SECRET_KEY', () => word(32)),
  LIVEKIT_API_KEY: keep('LIVEKIT_API_KEY', () => `API${word(9)}`),
  LIVEKIT_API_SECRET: keep('LIVEKIT_API_SECRET', () => word(40)),
};

const env = { TIHE_HOST: host, ...secrets };
writeFileSync(
  envFile,
  [
    '# Written by infra/scripts/server-config.mjs. Back this file up somewhere safe and private:',
    '# the database plus KEK_BASE64 decrypt every video, and without this file nobody can sign in.',
    ...Object.entries(env).map(([k, v]) => `${k}=${v}`),
    '',
  ].join('\n'),
  { mode: 0o600 },
);

mkdirSync(generated, { recursive: true });
// Readable by all: Egress runs as an unprivileged user inside its container and could not read a
// 0600 file owned by the host's user. The keys in it only reach this PC's own LiveKit.
const shared = { mode: 0o644 };
const { LIVEKIT_API_KEY: lkKey, LIVEKIT_API_SECRET: lkSecret } = secrets;

writeFileSync(
  join(generated, 'livekit.yaml'),
  `# Written by infra/scripts/server-config.mjs.
port: 7880
bind_addresses: ['']
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 50100
  # Students reach media on this PC's own address.
  node_ip: ${host}
  use_external_ip: false
redis:
  address: redis:6379
keys:
  ${lkKey}: ${lkSecret}
room:
  auto_create: false
  empty_timeout: 300
  max_participants: 100
webhook:
  api_key: ${lkKey}
  urls:
    - http://api:3000/v1/webhooks/livekit
    - http://live:3100/v1/live/webhooks/livekit
logging:
  level: info
`,
  shared,
);

writeFileSync(
  join(generated, 'egress.yaml'),
  `# Written by infra/scripts/server-config.mjs.
api_key: ${lkKey}
api_secret: ${lkSecret}
ws_url: ws://livekit:7880
redis:
  address: redis:6379
s3:
  access_key: ${secrets.STORAGE_ACCESS_KEY}
  secret: ${secrets.STORAGE_SECRET_KEY}
  region: us-east-1
  endpoint: http://storage:9000
  bucket: tihe-raw
  force_path_style: true
cpu_cost:
  room_composite_cpu_cost: 3.0
logging:
  level: info
`,
  shared,
);

console.log(`Server configured for ${host}${Object.keys(old).length ? ' (secrets kept)' : ''}.`);
