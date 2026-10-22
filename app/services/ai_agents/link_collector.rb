class AiAgents::LinkCollector
  MAX_LINKS = 300
  MAX_CHILD_SITEMAPS = 3
  FILE_EXTENSIONS = %w[
    .7z .apk .avi .css .csv .dmg .doc .docx .exe .gif .gz .ico .jpeg .jpg .js .json .mov .mp3 .mp4 .pdf .png .ppt .pptx
    .rar .rss .svg .tar .tgz .ttf .txt .wav .webm .webp .woff .woff2 .xls .xlsx .xml .zip
  ].freeze

  def initialize(url)
    @start_uri = parse_http_uri(url.to_s.strip)
    raise AiAgents::ExtractionError, I18n.t('ai_agents.knowledge.errors.invalid_url') if @start_uri.nil?

    @links = []
  end

  def perform
    page_html = AiAgents::WebPageFetcher.html(@start_uri.to_s)
    add_link(@start_uri.to_s)
    sitemap_links.each { |link| add_link(link) }
    page_links(page_html).each { |link| add_link(link) }
    @links
  end

  private

  def add_link(link)
    return if @links.size >= MAX_LINKS

    uri = parse_http_uri(link)
    return if uri.nil? || uri.host != @start_uri.host || file_link?(uri)

    normalized = normalize(uri)
    @links << normalized unless @links.include?(normalized)
  end

  def page_links(html)
    Nokogiri::HTML(html).css('a[href]').filter_map do |anchor|
      URI.join(@start_uri.to_s, anchor['href'].strip).to_s
    rescue URI::Error
      nil
    end
  end

  def sitemap_links
    document = Nokogiri::XML(AiAgents::WebPageFetcher.xml("#{@start_uri.scheme}://#{@start_uri.host}/sitemap.xml"))
    document.remove_namespaces!
    child_sitemaps = document.xpath('//sitemap/loc').map(&:text).first(MAX_CHILD_SITEMAPS)
    document.xpath('//url/loc').map(&:text) + child_sitemaps.flat_map { |url| child_sitemap_links(url) }
  rescue AiAgents::ExtractionError
    []
  end

  def child_sitemap_links(url)
    document = Nokogiri::XML(AiAgents::WebPageFetcher.xml(url))
    document.remove_namespaces!
    document.xpath('//url/loc').map(&:text)
  rescue AiAgents::ExtractionError
    []
  end

  def parse_http_uri(value)
    uri = URI.parse(value)
    uri if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::Error
    nil
  end

  def file_link?(uri)
    FILE_EXTENSIONS.include?(File.extname(uri.path.to_s).downcase)
  end

  def normalize(uri)
    normalized = uri.dup
    normalized.fragment = nil
    normalized.to_s.chomp('/')
  end
end
