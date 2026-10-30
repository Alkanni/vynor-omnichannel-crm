// Recreates the eval AI agents from fixtures/toko-roti.json through the app API, waits until their knowledge is
// indexed, and writes their ids to .eval-agents.json for provider.mjs. Only agents named in the fixture are replaced.
import { readFileSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { AGENTS_FILE, appApi } from './lib/app-api.mjs';

const TRAINING_TIMEOUT_MS = 180_000;
const POLL_INTERVAL_MS = 3_000;

const fixture = JSON.parse(
  readFileSync(new URL('./fixtures/toko-roti.json', import.meta.url), 'utf8')
);

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

async function createAgent(name, extraKnowledge, allowedLabelIds) {
  const agent = await appApi('/ai_agents', {
    method: 'POST',
    body: {
      ai_agent: {
        ...fixture.settings,
        name,
        allowed_label_ids: allowedLabelIds,
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

const names = Object.values(fixture.agents).map(agent => agent.name);
const { payload: existing } = await appApi('/ai_agents');
for (const agent of existing.filter(candidate =>
  names.includes(candidate.name)
)) {
  await appApi(`/ai_agents/${agent.id}`, { method: 'DELETE' });
  console.log(`Deleted old eval agent ${agent.id} (${agent.name})`);
}

const allowedLabelIds = await labelIds(fixture.labels);
const ids = {};
for (const [key, { name, knowledge }] of Object.entries(fixture.agents)) {
  ids[key] = await createAgent(name, knowledge, allowedLabelIds);
  console.log(`Created ${key} agent ${ids[key]} (${name})`);
}

await Promise.all(Object.values(ids).map(waitForTraining));
writeFileSync(AGENTS_FILE, `${JSON.stringify(ids, null, 2)}\n`);
console.log(`Knowledge indexed; agent ids written to ${AGENTS_FILE.pathname}`);
