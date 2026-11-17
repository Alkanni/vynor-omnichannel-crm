window.jQuery(() => {
  const KEYS_THAT_OPEN_ROW = [' ', 'Enter'];

  const visitDataUrl = event => {
    if (event.type === 'keydown' && !KEYS_THAT_OPEN_ROW.includes(event.key)) {
      return;
    }
    if (event.target.href) return;

    const dataUrl = window.jQuery(event.target).closest('tr').data('url');
    const hasSelection = window.getSelection().toString().length > 0;
    if (dataUrl && !hasSelection) {
      window.location = `${window.location.origin}${dataUrl}`;
    }
  };

  window.jQuery('table').on('click keydown', '.js-table-row', visitDataUrl);
});
