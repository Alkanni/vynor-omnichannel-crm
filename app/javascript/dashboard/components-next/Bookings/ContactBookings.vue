<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BookingsAPI from 'dashboard/api/bookings';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BookingFormDialog from './BookingFormDialog.vue';
import BookingStatusMenu from './BookingStatusMenu.vue';
import { formatBookingTime, sortUpcomingFirst } from './helpers';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
  // The display id of the open conversation, which a booking added here belongs to.
  conversationId: {
    type: [Number, String],
    default: null,
  },
  contactName: {
    type: String,
    default: '',
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

const formRef = ref(null);

const addBooking = async () => {
  try {
    const { data } = await BookingsAPI.fields(props.conversationId);
    formRef.value.open({
      customerName: props.contactName,
      fields: data.fields,
    });
  } catch {
    useAlert(t('BOOKINGS.FORM.FIELDS_ERROR'));
  }
};

// A new or edited booking, in its place by time.
const saveBooking = saved => {
  bookings.value = sortUpcomingFirst([
    ...bookings.value.filter(booking => booking.id !== saved.id),
    saved,
  ]);
};

watch(() => props.contactId, fetchBookings, { immediate: true });
</script>

<template>
  <div class="flex flex-col gap-3 px-4 py-2 text-n-slate-12">
    <Button
      v-if="conversationId"
      :label="t('BOOKINGS.FORM.ADD')"
      icon="i-lucide-plus"
      variant="faded"
      color="slate"
      size="sm"
      class="self-start"
      @click="addBooking"
    />
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
        <span
          v-if="booking.rescheduled_from_id"
          class="text-label-small text-n-slate-11"
        >
          {{
            t('BOOKINGS.RESCHEDULED_FROM', { id: booking.rescheduled_from_id })
          }}
        </span>
        <div class="flex items-center gap-2">
          <BookingStatusMenu :booking="booking" @updated="replaceBooking" />
          <Button
            v-if="booking.next_statuses.length"
            v-tooltip="t('BOOKINGS.FORM.EDIT')"
            :aria-label="t('BOOKINGS.FORM.EDIT')"
            icon="i-lucide-pencil"
            variant="ghost"
            color="slate"
            size="xs"
            @click="formRef.open({ current: booking })"
          />
        </div>
      </li>
    </ul>
    <BookingFormDialog
      ref="formRef"
      :conversation-id="conversationId"
      @saved="saveBooking"
    />
  </div>
</template>
