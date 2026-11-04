<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
});

// Same limit as AiAgents::KnowledgeRetriever::MAX_QUERY_CHARACTERS.
const MAX_QUERY_LENGTH = 4000;
// Same limit as AiAgents::WebSearch::MAX_QUERY_CHARACTERS.
const MAX_WEB_QUERY_LENGTH = 200;
// Exa charges in US dollars.
const WEB_SEARCH_CURRENCY = 'USD';
const WEB_URL_PATTERN = /^https?:\/\//i;
const MAX_CONVERSATION_LENGTH = 10000;
const AGENT_REPLY_PREFIX = 'AI:';

const { t, locale } = useI18n();
const { run, abort, isPending } = useAbortableRequest();

const dialogRef = ref(null);
const query = ref('');
const webQuery = ref('');
const conversation = ref('');
const result = ref(null);

const trimmedQuery = computed(() => query.value.trim());
const trimmedWebQuery = computed(() => webQuery.value.trim());
const history = computed(() =>
  conversation.value
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .map(line =>
      line.startsWith(AGENT_REPLY_PREFIX)
        ? {
            role: 'assistant',
            content: line.slice(AGENT_REPLY_PREFIX.length).trim(),
          }
        : { role: 'user', content: line }
    )
    .filter(message => message.content)
);
const sourceTypeLabels = computed(() => ({
  text: t('AI_AGENTS.KNOWLEDGE.TABS.TEXT'),
  website: t('AI_AGENTS.KNOWLEDGE.TABS.WEBSITE'),
  file: t('AI_AGENTS.KNOWLEDGE.TABS.FILE'),
  qa: t('AI_AGENTS.KNOWLEDGE.TABS.QA'),
  product: t('AI_AGENTS.KNOWLEDGE.TABS.PRODUCT'),
}));
const modeDescription = computed(() =>
  result.value.mode === 'hybrid'
    ? t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.MODE_HYBRID', {
        model: result.value.embedding_model,
      })
    : t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.MODE_KEYWORD')
);

const webStatusDescription = computed(() => {
  const { status, latency_ms: latency, cost_usd: cost } = result.value.web;
  const descriptions = {
    searched: t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.STATUS.SEARCHED', {
      latency,
      cost: new Intl.NumberFormat(locale.value, {
        style: 'currency',
        currency: WEB_SEARCH_CURRENCY,
        maximumFractionDigits: 4,
      }).format(cost),
    }),
    cached: t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.STATUS.CACHED'),
    skipped_budget: t(
      'AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.STATUS.SKIPPED_BUDGET'
    ),
    failed_timeout: t(
      'AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.STATUS.FAILED_TIMEOUT'
    ),
    failed_rate_limit: t(
      'AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.STATUS.FAILED_RATE_LIMIT'
    ),
    failed_credits: t(
      'AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.STATUS.FAILED_CREDITS'
    ),
    failed_provider: t(
      'AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.STATUS.FAILED_PROVIDER'
    ),
    failed_request: t(
      'AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.STATUS.FAILED_REQUEST'
    ),
  };
  return descriptions[status];
});
const webSearchFoundNothing = computed(
  () =>
    ['searched', 'cached'].includes(result.value.web.status) &&
    !result.value.web.results.length
);

const formatScore = score =>
  new Intl.NumberFormat(locale.value, { maximumFractionDigits: 4 }).format(
    score
  );

// Exa gives the date without a time, so it is shown as is in any time zone.
const formatPublishedDate = date =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeZone: 'UTC',
  }).format(new Date(date));

// The URLs come from pages on the internet, so only web addresses become links.
const webUrlLink = url => (WEB_URL_PATTERN.test(url) ? url : undefined);

const runTest = async () => {
  if (!trimmedQuery.value) return;
  try {
    const data = await run(async signal => {
      const response = await AiAgentKnowledgeAPI.testRetrieval(
        props.agentId,
        {
          query: trimmedQuery.value,
          history: history.value,
          webQuery: trimmedWebQuery.value || undefined,
        },
        { signal }
      );
      return response.data;
    });
    if (data) result.value = data;
  } catch (error) {
    const message = parseAPIErrorResponse(error);
    useAlert(
      typeof message === 'string'
        ? message
        : t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.ERROR')
    );
  }
};

