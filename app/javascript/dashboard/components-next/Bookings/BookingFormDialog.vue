<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BookingsAPI from 'dashboard/api/bookings';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
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

const { t } = useI18n();
const dialogRef = ref(null);
const booking = ref(null);
const isSaving = ref(false);
// Why the last save was refused: the slot a confirmed booking holds, shown in the dialog so staff pick another one.
const slotTaken = ref('');
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

// A new booking starts with the customer's name and the agent's fields; an existing one with its own values, in the
// viewer's time zone.
const open = ({ current = null, customerName = '', fields = [] } = {}) => {
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
      : Object.fromEntries(fields.map(field => [field, ''])),
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
      <Input
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
      <Input
        v-for="(value, field) in form.details"
        :key="field"
        v-model="form.details[field]"
        :label="field"
      />
      <TextArea
        id="booking-notes"
        v-model="form.notes"
        :label="t('BOOKINGS.FORM.NOTES')"
        :max-length="NOTES_MAX_LENGTH"
      />
    </div>
  </Dialog>
</template>
