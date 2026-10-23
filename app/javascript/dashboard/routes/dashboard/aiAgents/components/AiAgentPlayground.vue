<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AiAgentsAPI from 'dashboard/api/aiAgents';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

import Button from 'dashboard/components-next/button/Button.vue';
import MessageList from 'dashboard/components-next/captain/assistant/MessageList.vue';

const props = defineProps({
  agentId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();

const messages = ref([]);
const draft = ref('');
const isLoading = ref(false);
// Replies to a conversation that was reset meanwhile are dropped.
let conversationVersion = 0;

const canSend = computed(() => draft.value.trim() && !isLoading.value);

const reset = () => {
  conversationVersion += 1;
  messages.value = [];
  draft.value = '';
  isLoading.value = false;
};

const send = async () => {
  if (!canSend.value) return;

  messages.value.push({ sender: 'user', content: draft.value.trim() });
  draft.value = '';
  const version = conversationVersion;
  const history = messages.value
    .filter(message => !message.isError)
    .map(message => ({
      role: message.sender === 'user' ? 'user' : 'assistant',
      content: message.content,
    }));

  isLoading.value = true;
  try {
    const { data } = await AiAgentsAPI.playground(props.agentId, history);
    if (version !== conversationVersion) return;
    data.messages.forEach(content => {
      messages.value.push({ sender: 'assistant', content });
    });
  } catch (error) {
    if (version !== conversationVersion) return;
    const reason = parseAPIErrorResponse(error);
    messages.value.push({
      sender: 'assistant',
      isError: true,
      content:
        typeof reason === 'string' ? reason : t('AI_AGENTS.PLAYGROUND.ERROR'),
    });
  } finally {
    if (version === conversationVersion) isLoading.value = false;
  }
};

const onEnter = event => {
  if (event.isComposing) return;
  event.preventDefault();
  send();
};

watch(() => props.agentId, reset);
</script>

<template>
  <section class="flex flex-col h-full min-h-0 py-5">
    <header class="flex items-start justify-between gap-3 px-6 mb-4">
      <div class="flex flex-col gap-1">
        <h2 class="text-heading-2 text-n-slate-12">
          {{ t('AI_AGENTS.PLAYGROUND.TITLE') }}
        </h2>
        <p class="text-body-main text-n-slate-11">
          {{ t('AI_AGENTS.PLAYGROUND.DESCRIPTION') }}
        </p>
      </div>
      <Button
        v-tooltip.top="t('AI_AGENTS.PLAYGROUND.RESET')"
        :aria-label="t('AI_AGENTS.PLAYGROUND.RESET')"
        icon="i-lucide-rotate-ccw"
        color="slate"
        variant="ghost"
        size="sm"
        :disabled="!messages.length"
        @click="reset"
      />
    </header>

    <MessageList :messages="messages" :is-loading="isLoading" />

    <form
      class="flex items-center gap-2 p-3 mx-6 rounded-xl bg-n-background outline outline-1 outline-n-weak"
      @submit.prevent="send"
    >
      <input
        v-model="draft"
        :aria-label="t('AI_AGENTS.PLAYGROUND.PLACEHOLDER')"
        :placeholder="t('AI_AGENTS.PLAYGROUND.PLACEHOLDER')"
        class="flex-1 min-w-0 mb-0 bg-transparent border-none text-body-main text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none"
        @keydown.enter.exact="onEnter"
      />
      <Button
        type="submit"
        :aria-label="t('AI_AGENTS.PLAYGROUND.SEND')"
        icon="i-lucide-send"
        variant="ghost"
        size="sm"
        :disabled="!canSend"
      />
    </form>
  </section>
</template>
