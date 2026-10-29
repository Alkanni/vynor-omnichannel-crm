<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AiAgentKnowledgeAPI from 'dashboard/api/aiAgentKnowledge';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { dynamicTime } from 'shared/helpers/timeHelper';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
});

const { t, locale } = useI18n();
const { run, abort, isPending } = useAbortableRequest();

const dialogRef = ref(null);
const sourceTitle = ref('');
const chunks = ref([]);
const embeddingModel = ref(null);
const hasError = ref(false);

const unsearchableCount = computed(
  () => chunks.value.filter(chunk => !chunk.searchable).length
);

const formatNumber = value => new Intl.NumberFormat(locale.value).format(value);

const open = async source => {
  sourceTitle.value = source.title;
  chunks.value = [];
  hasError.value = false;
  dialogRef.value.open();
  try {
    const data = await run(async signal => {
      const response = await AiAgentKnowledgeAPI.getSourceChunks(
        props.agentId,
        source.id,
        { signal }
      );
      return response.data;
    });
    if (!data) return;
    chunks.value = data.payload;
    embeddingModel.value = data.embedding_model;
  } catch {
    hasError.value = true;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AI_AGENTS.KNOWLEDGE.CHUNKS.TITLE', { title: sourceTitle })"
    :description="t('AI_AGENTS.KNOWLEDGE.CHUNKS.DESCRIPTION')"
    :cancel-button-label="t('AI_AGENTS.KNOWLEDGE.CHUNKS.CLOSE')"
    :show-confirm-button="false"
    width="3xl"
    overflow-y-auto
    @close="abort"
  >
    <div v-if="isPending" class="flex justify-center py-6">
      <Spinner />
    </div>
    <p v-else-if="hasError" class="text-body-main text-n-ruby-11">
      {{ t('AI_AGENTS.KNOWLEDGE.CHUNKS.LOAD_ERROR') }}
    </p>
    <p v-else-if="!chunks.length" class="text-body-main text-n-slate-11">
      {{ t('AI_AGENTS.KNOWLEDGE.CHUNKS.EMPTY') }}
    </p>
    <div v-else class="flex flex-col gap-3">
      <p class="text-body-main text-n-slate-11">
        {{
          t(
            'AI_AGENTS.KNOWLEDGE.CHUNKS.COUNT',
            { count: chunks.length },
            chunks.length
          )
        }}
      </p>
      <p
        v-if="unsearchableCount"
        class="flex items-start gap-2 p-3 rounded-lg bg-n-amber-2 text-body-main text-n-amber-11"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 mt-0.5 shrink-0" />
        {{
          t(
            'AI_AGENTS.KNOWLEDGE.CHUNKS.UNSEARCHABLE',
            { count: unsearchableCount, model: embeddingModel },
            unsearchableCount
          )
        }}
      </p>
      <ol class="flex flex-col gap-3">
        <li
          v-for="chunk in chunks"
          :key="chunk.id"
          class="flex flex-col gap-2 p-3 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <div
            class="flex flex-wrap items-center gap-x-3 gap-y-1 text-label-small text-n-slate-11"
          >
            <span class="text-n-slate-12">
              {{
                t('AI_AGENTS.KNOWLEDGE.CHUNKS.POSITION', {
                  position: chunk.position,
                })
              }}
            </span>
            <span class="tabular-nums">
              {{
                t('AI_AGENTS.KNOWLEDGE.CHARACTERS', {
                  count: formatNumber(chunk.content.length),
                })
              }}
            </span>
            <span>
              {{
                chunk.embedding_model ||
                t('AI_AGENTS.KNOWLEDGE.CHUNKS.NO_EMBEDDING')
              }}
            </span>
            <span>
              {{
                t('AI_AGENTS.KNOWLEDGE.CHUNKS.INDEXED', {
                  time: dynamicTime(chunk.indexed_at),
                })
              }}
            </span>
            <span
              v-if="!chunk.searchable"
              class="px-2 py-0.5 rounded-md bg-n-amber-3 text-n-amber-11"
            >
              {{ t('AI_AGENTS.KNOWLEDGE.CHUNKS.NOT_SEARCHED') }}
            </span>
          </div>
          <p
            class="whitespace-pre-wrap break-words text-body-main text-n-slate-12"
          >
            {{ chunk.content }}
          </p>
        </li>
      </ol>
    </div>
  </Dialog>
</template>
