import { computed, watch } from 'vue';
import { useIntervalFn } from '@vueuse/core';

const POLL_INTERVAL_MS = 3000;
const IN_PROGRESS_STATUSES = ['pending', 'processing'];

// Refreshes the list while any knowledge source is still being processed.
export const useProcessingPoll = (sources, refresh) => {
  const hasInProgress = computed(() =>
    sources.value.some(source => IN_PROGRESS_STATUSES.includes(source.status))
  );
  const { pause, resume } = useIntervalFn(refresh, POLL_INTERVAL_MS, {
    immediate: false,
  });

  watch(
    hasInProgress,
    inProgress => {
      if (inProgress) resume();
      else pause();
    },
    { immediate: true }
  );

  return { hasInProgress };
};
