<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';

// How a ready source is indexed, from the knowledge sources API:
// { status: 'indexed' | 'outdated' | 'not_indexed', chunks, other_model_chunks, indexed_at }.
const props = defineProps({
  index: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const needsAttention = computed(
  () => props.index.status !== 'indexed' || props.index.other_model_chunks > 0
);

const label = computed(() =>
  t(
    'AI_AGENTS.KNOWLEDGE.CHUNKS.COUNT',
    { count: props.index.chunks },
    props.index.chunks
  )
);

const detail = computed(() => {
  const { status, other_model_chunks: otherModelChunks } = props.index;
  if (status === 'not_indexed')
    return t('AI_AGENTS.KNOWLEDGE.INDEX.NOT_INDEXED');
  if (status === 'outdated') return t('AI_AGENTS.KNOWLEDGE.INDEX.OUTDATED');
  if (otherModelChunks > 0) {
    return t(
      'AI_AGENTS.KNOWLEDGE.INDEX.OTHER_MODEL',
      { count: otherModelChunks },
      otherModelChunks
    );
  }
  return t('AI_AGENTS.KNOWLEDGE.CHUNKS.INDEXED', {
    time: dynamicTime(props.index.indexed_at),
  });
});
</script>

<template>
  <span
    v-tooltip.top="detail"
    :aria-label="`${label}. ${detail}`"
    role="img"
    class="inline-flex items-center gap-1 shrink-0 text-label-small"
    :class="needsAttention ? 'text-n-amber-11' : 'text-n-slate-11'"
  >
    <span v-if="needsAttention" class="i-lucide-circle-alert size-3" />
    {{ label }}
  </span>
</template>
