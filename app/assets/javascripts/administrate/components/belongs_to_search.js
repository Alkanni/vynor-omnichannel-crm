window.jQuery(() => {
  window.jQuery('select.js-belongs-to-search-field').each((_index, element) => {
    window.jQuery(element).selectize({
      valueField: 'id',
      labelField: 'dashboard_display_name',
      searchField: 'dashboard_display_name',
      create: false,
      load(query, callback) {
        if (!query.length) {
          callback();
          return;
        }

        window.jQuery.ajax({
          url: `${element.dataset.url}?search=${encodeURIComponent(query)}`,
          type: 'GET',
          error: () => callback(),
          success: response => callback(response.resources),
        });
      },
    });
  });
});
