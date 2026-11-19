<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingsAPI from 'dashboard/api/bookings';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BookingStatusMenu from './BookingStatusMenu.vue';
import { formatBookingTime, sortUpcomingFirst } from './helpers';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

const { t, locale } = useI18n();
const bookings = ref([]);
const isLoading = ref(true);
const hasError = ref(false);

const fetchBookings = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await BookingsAPI.list({ contact_id: props.contactId });
    bookings.value = sortUpcomingFirst(data.payload);
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const replaceBooking = updated => {
  bookings.value = bookings.value.map(booking =>
    booking.id === updated.id ? updated : booking
  );
};

watch(() => props.contactId, fetchBookings, { immediate: true });
</script>

<template>
  <div class="px-4 py-2 text-n-slate-12">
    <div v-if="isLoading" class="flex items-center justify-center p-4">
      <Spinner />
    </div>
    <p v-else-if="hasError" class="text-center text-body-main text-n-ruby-11">
      {{ t('BOOKINGS.LOAD_ERROR') }}
    </p>
    <p
      v-else-if="!bookings.length"
      class="text-center text-body-main text-n-slate-11"
    >
      {{ t('BOOKINGS.PANEL_EMPTY') }}
    </p>
    <ul v-else class="flex flex-col gap-3">
      <li
        v-for="booking in bookings"
        :key="booking.id"
        class="flex flex-col gap-1.5 pb-3 border-b border-n-weak last:border-b-0 last:pb-0"
      >
        <span class="text-heading-3 text-n-slate-12">
          {{ booking.service }}
        </span>
        <span class="text-label-small text-n-slate-11 tabular-nums">
          {{ formatBookingTime(booking.scheduled_at, locale) }}
        </span>
        <span
          v-for="(value, field) in booking.details"
          :key="field"
          class="text-label-small text-n-slate-11"
        >
          {{ t('BOOKINGS.FIELD_VALUE', { field, value: value || '-' }) }}
        </span>
        <span v-if="booking.notes" class="text-label-small text-n-slate-11">
          {{ booking.notes }}
        </span>
        <BookingStatusMenu :booking="booking" @updated="replaceBooking" />
      </li>
    </ul>
  </div>
</template>
