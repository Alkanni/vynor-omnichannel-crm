<script setup>
import { getCurrentInstance, ref } from 'vue';

import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  icon: {
    type: String,
    required: true,
  },
});

const isOpen = ref(false);
const contentId = `ai-agent-panel-${getCurrentInstance().uid}`;
</script>

<template>
  <section
    class="rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
  >
    <button
      type="button"
      class="flex items-center w-full gap-3 p-4 rounded-xl text-start hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-expanded="isOpen"
      :aria-controls="contentId"
      @click="isOpen = !isOpen"
    >
      <span
        class="flex items-center justify-center rounded-lg size-9 shrink-0 bg-n-alpha-2 text-n-brand"
      >
        <Icon :icon="icon" class="size-5" />
      </span>
      <span class="flex flex-col flex-1 min-w-0 gap-0.5">
        <span class="text-heading-3 text-n-slate-12">{{ title }}</span>
        <span v-if="description" class="text-label-small text-n-slate-11">
          {{ description }}
        </span>
      </span>
      <Icon
        icon="i-lucide-chevron-down"
        class="transition-transform duration-200 size-4 text-n-slate-11"
        :class="{ 'rotate-180': isOpen }"
      />
    </button>
    <div
      v-if="isOpen"
      :id="contentId"
      class="flex flex-col gap-6 px-4 pt-2 pb-5"
    >
      <slot />
    </div>
  </section>
</template>
