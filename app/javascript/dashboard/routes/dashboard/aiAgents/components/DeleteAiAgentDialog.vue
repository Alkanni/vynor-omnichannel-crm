<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const emit = defineEmits(['deleted']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const agent = ref(null);
const isDeleting = ref(false);

const open = selectedAgent => {
  agent.value = selectedAgent;
  dialogRef.value.open();
};

const deleteAgent = async () => {
  isDeleting.value = true;
  try {
    await store.dispatch('aiAgents/delete', agent.value.id);
    useAlert(t('AI_AGENTS.DELETE.SUCCESS'));
    dialogRef.value.close();
    emit('deleted', agent.value);
  } catch (error) {
    useAlert(error.message || t('AI_AGENTS.DELETE.ERROR'));
  } finally {
    isDeleting.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('AI_AGENTS.DELETE.TITLE', { name: agent?.name })"
    :description="t('AI_AGENTS.DELETE.DESCRIPTION')"
    :confirm-button-label="t('AI_AGENTS.DELETE.CONFIRM')"
    :is-loading="isDeleting"
    @confirm="deleteAgent"
  />
</template>
