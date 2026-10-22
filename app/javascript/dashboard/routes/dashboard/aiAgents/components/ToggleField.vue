<script setup>
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
});

const modelValue = defineModel({ type: Boolean, default: false });
</script>

<template>
  <div class="flex items-start justify-between gap-4">
    <div class="flex flex-col gap-0.5 min-w-0">
      <h3 class="text-heading-3 text-n-slate-12">{{ title }}</h3>
      <p v-if="description" class="text-label-small text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <Switch v-model="modelValue" class="mt-1" />
  </div>
</template>
