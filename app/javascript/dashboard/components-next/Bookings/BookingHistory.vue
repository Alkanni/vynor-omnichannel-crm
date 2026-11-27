<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingsAPI from 'dashboard/api/bookings';
import { BOOKING_STATUS_LABELS } from './constants';
import { formatBookingTime } from './helpers';

const props = defineProps({
  bookingId: { type: Number, required: true },
});

// What a field without a value shows.
const EMPTY_VALUE = '-';
// The booking fields a history entry names (see Booking::HISTORY_FIELDS), besides details, the agent's own fields,
// which each go by their own name.
const FIELD_LABELS = Object.freeze({
  status: 'BOOKINGS.TABLE.STATUS',
  service: 'BOOKINGS.TABLE.SERVICE',
  customer_name: 'BOOKINGS.FORM.CUSTOMER_NAME',
  scheduled_at: 'BOOKINGS.TABLE.SCHEDULE',
  notes: 'BOOKINGS.FORM.NOTES',
});
const ACTION_LABELS = Object.freeze({
  create: 'BOOKINGS.HISTORY.CREATED',
  update: 'BOOKINGS.HISTORY.UPDATED',
});
const AI_AGENT_ACTOR = 'AiAgent';

const { t, locale } = useI18n();
const entries = ref([]);
const isLoading = ref(true);
const hasError = ref(false);

const formatValue = (field, value) => {
  if (!value) return EMPTY_VALUE;
  if (field === 'scheduled_at') return formatBookingTime(value, locale.value);
  if (field === 'status') return t(BOOKING_STATUS_LABELS[value]);
  return value;
};

// A user or AI agent deleted since keeps no name.
const actorName = actor => {
  if (!actor?.name) return t('BOOKINGS.HISTORY.UNKNOWN_ACTOR');
  if (actor.type === AI_AGENT_ACTOR) {
    return t('BOOKINGS.HISTORY.AI_AGENT_ACTOR', { name: actor.name });
  }
  return actor.name;
};

// Each changed field as a label with its value before and after; a detail only when its own value changed.
const fieldChanges = changes =>
  changes.flatMap(({ field, from, to }) => {
    if (field !== 'details') {
      return [
        {
          label: t(FIELD_LABELS[field]),
          from: formatValue(field, from),
          to: formatValue(field, to),
        },
      ];
    }
    const before = from || {};
    const after = to || {};
    return [...new Set([...Object.keys(before), ...Object.keys(after)])]
      .filter(name => before[name] !== after[name])
      .map(name => ({
        label: name,
        from: before[name] || EMPTY_VALUE,
        to: after[name] || EMPTY_VALUE,
      }));
  });

// A recorded booking lists its first values; a change, each value before and after.
const items = computed(() =>
  entries.value.map(entry => ({
    id: entry.id,
    summary: t(ACTION_LABELS[entry.action], {
      actor: actorName(entry.actor),
    }),
    time: formatBookingTime(entry.created_at, locale.value),
    createdAt: entry.created_at,
    lines: fieldChanges(entry.changes).map(change =>
      entry.action === 'create'
        ? t('BOOKINGS.FIELD_VALUE', { field: change.label, value: change.to })
        : t('BOOKINGS.HISTORY.FIELD_CHANGE', {
            field: change.label,
            from: change.from,
            to: change.to,
          })
    ),
    comment: entry.comment,
  }))
);

onMounted(async () => {
  try {
    const { data } = await BookingsAPI.history(props.bookingId);
    entries.value = data.payload;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <section class="flex flex-col gap-3">
    <h3 class="text-heading-3 text-n-slate-12">
      {{ t('BOOKINGS.HISTORY.TITLE') }}
    </h3>
    <p v-if="isLoading" class="text-body-main text-n-slate-11">
      {{ t('BOOKINGS.HISTORY.LOADING') }}
    </p>
    <p v-else-if="hasError" class="text-body-main text-n-ruby-11">
      {{ t('BOOKINGS.HISTORY.LOAD_ERROR') }}
    </p>
    <p v-else-if="!items.length" class="text-body-main text-n-slate-11">
      {{ t('BOOKINGS.HISTORY.EMPTY') }}
    </p>
    <ol v-else class="flex flex-col gap-4 list-none">
      <li
        v-for="item in items"
        :key="item.id"
        class="flex flex-col gap-1 border-s-2 border-n-strong ps-3"
      >
        <div
          class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1"
        >
          <span class="text-body-main text-n-slate-12">{{ item.summary }}</span>
          <time
            :datetime="item.createdAt"
            class="text-label-small text-n-slate-11"
          >
            {{ item.time }}
          </time>
        </div>
        <ul class="flex flex-col gap-0.5 list-none">
          <li
            v-for="(line, index) in item.lines"
            :key="index"
            class="break-words whitespace-pre-wrap text-body-main text-n-slate-11"
          >
            {{ line }}
          </li>
        </ul>
        <p
          v-if="item.comment"
          class="break-words whitespace-pre-wrap text-body-main text-n-slate-11"
        >
          {{ t('BOOKINGS.HISTORY.REASON', { reason: item.comment }) }}
        </p>
      </li>
    </ol>
  </section>
</template>
