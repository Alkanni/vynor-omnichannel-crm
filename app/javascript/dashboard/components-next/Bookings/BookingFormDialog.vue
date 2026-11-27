<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BookingsAPI from 'dashboard/api/bookings';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import {
  localDate,
  localDateTime,
  localTime,
  slotTakenMessage,
} from './helpers';

const props = defineProps({
  // The display id of the conversation a new booking is recorded for.
  conversationId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['saved']);

const NOTES_MAX_LENGTH = 5000;
const FIELD_TYPES = { number: 'number', choice: 'choice' };

const { t } = useI18n();
const dialogRef = ref(null);
const booking = ref(null);
const isSaving = ref(false);
// Why the last save was refused: the slot a confirmed booking holds, shown in the dialog so staff pick another one.
const slotTaken = ref('');
// The fields and services of the AI agent of the conversation (see AiAgent::BookingFields). They only guide the staff: a
// required field may stay empty, and a value outside the options or the services stays one to choose.
const agentFields = ref([]);
const services = ref([]);
const form = reactive({
  service: '',
  customerName: '',
  date: '',
  time: '',
  notes: '',
  details: {},
});

const isComplete = computed(() =>
  [form.service, form.customerName, form.date, form.time].every(value =>
    value.trim()
  )
);

const fieldsByName = computed(() =>
  Object.fromEntries(agentFields.value.map(field => [field.name, field]))
);

const withValue = (choices, value) =>
  value && !choices.includes(value) ? [...choices, value] : choices;

const toOptions = choices => choices.map(value => ({ value, label: value }));

const serviceOptions = computed(() =>
  toOptions(withValue(services.value, form.service))
);

const choiceOptions = (field, value) => [
  { value: '', label: t('BOOKINGS.FORM.NO_CHOICE') },
  ...toOptions(withValue(field.options, value)),
];

const fieldLabel = name =>
  fieldsByName.value[name]?.required
    ? t('BOOKINGS.FORM.REQUIRED_FIELD', { name })
    : name;

// A new booking starts with the customer's name and the agent's fields; an existing one with its own values, in the
// viewer's time zone. Both load the fields of the conversation's agent first.
const open = async ({ current = null, customerName = '' } = {}) => {
  try {
    const { data } = await BookingsAPI.fields(
      current ? current.conversation.display_id : props.conversationId
    );
    agentFields.value = data.fields;
    services.value = data.services;
  } catch {
    useAlert(t('BOOKINGS.FORM.FIELDS_ERROR'));
    return;
  }
  booking.value = current;
  slotTaken.value = '';
  const at = current && new Date(current.scheduled_at);
  Object.assign(form, {
    service: current?.service || '',
    customerName: current?.customer_name || customerName,
    date: at ? localDate(at) : '',
    time: at ? localTime(at) : '',
    notes: current?.notes || '',
    details: current
      ? { ...current.details }
      : Object.fromEntries(agentFields.value.map(field => [field.name, ''])),
  });
  dialogRef.value.open();
};

const save = async () => {
  if (!isComplete.value || isSaving.value) return;

  const fields = {
    service: form.service,
    customer_name: form.customerName,
    scheduled_at: localDateTime(form.date, form.time),
    notes: form.notes,
    details: form.details,
  };
  isSaving.value = true;
  slotTaken.value = '';
  try {
    const { data } = booking.value
      ? await BookingsAPI.update(booking.value.id, fields)
      : await BookingsAPI.create({
          ...fields,
          conversation_id: props.conversationId,
        });
    emit('saved', data);
    useAlert(t('BOOKINGS.FORM.SAVE_SUCCESS'));
    dialogRef.value.close();
  } catch (error) {
    slotTaken.value = slotTakenMessage(error) || '';
    if (!slotTaken.value) useAlert(t('BOOKINGS.FORM.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      booking ? t('BOOKINGS.FORM.EDIT_TITLE') : t('BOOKINGS.FORM.NEW_TITLE')
    "
    :description="t('BOOKINGS.FORM.DESCRIPTION')"
    :confirm-button-label="t('BOOKINGS.FORM.SAVE')"
    :is-loading="isSaving"
    :disable-confirm-button="!isComplete || isSaving"
    @confirm="save"
  >
    <div class="flex flex-col gap-3">
      <Banner v-if="slotTaken" color="amber">{{ slotTaken }}</Banner>
      <div v-if="services.length" class="flex flex-col gap-1">
        <span class="mb-0.5 text-heading-3 text-n-slate-12">
          {{ t('BOOKINGS.FORM.SERVICE') }}
        </span>
        <Select
          v-model="form.service"
          :options="serviceOptions"
          :placeholder="t('BOOKINGS.FORM.CHOOSE_SERVICE')"
          :aria-label="t('BOOKINGS.FORM.SERVICE')"
        />
      </div>
      <Input
        v-else
        id="booking-service"
        v-model="form.service"
        :label="t('BOOKINGS.FORM.SERVICE')"
      />
      <Input
        id="booking-customer-name"
        v-model="form.customerName"
        :label="t('BOOKINGS.FORM.CUSTOMER_NAME')"
      />
      <div class="flex gap-3">
        <Input
          id="booking-date"
          v-model="form.date"
          type="date"
          class="flex-1"
          :label="t('BOOKINGS.FORM.DATE')"
        />
        <Input
          id="booking-time"
          v-model="form.time"
          type="time"
          class="flex-1"
          :label="t('BOOKINGS.FORM.TIME')"
        />
      </div>
      <template v-for="(value, name) in form.details" :key="name">
        <div
          v-if="fieldsByName[name]?.type === FIELD_TYPES.choice"
          class="flex flex-col gap-1"
        >
          <span class="mb-0.5 text-heading-3 text-n-slate-12">
            {{ fieldLabel(name) }}
          </span>
          <Select
            v-model="form.details[name]"
            :options="choiceOptions(fieldsByName[name], value)"
            :aria-label="name"
          />
        </div>
        <Input
          v-else
          v-model="form.details[name]"
          :label="fieldLabel(name)"
          :inputmode="
            fieldsByName[name]?.type === FIELD_TYPES.number
              ? 'numeric'
              : undefined
          "
        />
      </template>
      <TextArea
        id="booking-notes"
        v-model="form.notes"
        :label="t('BOOKINGS.FORM.NOTES')"
        :max-length="NOTES_MAX_LENGTH"
      />
    </div>
  </Dialog>
</template>
