<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BookingsAPI from 'dashboard/api/bookings';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import {
  BOOKING_FINAL_STATUS,
  BOOKING_STATUSES,
  BOOKING_STATUS_CLASSES,
  BOOKING_STATUS_LABELS,
} from './constants';
import { slotTakenMessage } from './helpers';

const props = defineProps({
  booking: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();
const isSaving = ref(false);
const cancelDialogRef = ref(null);

const statusLabel = status => t(BOOKING_STATUS_LABELS[status]);
// The booking's own status and the ones it may change to (next_statuses), in the order staff move it through.
const options = computed(() =>
  BOOKING_STATUSES.filter(
    status =>
      status === props.booking.status ||
      props.booking.next_statuses.includes(status)
  ).map(status => ({ value: status, label: statusLabel(status) }))
);
const canChange = computed(() => props.booking.next_statuses.length > 0);

const saveStatus = async status => {
  isSaving.value = true;
  try {
    const { data } = await BookingsAPI.update(props.booking.id, { status });
    emit('updated', data);
    useAlert(t('BOOKINGS.UPDATE_SUCCESS'));
  } catch (error) {
    // A confirmed booking holding the slot is named, so staff know which one to move first.
    useAlert(slotTakenMessage(error) || t('BOOKINGS.UPDATE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

// A cancelled booking cannot change again and may message the customer, so staff confirm it first.
const changeStatus = status => {
  if (status === props.booking.status || isSaving.value) return;

  if (status === BOOKING_FINAL_STATUS) cancelDialogRef.value.open();
  else saveStatus(status);
};

const confirmCancel = () => {
  cancelDialogRef.value.close();
  saveStatus(BOOKING_FINAL_STATUS);
};
</script>

<template>
  <div class="flex items-center gap-2">
    <span
      class="inline-flex items-center h-6 px-2 text-xs font-medium rounded-md whitespace-nowrap"
      :class="BOOKING_STATUS_CLASSES[booking.status]"
    >
      {{ statusLabel(booking.status) }}
    </span>
    <SelectMenu
      v-if="canChange"
      :model-value="booking.status"
      :options="options"
      :label="t('BOOKINGS.TABLE.STATUS')"
      sub-menu-position="bottom"
      @update:model-value="changeStatus"
    />
    <Dialog
      ref="cancelDialogRef"
      type="alert"
      :title="t('BOOKINGS.CANCEL_DIALOG.TITLE')"
      :description="t('BOOKINGS.CANCEL_DIALOG.DESCRIPTION')"
      :cancel-button-label="t('BOOKINGS.CANCEL_DIALOG.KEEP')"
      :confirm-button-label="t('BOOKINGS.CANCEL_DIALOG.CONFIRM')"
      @confirm="confirmCancel"
    />
  </div>
</template>
