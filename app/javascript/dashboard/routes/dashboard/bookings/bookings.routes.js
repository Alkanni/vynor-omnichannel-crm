import { frontendURL } from '../../../helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import BookingsPage from './pages/BookingsPage.vue';

// Agents see the bookings of their inboxes only (see BookingPolicy).
export const routes = [
  {
    path: frontendURL('accounts/:accountId/bookings'),
    name: 'bookings_index',
    component: BookingsPage,
    meta: {
      permissions: ['administrator', 'agent'],
      featureFlag: FEATURE_FLAGS.BOOKINGS,
    },
  },
];
