class AiAgents::WebsiteContentExtractor
  REMOVED_ELEMENTS = 'script, style, noscript, svg, img, picture, nav, header, footer, form, iframe, template'.freeze

  def initialize(url)
    @url = url
  end

  def perform
    document = Nokogiri::HTML(AiAgents::WebPageFetcher.html(@url))
    title = document.at_css('title')&.text.to_s.squish
    document.css(REMOVED_ELEMENTS).remove
    main_node = document.at_css('main') || document.at_css('body') || document
    content = ReverseMarkdown.convert(main_node.to_html, unknown_tags: :bypass, github_flavored: true)

    { title: title.presence, content: content.gsub(/\n{3,}/, "\n\n").strip }
  end
end
