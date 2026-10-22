<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

defineProps({
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const dialogRef = ref(null);
const title = ref('');
const isRename = ref(false);

const trimmedTitle = computed(() => title.value.trim());

const open = (currentTitle = '') => {
  title.value = currentTitle;
  isRename.value = Boolean(currentTitle);
  dialogRef.value.open();
};

const submit = () => {
  if (trimmedTitle.value) emit('submit', trimmedTitle.value);
};

defineExpose({ open, close: () => dialogRef.value.close() });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isRename
        ? t('AI_AGENTS.KNOWLEDGE.TEXT.TITLE_DIALOG.RENAME_TITLE')
        : t('AI_AGENTS.KNOWLEDGE.TEXT.TITLE_DIALOG.CREATE_TITLE')
    "
    :confirm-button-label="
      isRename
        ? t('AI_AGENTS.KNOWLEDGE.TEXT.TITLE_DIALOG.RENAME_CONFIRM')
        : t('AI_AGENTS.KNOWLEDGE.TEXT.TITLE_DIALOG.CREATE_CONFIRM')
    "
    :disable-confirm-button="!trimmedTitle"
    :is-loading="isLoading"
    @confirm="submit"
  >
    <Input
      id="ai-agent-text-title"
      v-model="title"
      :label="t('AI_AGENTS.KNOWLEDGE.TEXT.TITLE_DIALOG.LABEL')"
      :placeholder="t('AI_AGENTS.KNOWLEDGE.TEXT.TITLE_DIALOG.PLACEHOLDER')"
      autofocus
    />
  </Dialog>
</template>
