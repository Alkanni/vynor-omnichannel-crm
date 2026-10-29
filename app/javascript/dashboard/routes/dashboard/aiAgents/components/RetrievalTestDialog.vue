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

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
});

// Same limit as AiAgents::ReplyGenerator::MAX_QUERY_CHARACTERS.
const MAX_QUERY_LENGTH = 4000;

const { t, locale } = useI18n();
const { run, abort, isPending } = useAbortableRequest();

const dialogRef = ref(null);
const query = ref('');
const result = ref(null);

const trimmedQuery = computed(() => query.value.trim());
const sourceTypeLabels = computed(() => ({
  text: t('AI_AGENTS.KNOWLEDGE.TABS.TEXT'),
  website: t('AI_AGENTS.KNOWLEDGE.TABS.WEBSITE'),
  file: t('AI_AGENTS.KNOWLEDGE.TABS.FILE'),
  qa: t('AI_AGENTS.KNOWLEDGE.TABS.QA'),
  product: t('AI_AGENTS.KNOWLEDGE.TABS.PRODUCT'),
}));
const modeDescription = computed(() =>
  result.value.mode === 'vector'
    ? t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.MODE_VECTOR', {
        model: result.value.embedding_model,
      })
    : t('AI_AGENTS.KNOWLEDGE.RETRIEVAL_TEST.MODE_KEYWORD')
);

const formatScore = score =>
  new Intl.NumberFormat(locale.value, { maximumFractionDigits: 4 }).format(
    score
  );

const runTest = async () => {
  if (!trimmedQuery.value) return;
  try {
    const data = await run(async signal => {
      const response = await AiAgentKnowledgeAPI.testRetrieval(
        props.agentId,
        trimmedQuery.value,
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

    <div v-if="result" class="flex flex-col gap-3">
      <div class="flex flex-col gap-1 text-body-main text-n-slate-11">
        <p>{{ modeDescription }}</p>
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
  </Dialog>
</template>
