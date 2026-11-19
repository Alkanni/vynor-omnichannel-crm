<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BookingsAPI from 'dashboard/api/bookings';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import {
  BOOKING_STATUSES,
  BOOKING_STATUS_CLASSES,
  BOOKING_STATUS_LABELS,
} from './constants';

const props = defineProps({
  booking: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['updated']);

const { t } = useI18n();
const isSaving = ref(false);

const statusLabel = status => t(BOOKING_STATUS_LABELS[status]);
const options = computed(() =>
  BOOKING_STATUSES.map(status => ({
    value: status,
    label: statusLabel(status),
  }))
);

const changeStatus = async status => {
  if (status === props.booking.status || isSaving.value) return;

  isSaving.value = true;
  try {
    const { data } = await BookingsAPI.update(props.booking.id, { status });
    emit('updated', data);
    useAlert(t('BOOKINGS.UPDATE_SUCCESS'));
  } catch {
    useAlert(t('BOOKINGS.UPDATE_ERROR'));
  } finally {
    isSaving.value = false;
  }
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
      :model-value="booking.status"
      :options="options"
      :label="t('BOOKINGS.TABLE.STATUS')"
      sub-menu-position="bottom"
      @update:model-value="changeStatus"
    />
  </div>
</template>
