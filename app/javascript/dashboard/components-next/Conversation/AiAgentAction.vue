<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import wootConstants from 'dashboard/constants/globals';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

// Shows whether the inbox's AI agent answers the conversation (meta.ai_agent) and lets the agent take it over or
// hand it back. A pending conversation belongs to the AI agent, so both are status changes.
const props = defineProps({
  conversation: { type: Object, required: true },
});

const { OPEN, PENDING } = wootConstants.STATUS_TYPE;

const store = useStore();
const { t } = useI18n();

const showDropdown = ref(false);
const isLoading = ref(false);

const aiAgent = computed(() => props.conversation.meta?.ai_agent);
const isVisible = computed(
  () => aiAgent.value && [OPEN, PENDING].includes(props.conversation.status)
);
// The button shows the state and its menu offers the one status change that flips it.
const control = computed(() => {
  const agentName = aiAgent.value.name;
  if (aiAgent.value.active) {
    return {
      label: t('CONVERSATION.AI_AGENT_ACTION.ACTIVE'),
      tooltip: t('CONVERSATION.AI_AGENT_ACTION.ACTIVE_TOOLTIP', { agentName }),
      icon: 'i-lucide-bot',
      color: 'teal',
      variant: 'faded',
      item: {
        label: t('CONVERSATION.AI_AGENT_ACTION.TAKE_OVER'),
        action: OPEN,
        value: OPEN,
        icon: 'i-lucide-user-check',
      },
    };
  }
  return {
    label: t('CONVERSATION.AI_AGENT_ACTION.INACTIVE'),
    tooltip: t('CONVERSATION.AI_AGENT_ACTION.INACTIVE_TOOLTIP', { agentName }),
    icon: 'i-lucide-bot-off',
    color: 'slate',
    variant: 'outline',
    item: {
      label: t('CONVERSATION.AI_AGENT_ACTION.HAND_OVER', { agentName }),
      action: PENDING,
      value: PENDING,
      icon: 'i-lucide-bot',
    },
  };
});

const changeStatus = async ({ action }) => {
  showDropdown.value = false;
  isLoading.value = true;
  await store.dispatch('toggleStatus', {
    conversationId: props.conversation.id,
    status: action,
  });
  isLoading.value = false;
  useAlert(t('CONVERSATION.CHANGE_STATUS'));
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div
    v-if="isVisible"
    v-on-clickaway="() => (showDropdown = false)"
    class="relative flex items-center"
  >
    <Button
      v-tooltip.bottom="control.tooltip"
      :label="control.label"
      :icon="control.icon"
      :color="control.color"
      :variant="control.variant"
      size="sm"
      no-animation
      :is-loading="isLoading"
      @click="showDropdown = !showDropdown"
    />
    <DropdownMenu
      v-if="showDropdown"
      :menu-items="[control.item]"
      class="mt-1 ltr:right-0 rtl:left-0 top-full"
      @action="changeStatus"
    />
  </div>
</template>
