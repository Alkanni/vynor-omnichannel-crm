// Minimal client for the account API of the app under test, configured from evals/ai-agent/.env.
const { EVAL_APP_URL, EVAL_ACCOUNT_ID, EVAL_API_ACCESS_TOKEN } = process.env;

export const AGENTS_FILE = new URL('../.eval-agents.json', import.meta.url);

export async function appApi(path, { method = 'GET', body } = {}) {
  if (!EVAL_APP_URL || !EVAL_ACCOUNT_ID || !EVAL_API_ACCESS_TOKEN) {
    throw new Error(
      'Set EVAL_APP_URL, EVAL_ACCOUNT_ID and EVAL_API_ACCESS_TOKEN (see .env.example)'
    );
  }

  const response = await fetch(
    `${EVAL_APP_URL}/api/v1/accounts/${EVAL_ACCOUNT_ID}${path}`,
    {
      method,
      headers: {
        'Content-Type': 'application/json',
        api_access_token: EVAL_API_ACCESS_TOKEN,
      },
      body: body && JSON.stringify(body),
    }
  );
  const text = await response.text();
  if (!response.ok)
    throw new Error(
      `${method} ${path} → HTTP ${response.status}: ${text.slice(0, 300)}`
    );
  return text ? JSON.parse(text) : null;
}
