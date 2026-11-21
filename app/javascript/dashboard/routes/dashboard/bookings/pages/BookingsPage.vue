<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import BookingsAPI from 'dashboard/api/bookings';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import BookingStatusMenu from 'dashboard/components-next/Bookings/BookingStatusMenu.vue';
import {
  BOOKING_STATUSES,
  BOOKING_STATUS_LABELS,
} from 'dashboard/components-next/Bookings/constants';
import {
  formatBookingTime,
  localDate,
  startOfLocalDay,
} from 'dashboard/components-next/Bookings/helpers';

const BOOKINGS_PER_PAGE = 25;
// The All tab sends no status.
const STATUS_FILTERS = ['', ...BOOKING_STATUSES];

const { t, locale } = useI18n();
const route = useRoute();
const { isCloudFeatureEnabled } = useAccount();

// The router does not check a route's feature flag, and the API refuses bookings without it.
const isBookingsEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.BOOKINGS)
);

const filters = reactive({
  status: '',
  from: localDate(new Date()),
  to: '',
  page: 1,
});
const bookings = ref([]);
const totalCount = ref(0);
const isLoading = ref(true);
const hasError = ref(false);

const tabs = computed(() =>
  STATUS_FILTERS.map(status => ({
    value: status,
    label: status
      ? t(BOOKING_STATUS_LABELS[status])
      : t('BOOKINGS.FILTERS.ALL'),
  }))
);
const activeTab = computed(() => STATUS_FILTERS.indexOf(filters.status));
const headers = computed(() => [
  t('BOOKINGS.TABLE.SCHEDULE'),
  t('BOOKINGS.TABLE.CUSTOMER'),
  t('BOOKINGS.TABLE.SERVICE'),
  t('BOOKINGS.TABLE.STATUS'),
  t('BOOKINGS.TABLE.CONVERSATION'),
]);

const fetchBookings = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await BookingsAPI.list({
      status: filters.status || undefined,
      from: filters.from ? startOfLocalDay(filters.from) : undefined,
      // The whole To day is included, so the range ends where the next day starts.
      to: filters.to ? startOfLocalDay(filters.to, 1) : undefined,
      page: filters.page,
    });
    bookings.value = data.payload;
    totalCount.value = data.meta.count;
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

const conversationRoute = booking => ({
  name: 'inbox_conversation',
  params: {
    accountId: route.params.accountId,
    conversation_id: booking.conversation.display_id,
  },
});

// A filter change starts again from the first page, whose change fetches.
watch(
  () => [filters.status, filters.from, filters.to],
  () => {
    if (filters.page === 1) fetchBookings();
    else filters.page = 1;
  }
);
watch(() => filters.page, fetchBookings);
// The account's features load after a reload, so the first fetch waits for them.
watch(
  isBookingsEnabled,
  enabled => {
    if (enabled) fetchBookings();
  },
  { immediate: true }
);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div class="flex flex-col w-full gap-6 px-6 py-10 mx-auto max-w-[71rem]">
      <header class="flex flex-col gap-2">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ t('BOOKINGS.HEADER') }}
        </h1>
        <p class="text-body-para text-n-slate-11">
          {{ t('BOOKINGS.DESCRIPTION') }}
        </p>
      </header>
      <p v-if="!isBookingsEnabled" class="text-body-main text-n-slate-11">
        {{ t('BOOKINGS.DISABLED') }}
      </p>
      <template v-else>
        <div
          class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between"
        >
          <div class="min-w-0 p-1 -m-1 overflow-x-auto no-scrollbar">
            <TabBar
              :tabs="tabs"
              :initial-active-tab="activeTab"
              @tab-changed="tab => (filters.status = tab.value)"
            />
          </div>
          <div class="flex flex-wrap gap-3">
            <Input
              id="bookings-from"
              v-model="filters.from"
              type="date"
              :label="t('BOOKINGS.FILTERS.FROM')"
            />
            <Input
              id="bookings-to"
              v-model="filters.to"
              type="date"
              :label="t('BOOKINGS.FILTERS.TO')"
            />
          </div>
        </div>

        <div class="w-full border rounded-xl border-n-weak bg-n-solid-1">
          <div
            v-if="isLoading"
            class="flex items-center justify-center py-20 text-n-slate-11"
          >
            <Spinner />
          </div>
          <p
            v-else-if="hasError"
            class="py-20 text-center text-body-main text-n-ruby-11"
          >
            {{ t('BOOKINGS.LOAD_ERROR') }}
          </p>
          <div
            v-else
            class="overflow-x-auto [&_th:first-child]:ps-5 [&_td:first-child]:ps-5 [&_th:last-child]:pe-5 [&_td:last-child]:pe-5"
          >
            <BaseTable
              :headers="headers"
              :items="bookings"
              :no-data-message="t('BOOKINGS.EMPTY')"
            >
              <template #row="{ items }">
                <BaseTableRow
                  v-for="booking in items"
                  :key="booking.id"
                  :item="booking"
                >
                  <template #default>
                    <BaseTableCell>
                      <span
                        class="tabular-nums whitespace-nowrap text-body-main text-n-slate-12"
                      >
                        {{ formatBookingTime(booking.scheduled_at, locale) }}
                      </span>
                    </BaseTableCell>
                    <BaseTableCell>
                      <div class="flex flex-col gap-0.5 py-1">
                        <span class="text-heading-3 text-n-slate-12">
                          {{ booking.customer_name }}
                        </span>
                        <span class="text-label-small text-n-slate-11">
                          {{ booking.contact.name }}
                        </span>
                        <span
                          class="tabular-nums text-label-small text-n-slate-11"
                        >
                          {{ booking.contact.phone_number || '-' }}
                        </span>
                      </div>
                    </BaseTableCell>
                    <BaseTableCell>
                      <div class="flex flex-col gap-0.5 py-1">
                        <span class="text-body-main text-n-slate-12">
                          {{ booking.service }}
                        </span>
                        <span
                          v-for="(value, field) in booking.details"
                          :key="field"
                          class="text-label-small text-n-slate-11"
                        >
                          {{
                            t('BOOKINGS.FIELD_VALUE', {
                              field,
                              value: value || '-',
                            })
                          }}
                        </span>
                        <span
                          v-if="booking.notes"
                          class="text-label-small text-n-slate-11"
                        >
                          {{ booking.notes }}
                        </span>
                        <span
                          v-if="booking.rescheduled_from_id"
                          class="text-label-small text-n-slate-11"
                        >
                          {{
                            t('BOOKINGS.RESCHEDULED_FROM', {
                              id: booking.rescheduled_from_id,
                            })
                          }}
                        </span>
                      </div>
                    </BaseTableCell>
                    <BaseTableCell>
                      <BookingStatusMenu
                        :booking="booking"
                        @updated="replaceBooking"
                      />
                    </BaseTableCell>
                    <BaseTableCell>
                      <RouterLink
                        :to="conversationRoute(booking)"
                        class="whitespace-nowrap text-body-main text-n-blue-11 hover:underline underline-offset-2"
                      >
                        {{
                          t('BOOKINGS.TABLE.OPEN_CONVERSATION', {
                            id: booking.conversation.display_id,
                          })
                        }}
                      </RouterLink>
                    </BaseTableCell>
                  </template>
                </BaseTableRow>
              </template>
            </BaseTable>
          </div>
        </div>

        <PaginationFooter
          v-if="totalCount > BOOKINGS_PER_PAGE"
          v-model:current-page="filters.page"
          :total-items="totalCount"
          :items-per-page="BOOKINGS_PER_PAGE"
        />
      </template>
    </div>
  </section>
</template>
