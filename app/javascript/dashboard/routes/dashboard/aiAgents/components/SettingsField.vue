<script setup>
defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  badge: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex items-start justify-between gap-3">
      <div class="flex flex-col gap-0.5 min-w-0">
        <h3 class="text-heading-3 text-n-slate-12">{{ title }}</h3>
        <p v-if="description" class="text-label-small text-n-slate-11">
          {{ description }}
        </p>
      </div>
      <span
        v-if="badge"
        class="px-2 py-0.5 rounded-md shrink-0 text-label-small bg-n-alpha-2 text-n-slate-11"
      >
        {{ badge }}
      </span>
    </div>
    <slot />
  </div>
</template>
