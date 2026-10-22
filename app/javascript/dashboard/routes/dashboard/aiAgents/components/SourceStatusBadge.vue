<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  status: {
    type: String,
    required: true,
  },
  errorMessage: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();

const STATUS_STYLES = {
  pending: 'bg-n-slate-3 text-n-slate-11',
  processing: 'bg-n-blue-3 text-n-blue-11',
  ready: 'bg-n-teal-3 text-n-teal-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
};

const label = computed(
  () =>
    ({
      pending: t('AI_AGENTS.KNOWLEDGE.STATUS.PENDING'),
      processing: t('AI_AGENTS.KNOWLEDGE.STATUS.PROCESSING'),
      ready: t('AI_AGENTS.KNOWLEDGE.STATUS.READY'),
      failed: t('AI_AGENTS.KNOWLEDGE.STATUS.FAILED'),
    })[props.status]
);
</script>

<template>
  <span
    v-tooltip.top="status === 'failed' ? errorMessage : ''"
    class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md shrink-0 text-label-small"
    :class="STATUS_STYLES[status]"
  >
    <span
      v-if="status === 'processing'"
      class="i-lucide-loader-circle size-3 animate-spin"
    />
    {{ label }}
  </span>
</template>
