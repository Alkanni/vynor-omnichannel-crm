window.jQuery(() => {
  window
    .jQuery(
      [
        '.field-unit--belongs-to select',
        '.field-unit--has-many select',
        '.field-unit--polymorphic select',
        '.field-unit--select select',
      ].join(', ')
    )
    .selectize({});
});
