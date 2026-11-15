// Regenerates test/fixtures/webhook_*.json: webhook bodies, and their
// signatures made the way the FlightByte API makes them
// (HMAC-SHA256 over "<t>.<raw body>", sent as "t=<t>,v1=<hex>").
//
//   node tool/webhook_vectors.mjs
import { createHmac } from 'node:crypto';
import { writeFileSync } from 'node:fs';

const dir = new URL('../test/fixtures/', import.meta.url);
const secret = 'whsec_testSecretForVectors0123456789ab';
const timestamp = 1788858600;

const bodies = {
  'webhook_test.json': {
    id: 'evt_1',
    type: 'subscription.test',
    createdAt: '2026-09-08T09:10:00.000Z',
    subscriptionId: 'sub_1',
    flightKey: 'TK1848:2026-09-08',
    changes: [],
  },
  'webhook_flight_updated.json': {
    id: 'evt_2',
    type: 'flight.updated',
    createdAt: '2026-09-08T09:10:00.000Z',
    subscriptionId: 'sub_1',
    flightKey: 'TK1848:2026-09-08',
    changes: [
      {
        type: 'departure.gate.changed',
        path: 'departure.gate',
        from: 'A11',
        to: 'A22',
        message: 'Kapı A11 → A22 🇹🇷 İstanbul',
        deltaMinutes: null,
      },
    ],
    metadata: { booking: '42' },
  },
};

const vectors = { secret, timestamp, cases: [] };
for (const [file, body] of Object.entries(bodies)) {
  const raw = JSON.stringify(body);
  writeFileSync(new URL(file, dir), raw);
  const v1 = createHmac('sha256', secret).update(`${timestamp}.${raw}`).digest('hex');
  vectors.cases.push({ file, signature: `t=${timestamp},v1=${v1}` });
}
writeFileSync(new URL('webhook_vectors.json', dir), JSON.stringify(vectors, null, 2) + '\n');
console.log(`wrote ${vectors.cases.length} signed webhook fixtures`);
