// The promotion assertions of promptfooconfig.promo.yaml (issue #215), over the `promotion` metadata of provider.mjs (the
// one promotion of the prompt, with its rank and whether it was offered or in the knowledge) and the metadata of each
// case in tests/p-promo.yaml. A reply mentions a promotion when it cites its rank, which a strict reply must do for every
// fact it states. `promotion` of a case is the title of the promotion the reply must mention, 'any' for any active
// one, or null when it must mention none, by citation or in its words; a case without it is not checked for that.
// Every reply is checked for one promotion at most in its prompt and for no promotion that is not active today.
const PROMOTION_WORDS = /\b(promo|promosi|diskon|potongan harga)\b/i;
// The fixture promotions that are scheduled or archived on every run day (fixtures/bengkel-promo.json), and what a reply
// would state about them.
const INACTIVE_TITLES = ['Promo Akhir Tahun', 'Promo Cuci Mobil'];
const INACTIVE_FACTS = /20\s?%|cuci mobil gratis|gratis cuci/i;

const result = (pass, reason) => ({ pass, score: pass ? 1 : 0, reason });

// The promotion of the prompt when the reply cites it, else null.
export function mentionedPromotion({ promotion, citedRanks }) {
  return promotion && (citedRanks || []).includes(promotion.rank)
    ? promotion
    : null;
}

export function mentionsAsExpected(output, { metadata, test }) {
  const expected = test.metadata.promotion;
  if (expected === undefined) return result(true, 'not checked');

  const promotion = mentionedPromotion(metadata);
  const described = promotion
    ? `mentions ${promotion.title} (${promotion.placement})`
    : 'mentions no promotion';
  if (expected === null) {
    const words = PROMOTION_WORDS.test(output);
    return result(
      !promotion && !words,
      words && !promotion ? 'writes about a promotion' : described
    );
  }
  return result(
    promotion != null && (expected === 'any' || promotion.title === expected),
    described
  );
}

export function onePromotionAtMost(_output, { metadata }) {
  const promotions = (metadata.retrieved || []).filter(
    chunk => chunk.source.type === 'promotion'
  );
  return result(
    promotions.length <= 1,
    `${promotions.length} promotion(s) in the prompt`
  );
}

// A reply may repeat what the customer wrote ("belum ada promo cuci mobil gratis"), so its words only count when the
// conversation does not have them.
export function noInactivePromotion(output, { metadata, test }) {
  const inactive = (metadata.retrieved || []).filter(
    chunk =>
      chunk.source.type === 'promotion' &&
      INACTIVE_TITLES.includes(chunk.source.title)
  );
  if (inactive.length)
    return result(
      false,
      `prompt had ${inactive.map(chunk => chunk.source.title).join(', ')}`
    );

  const stated =
    INACTIVE_FACTS.test(output) && !INACTIVE_FACTS.test(test.vars.conversation);
  return result(
    !stated,
    stated ? 'states a promotion that is not active' : 'no inactive promotion'
  );
}
