import bookings from '../bookings';
import ApiClient from '../ApiClient';

describe('#BookingsAPI', () => {
  it('creates correct instance', () => {
    expect(bookings).toBeInstanceOf(ApiClient);
    expect(bookings).toHaveProperty('list');
    expect(bookings).toHaveProperty('update');
    expect(bookings.url).toBe('/api/v1/bookings');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      Object.defineProperty(bookings, 'accountIdFromRoute', {
        get: () => '1',
        configurable: true,
      });
    });

    afterEach(() => {
      window.axios = originalAxios;
      delete bookings.accountIdFromRoute;
    });

    it('#list sends the filters as query parameters', () => {
      const params = {
        status: 'confirmed',
        from: '2026-11-20T00:00:00.000Z',
        page: 2,
      };

      bookings.list(params);

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/bookings',
        { params }
      );
    });

    it('#update sends the status of a booking', () => {
      bookings.update(7, { status: 'confirmed' });

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/bookings/7',
        { status: 'confirmed' }
      );
    });
  });
});
