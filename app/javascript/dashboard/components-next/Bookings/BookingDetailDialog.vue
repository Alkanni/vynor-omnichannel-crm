<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { BOOKING_STATUS_CLASSES, BOOKING_STATUS_LABELS } from './constants';
import { bookingConversationRoute, formatBookingTime } from './helpers';

// What a field without a value shows.
const EMPTY_VALUE = '-';

const { t, locale } = useI18n();
const route = useRoute();
const dialogRef = ref(null);
const booking = ref(null);

// The booking's fields in reading order, the agent's own fields (details) after the customer's.
const fields = computed(() => {
  const current = booking.value;
  if (!current) return [];

  return [
    [
      t('BOOKINGS.TABLE.SCHEDULE'),
      formatBookingTime(current.scheduled_at, locale.value),
    ],
    [t('BOOKINGS.TABLE.SERVICE'), current.service],
    [t('BOOKINGS.FORM.CUSTOMER_NAME'), current.customer_name],
    [t('BOOKINGS.DETAIL.CONTACT'), current.contact.name],
    [t('BOOKINGS.DETAIL.PHONE_NUMBER'), current.contact.phone_number],
    ...Object.entries(current.details),
    [t('BOOKINGS.DETAIL.AI_AGENT'), current.ai_agent?.name],
    [
      t('BOOKINGS.DETAIL.RECORDED_AT'),
      formatBookingTime(current.created_at, locale.value),
    ],
  ].map(([label, value]) => ({ label, value: value || EMPTY_VALUE }));
});

// The booking as the list holds it, so a changed booking shows its latest values the next time.
const open = current => {
  booking.value = current;
  dialogRef.value.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="booking ? t('BOOKINGS.DETAIL.TITLE', { id: booking.id }) : ''"
    :cancel-button-label="t('GENERAL.CLOSE')"
    :show-confirm-button="false"
    overflow-y-auto
  >
    <div v-if="booking" class="flex flex-col gap-5">
      <div class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center h-6 px-2 text-xs font-medium rounded-md whitespace-nowrap"
          :class="BOOKING_STATUS_CLASSES[booking.status]"
        >
          {{ t(BOOKING_STATUS_LABELS[booking.status]) }}
        </span>
        <span
          v-if="booking.rescheduled_from_id"
          class="text-label-small text-n-slate-11"
        >
          {{
            t('BOOKINGS.RESCHEDULED_FROM', { id: booking.rescheduled_from_id })
          }}
        </span>
      </div>
      <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div
          v-for="(field, index) in fields"
          :key="index"
          class="flex flex-col min-w-0 gap-1"
        >
          <dt class="text-label-small text-n-slate-11">{{ field.label }}</dt>
          <dd class="break-words text-body-main text-n-slate-12">
            {{ field.value }}
          </dd>
        </div>
        <div class="flex flex-col min-w-0 gap-1 sm:col-span-2">
          <dt class="text-label-small text-n-slate-11">
            {{ t('BOOKINGS.FORM.NOTES') }}
          </dt>
          <dd
            class="break-words whitespace-pre-wrap text-body-main text-n-slate-12"
          >
            {{ booking.notes || EMPTY_VALUE }}
          </dd>
        </div>
      </dl>
      <RouterLink
        :to="bookingConversationRoute(route.params.accountId, booking)"
        class="self-start text-body-main text-n-blue-11 hover:underline underline-offset-2"
      >
        {{
          t('BOOKINGS.TABLE.OPEN_CONVERSATION', {
            id: booking.conversation.display_id,
          })
        }}
      </RouterLink>
    </div>
  </Dialog>
</template>