const open = () => dialogRef.value.open();

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.TITLE')"
    :description="t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.DESCRIPTION')"
    :cancel-button-label="t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.CLOSE')"
    :show-confirm-button="false"
    width="3xl"
    overflow-y-auto
    @confirm="runTest"
    @close="abort"
  >
    <TextArea
      v-model="conversation"
      :label="t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.HISTORY_LABEL')"
      :placeholder="t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.HISTORY_PLACEHOLDER')"
      :max-length="MAX_CONVERSATION_LENGTH"
    />
    <div class="flex flex-col gap-2">
      <label for="ai-agent-retrieval-query" class="text-label text-n-slate-12">
        {{ t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.LABEL') }}
      </label>
      <div class="flex flex-wrap items-start gap-2">
        <Input
          id="ai-agent-retrieval-query"
          v-model="query"
          :placeholder="t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.PLACEHOLDER')"
          :maxlength="MAX_QUERY_LENGTH"
          class="flex-1 min-w-56"
          autofocus
        />
        <Button
          type="submit"
          :label="t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.RUN')"
          :disabled="!trimmedQuery || isPending"
          :is-loading="isPending"
        />
      </div>
    </div>
    <div class="flex flex-col gap-1">
      <Input
        v-model="webQuery"
        :label="t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB_QUERY_LABEL')"
        :placeholder="
          t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB_QUERY_PLACEHOLDER')
        "
        :maxlength="MAX_WEB_QUERY_LENGTH"
      />
      <p class="text-label-small text-n-slate-11">
        {{ t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB_QUERY_HELP') }}
      </p>
    </div>

    <div v-if="result" class="flex flex-col gap-3">
      <div class="flex flex-col gap-1 text-body-main text-n-slate-11">
        <p>{{ modeDescription }}</p>
        <p>{{ t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.QUERIES') }}</p>
        <ul class="flex flex-col gap-1 ps-4 list-disc">
          <li
            v-for="searched in result.queries"
            :key="searched"
            class="break-words whitespace-pre-wrap"
          >
            {{ searched }}
          </li>
        </ul>
        <p>
          {{
            t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.LIMIT', {
              count: result.context_limit,
            })
          }}
        </p>
      </div>
      <p
        v-if="!result.chunks.length"
        class="px-6 py-8 text-center rounded-xl text-body-main text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        {{ t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.NO_RESULTS') }}
      </p>
      <ol v-else class="flex flex-col gap-3">
        <li
          v-for="chunk in result.chunks"
          :key="chunk.rank"
          class="flex flex-col gap-2 p-3 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <div class="flex items-center min-w-0 gap-2">
            <span
              class="px-2 py-0.5 rounded-md shrink-0 tabular-nums text-label-small bg-n-alpha-2 text-n-slate-12"
            >
              {{
                t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.RANK', {
                  rank: chunk.rank,
                })
              }}
            </span>
            <span class="shrink-0 text-label-small text-n-slate-11">
              {{ sourceTypeLabels[chunk.source.type] }}
            </span>
            <span
              class="flex-1 min-w-0 truncate text-heading-3 text-n-slate-12"
            >
              {{ chunk.source.title }}
            </span>
            <span
              class="shrink-0 tabular-nums text-label-small text-n-slate-11"
            >
              {{
                t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.SCORE', {
                  score: formatScore(chunk.score),
                })
              }}
            </span>
          </div>
          <p
            class="whitespace-pre-wrap break-words text-body-main text-n-slate-11"
          >
            {{ chunk.content }}
          </p>
        </li>
      </ol>
    </div>

    <div v-if="result?.web" class="flex flex-col gap-3">
      <div class="flex flex-col gap-1">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.TITLE') }}
        </h3>
        <p class="text-body-main text-n-slate-11">
          {{ webStatusDescription }}
        </p>
      </div>
      <p
        v-if="webSearchFoundNothing"
        class="px-6 py-8 text-center rounded-xl text-body-main text-n-slate-11 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        {{ t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.WEB.NO_RESULTS') }}
      </p>
      <ol v-else-if="result.web.results.length" class="flex flex-col gap-3">
        <li
          v-for="item in result.web.results"
          :key="item.rank"
          class="flex flex-col gap-2 p-3 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <div class="flex items-center min-w-0 gap-2">
            <span
              class="px-2 py-0.5 rounded-md shrink-0 tabular-nums text-label-small bg-n-alpha-2 text-n-slate-12"
            >
              {{
                t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.RANK', {
                  rank: item.rank,
                })
              }}
            </span>
            <span
              class="flex-1 min-w-0 truncate text-heading-3 text-n-slate-12"
            >
              {{ item.title }}
            </span>
            <span
              v-if="item.published_at"
              class="shrink-0 tabular-nums text-label-small text-n-slate-11"
            >
              {{ formatPublishedDate(item.published_at) }}
            </span>
          </div>
          <a
            :href="webUrlLink(item.url)"
            target="_blank"
            rel="noopener noreferrer"
            class="break-all text-body-main text-n-slate-11 hover:underline"
          >
            {{ item.url }}
          </a>
          <p
            v-for="(highlight, index) in item.highlights"
            :key="index"
            class="whitespace-pre-wrap break-words text-body-main text-n-slate-11"
          >
            {{ highlight }}
          </p>
        </li>
      </ol>
    </div>
  </Dialog>
</template>
