<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  stats: {
    type: Object,
    required: true,
  },
});

const { t, locale } = useI18n();

const formatNumber = value =>
  new Intl.NumberFormat(locale.value).format(value || 0);

const rows = computed(() => [
  {
    key: 'text',
    label: t('AI_AGENTS.KNOWLEDGE.STATS.TEXT_CHARACTERS'),
    value: formatNumber(props.stats.text_characters),
  },
  {
    key: 'qa',
    label: t('AI_AGENTS.KNOWLEDGE.STATS.QA'),
    value: t(
      'AI_AGENTS.KNOWLEDGE.STATS.QA_VALUE',
      {
        count: formatNumber(props.stats.qa_count),
        characters: formatNumber(props.stats.qa_characters),
      },
      props.stats.qa_count || 0
    ),
  },
  {
    key: 'products',
    label: t('AI_AGENTS.KNOWLEDGE.STATS.PRODUCTS'),
    value: formatNumber(props.stats.products),
  },
]);
</script>

<template>
  <aside
    class="flex flex-col gap-4 p-5 rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
  >
    <h2 class="text-heading-3 text-n-slate-12">
      {{ t('AI_AGENTS.KNOWLEDGE.STATS.TITLE') }}
    </h2>
    <dl class="flex flex-col gap-3">
      <div v-for="row in rows" :key="row.key" class="flex flex-col gap-0.5">
        <dt class="text-label-small text-n-slate-11">{{ row.label }}</dt>
        <dd class="text-heading-2 tabular-nums text-n-slate-12">
          {{ row.value }}
        </dd>
      </div>
      <div class="flex flex-col gap-0.5 pt-3 border-t border-n-weak">
        <dt class="text-label-small text-n-slate-11">
          {{ t('AI_AGENTS.KNOWLEDGE.STATS.TOTAL_CHARACTERS') }}
        </dt>
        <dd class="text-heading-1 tabular-nums text-n-slate-12">
          {{ formatNumber(stats.total_characters) }}
        </dd>
      </div>
    </dl>
  </aside>
</template>
