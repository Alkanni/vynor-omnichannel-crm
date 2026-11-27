<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';

// The agent's own booking fields (see AiAgent::BookingFields): a name, a description for the AI, a type, the options of a
// choice, and whether the AI needs the field to record a booking. Only a choice has options.
const MAX_FIELDS = 10;
const DESCRIPTION_MAX_LENGTH = 200;
const CHOICE = 'choice';

const fields = defineModel({ type: Array, required: true });

const { t } = useI18n();

const typeOptions = computed(() => [
  { value: 'text', label: t('AI_AGENTS.GENERAL.BOOKING.FIELDS.TYPES.TEXT') },
  {
    value: 'number',
    label: t('AI_AGENTS.GENERAL.BOOKING.FIELDS.TYPES.NUMBER'),
  },
  { value: CHOICE, label: t('AI_AGENTS.GENERAL.BOOKING.FIELDS.TYPES.CHOICE') },
]);

const update = (index, changes) => {
  fields.value = fields.value.map((field, position) =>
    position === index ? { ...field, ...changes } : field
  );
};

const setType = (index, type) => update(index, { type, options: [] });

const add = () => {
  fields.value = [
    ...fields.value,
    { name: '', description: '', type: 'text', options: [], required: false },
  ];
};

const remove = index => {
  fields.value = fields.value.filter((_, position) => position !== index);
};

const move = (index, offset) => {
  const moved = [...fields.value];
  [moved[index], moved[index + offset]] = [moved[index + offset], moved[index]];
  fields.value = moved;
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-for="(field, index) in fields"
      :key="index"
      class="flex flex-col gap-2 p-3 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <div class="flex items-center gap-2">
        <Input
          :model-value="field.name"
          class="flex-1"
          :placeholder="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.NAME_PLACEHOLDER')"
          :aria-label="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.NAME')"
          @update:model-value="name => update(index, { name })"
        />
        <Select
          :model-value="field.type"
          :options="typeOptions"
          :aria-label="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.TYPE')"
          @update:model-value="type => setType(index, type)"
        />
      </div>
      <Input
        :model-value="field.description"
        :placeholder="
          t('AI_AGENTS.GENERAL.BOOKING.FIELDS.DESCRIPTION_PLACEHOLDER')
        "
        :aria-label="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.FIELD_DESCRIPTION')"
        :maxlength="DESCRIPTION_MAX_LENGTH"
        @update:model-value="description => update(index, { description })"
      />
      <TagInput
        v-if="field.type === CHOICE"
        :model-value="field.options"
        :placeholder="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.OPTIONS_PLACEHOLDER')"
        @update:model-value="options => update(index, { options })"
      />
      <div class="flex items-center justify-between gap-2">
        <label class="flex items-center gap-2 text-label-small text-n-slate-12">
          <Checkbox
            :model-value="field.required"
            @update:model-value="required => update(index, { required })"
          />
          {{ t('AI_AGENTS.GENERAL.BOOKING.FIELDS.REQUIRED') }}
        </label>
        <div class="flex items-center gap-1">
          <Button
            type="button"
            icon="i-lucide-arrow-up"
            color="slate"
            variant="ghost"
            size="sm"
            :aria-label="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.MOVE_UP')"
            :disabled="index === 0"
            @click="move(index, -1)"
          />
          <Button
            type="button"
            icon="i-lucide-arrow-down"
            color="slate"
            variant="ghost"
            size="sm"
            :aria-label="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.MOVE_DOWN')"
            :disabled="index === fields.length - 1"
            @click="move(index, 1)"
          />
          <Button
            type="button"
            icon="i-lucide-trash"
            color="slate"
            variant="ghost"
            size="sm"
            :aria-label="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.REMOVE')"
            @click="remove(index)"
          />
        </div>
      </div>
    </div>
    <Button
      type="button"
      :label="t('AI_AGENTS.GENERAL.BOOKING.FIELDS.ADD')"
      icon="i-lucide-plus"
      color="slate"
      variant="faded"
      size="sm"
      class="self-start"
      :disabled="fields.length >= MAX_FIELDS"
      @click="add"
    />
  </div>
</template>
