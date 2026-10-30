// Test time for the judge (B-12 asks whether the shop is open now), evaluated when each case runs.
export default function now() {
  return {
    output: new Date().toLocaleString('id-ID', {
      timeZone: 'Asia/Jakarta',
      dateStyle: 'full',
      timeStyle: 'short',
    }),
  };
}
