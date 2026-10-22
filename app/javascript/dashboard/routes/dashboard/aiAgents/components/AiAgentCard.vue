<script setup>
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['settings', 'duplicate', 'delete']);

const { t } = useI18n();
</script>

<template>
  <article
    class="flex flex-col items-center gap-3 px-5 py-6 text-center rounded-xl bg-n-solid-2 outline outline-1 -outline-offset-1 outline-n-container"
  >
    <h3 class="w-full truncate text-heading-2 text-n-slate-12">
      {{ agent.name }}
    </h3>
    <Avatar :name="agent.name" :size="44" rounded-full />
    <p class="w-full truncate text-body-main text-n-slate-11">
      {{ agent.behavior || t('AI_AGENTS.CARD.NO_BEHAVIOR') }}
    </p>
    <div class="flex items-center justify-center gap-2">
      <Button
        :label="t('AI_AGENTS.CARD.SETTINGS')"
        icon="i-lucide-settings"
        color="slate"
        variant="outline"
        size="sm"
        @click="emit('settings', agent)"
      />
      <Button
        v-tooltip.top="t('AI_AGENTS.CARD.DUPLICATE')"
        :aria-label="t('AI_AGENTS.CARD.DUPLICATE')"
        icon="i-lucide-copy"
        color="blue"
        variant="outline"
        size="sm"
        @click="emit('duplicate', agent)"
      />
      <Button
        v-tooltip.top="t('AI_AGENTS.CARD.DELETE')"
        :aria-label="t('AI_AGENTS.CARD.DELETE')"
        icon="i-lucide-trash-2"
        color="ruby"
        variant="outline"
        size="sm"
        @click="emit('delete', agent)"
      />
    </div>
  </article>
</template>
