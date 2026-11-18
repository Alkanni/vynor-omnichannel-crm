// Promptfoo provider that replays an earlier run instead of calling the app, so the same replies are graded again, for
// example by another judge: REPLAY_OUTPUT is the JSON output of that run (`-o`), and each case gets the response its
// conversation got there, with the same metadata, so every assertion and transform sees what it saw then. Use it with
// the config of that run, e.g. `REPLAY_OUTPUT=output/web-1.json EVAL_JUDGE_MODEL=<model> npx promptfoo@0.124.1 eval -c
// promptfooconfig.web.yaml -r file://replay-provider.mjs --no-cache -o output/web-1-regraded.json`.
import { readFileSync } from 'node:fs';

export default class ReplayProvider {
  constructor() {
    const { results } = JSON.parse(
      readFileSync(process.env.REPLAY_OUTPUT, 'utf8')
    ).results;
    this.responses = new Map(
      results.map(result => [result.vars.conversation, result.response])
    );
  }

  id() {
    return 'replay';
  }

  async callApi(_prompt, { vars }) {
    const response = this.responses.get(vars.conversation);
    return response ?? { error: 'No response for this case in REPLAY_OUTPUT' };
  }
}
