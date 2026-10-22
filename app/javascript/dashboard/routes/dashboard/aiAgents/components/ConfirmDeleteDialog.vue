<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

defineProps({
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['confirm']);

const { t } = useI18n();

const dialogRef = ref(null);

defineExpose({
  open: () => dialogRef.value.open(),
  close: () => dialogRef.value.close(),
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="title"
    :description="description"
    :confirm-button-label="t('AI_AGENTS.KNOWLEDGE.CONFIRM_DELETE.CONFIRM')"
    :is-loading="isLoading"
    @confirm="emit('confirm')"
  />
</template>
