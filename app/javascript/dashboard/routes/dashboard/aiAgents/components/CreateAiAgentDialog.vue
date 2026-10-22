<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const emit = defineEmits(['created']);

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const name = ref('');
const isCreating = ref(false);

const trimmedName = computed(() => name.value.trim());

const open = () => {
  name.value = '';
  dialogRef.value.open();
};

const createAgent = async () => {
  if (!trimmedName.value) return;

  isCreating.value = true;
  try {
    const agent = await store.dispatch('aiAgents/create', {
      name: trimmedName.value,
    });
    useAlert(t('AI_AGENTS.CREATE.SUCCESS'));
    dialogRef.value.close();
    emit('created', agent);
  } catch (error) {
    useAlert(error.message || t('AI_AGENTS.CREATE.ERROR'));
  } finally {
    isCreating.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('AI_AGENTS.CREATE.TITLE')"
    :description="t('AI_AGENTS.CREATE.DESCRIPTION')"
    :confirm-button-label="t('AI_AGENTS.CREATE.CONFIRM')"
    :disable-confirm-button="!trimmedName"
    :is-loading="isCreating"
    @confirm="createAgent"
  >
    <Input
      id="ai-agent-create-name"
      v-model="name"
      :label="t('AI_AGENTS.CREATE.NAME_LABEL')"
      :placeholder="t('AI_AGENTS.CREATE.NAME_PLACEHOLDER')"
      autofocus
    />
  </Dialog>
</template>
