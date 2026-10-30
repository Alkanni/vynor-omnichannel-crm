// Recreates the eval AI agents of the given fixtures (default: every file in fixtures/) through the app API, waits
// until their knowledge is indexed, and records their ids in .eval-agents.json for the providers. Only agents named
// in those fixtures are replaced.
// Usage: node --env-file=.env setup.mjs [toko-roti.json ...]
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { AGENTS_FILE, appApi } from './lib/app-api.mjs';

const FIXTURES_DIR = new URL('./fixtures/', import.meta.url);
const TRAINING_TIMEOUT_MS = 180_000;
const POLL_INTERVAL_MS = 3_000;

async function labelIds(titles) {
  const { payload } = await appApi('/labels');
  return Promise.all(
    titles.map(async title => {
      const label = payload.find(existing => existing.title === title);
      if (label) return label.id;

      const created = await appApi('/labels', {
        method: 'POST',
        body: { label: { title, show_on_sidebar: true } },
      });
      return created.id;
    })
  );
}

async function createAgent(fixture, name, extraKnowledge) {
  const agent = await appApi('/ai_agents', {
    method: 'POST',
    body: {
      ai_agent: {
        ...fixture.settings,
        name,
        allowed_label_ids: await labelIds(fixture.labels),
      },
    },
  });
  for (const source of [...fixture.knowledge, ...extraKnowledge]) {
    await appApi(`/ai_agents/${agent.id}/knowledge_sources`, {
      method: 'POST',
      body: source,
    });
  }
  for (const product of fixture.products) {
    await appApi(`/ai_agents/${agent.id}/products`, {
      method: 'POST',
      body: product,
    });
  }
  return agent.id;
}

async function waitForTraining(id) {
  const deadline = Date.now() + TRAINING_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const agent = await appApi(`/ai_agents/${id}`);
    if (agent.trained_at) return;

    await sleep(POLL_INTERVAL_MS);
  }
  throw new Error(
    `AI agent ${id} was not trained within ${TRAINING_TIMEOUT_MS / 1000}s; check Sidekiq and the embedding settings`
  );
}

const fixtureNames =
  process.argv.length > 2
    ? process.argv.slice(2)
    : readdirSync(FIXTURES_DIR).filter(name => name.endsWith('.json'));
const fixtures = fixtureNames.map(name =>
  JSON.parse(readFileSync(new URL(name, FIXTURES_DIR), 'utf8'))
);

const names = fixtures.flatMap(fixture =>
  Object.values(fixture.agents).map(agent => agent.name)
);
const { payload: existing } = await appApi('/ai_agents');
for (const agent of existing.filter(candidate =>
  names.includes(candidate.name)
)) {
  await appApi(`/ai_agents/${agent.id}`, { method: 'DELETE' });
  console.log(`Deleted old eval agent ${agent.id} (${agent.name})`);
}

const ids = existsSync(AGENTS_FILE)
  ? JSON.parse(readFileSync(AGENTS_FILE, 'utf8'))
  : {};
const created = [];
for (const fixture of fixtures) {
  for (const [key, { name, knowledge }] of Object.entries(fixture.agents)) {
    ids[key] = await createAgent(fixture, name, knowledge);
    created.push(ids[key]);
    console.log(`Created ${key} agent ${ids[key]} (${name})`);
  }
}

await Promise.all(created.map(waitForTraining));
writeFileSync(AGENTS_FILE, `${JSON.stringify(ids, null, 2)}\n`);
console.log(`Knowledge indexed; agent ids written to ${AGENTS_FILE.pathname}`);
