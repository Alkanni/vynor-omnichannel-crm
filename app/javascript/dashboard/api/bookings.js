/* global axios */

import ApiClient from './ApiClient';

class BookingsAPI extends ApiClient {
  constructor() {
    super('bookings', { accountScoped: true });
  }

  // status (one or several), from and to (ISO 8601 times, to left out), contact_id, and page.
  list(params) {
    return axios.get(this.url, { params });
  }
}

export default new BookingsAPI();
