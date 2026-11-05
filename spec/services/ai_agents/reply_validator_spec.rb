require 'rails_helper'

RSpec.describe AiAgents::ReplyValidator do
  let(:hits) do
    ["Profil toko\n\nBuka setiap hari pukul 08.00-20.00 WIB. Ongkos kirim ke luar Bandung Rp20.000 per pesanan.",
     "Product: Roti Sobek Coklat\nPrice: 25000.00\nWeight: 400 grams\nStock: 12"].map.with_index(1) do |content, rank|
      AiAgents::KnowledgeRetriever::Hit.new(chunk: AiAgent::KnowledgeChunk.new(content: content), rank: rank, score: 0.1)
    end
  end
  let(:messages) { [{ role: :user, content: 'Roti Sobek Coklat berapa?' }] }
  let(:content) { { 'decision' => 'answer', 'sources' => [2] } }
  let(:replies) { ['Roti Sobek Coklat harganya Rp25.000.'] }
  let(:result) do
    described_class.new(content: content, replies: replies, hits: hits, messages: messages,
                        current_time: 'Current date and time: Tuesday, 3 November 2026 14:05 (Asia/Jakarta)').perform
  end

  it 'passes an answer whose numbers are in the chunks it cites' do
    expect(result).to have_attributes(decision: 'answer', sources: [2], blocked_reason: nil)
    expect(result).not_to be_knowledge_gap
  end

  it 'blocks a decision outside the list, without keeping it' do
    content['decision'] = 'out_of_scope'

    expect(result).to have_attributes(decision: nil, blocked_reason: 'invalid_decision')
    expect(result).to be_knowledge_gap
  end

  it 'blocks a reply without a decision, such as one the model wrote as text' do
    content.clear

    expect(result).to have_attributes(decision: nil, sources: [], blocked_reason: 'invalid_decision')
  end

  it 'leaves a knowledge gap decision to the knowledge gap message, whatever the reply says' do
    content.replace('decision' => 'knowledge_gap', 'sources' => [])
    replies.replace(['Kalau disimpan di kulkas tahan 7 hari.'])

    expect(result).to have_attributes(decision: 'knowledge_gap', blocked_reason: nil)
    expect(result).to be_knowledge_gap
  end

  it 'blocks an answer that cites no chunk' do
    content['sources'] = []

    expect(result).to have_attributes(sources: [], blocked_reason: 'missing_sources')
  end

  it 'blocks a citation of a chunk the search did not return, or of something that is not a rank' do
    content['sources'] = [2, 3]
    expect(result.blocked_reason).to eq('unknown_source')

    content['sources'] = ['2']
    expect(described_class.new(content: content, replies: replies, hits: hits, messages: messages, current_time: '').perform)
      .to have_attributes(sources: [], blocked_reason: 'unknown_source')
  end

  it 'passes a conversational reply without sources, and checks its numbers against the conversation' do
    content.replace('decision' => 'conversational', 'sources' => [])
    replies.replace(['Sama-sama, Kak!'])
    expect(result.blocked_reason).to be_nil

    replies.replace(['Pesanan Kakak sudah lunas Rp150.000.'])
    expect(described_class.new(content: content, replies: replies, hits: hits, messages: messages, current_time: '').perform.blocked_reason)
      .to eq('unsupported_number')
  end

  describe 'numbers' do
    it 'blocks an amount that neither the cited chunks nor the conversation has' do
      replies.replace(['Harganya Rp30.000.'])

      expect(result.blocked_reason).to eq('unsupported_number')
    end

    it 'only counts the chunks the reply cites' do
      replies.replace(['Ongkir ke luar Bandung Rp20.000.'])

      expect(result.blocked_reason).to eq('unsupported_number')
    end

    ['Rp25.000', 'Rp 25.000,00', '25000', '25 ribu', '25rb', '25K'].each do |amount|
      it "reads #{amount} as the price 25000.00 of the chunk" do
        replies.replace(["Harganya #{amount} per pcs."])

        expect(result.blocked_reason).to be_nil
      end
    end

    it 'passes a price times the quantity the customer asked for' do
      messages.replace([{ role: :user, content: 'Ada Roti Sobek Coklat?' }, { role: :assistant, content: 'Ada, harganya Rp25.000.' },
                        { role: :user, content: 'Kalau beli 4, totalnya berapa?' }])
      replies.replace(['Untuk 4 Roti Sobek Coklat totalnya Rp100.000.'])

      expect(result.blocked_reason).to be_nil
    end

    it 'blocks a total that is not a price times a number the customer wrote' do
      messages.replace([{ role: :user, content: 'Kalau beli 4, totalnya berapa?' }])
      replies.replace(['Totalnya Rp125.000.'])

      expect(result.blocked_reason).to eq('unsupported_number')
    end

    it 'passes numbers the conversation already has, from the customer or an earlier reply' do
      messages.replace([{ role: :user, content: 'Saya belanja Rp80.000' }, { role: :assistant, content: 'Pesanan Kakak 3 pcs.' },
                        { role: :user, content: 'Jadi berapa?' }])
      replies.replace(['Belanja Rp80.000 untuk 3 pcs, harga Rp25.000 per pcs.'])

      expect(result.blocked_reason).to be_nil
    end

    it 'passes times written another way and the current time of the prompt, but not another time' do
      content['sources'] = [1]
      replies.replace(['Sekarang pukul 14:05, toko buka 08.00 sampai 20.00 WIB.'])
      expect(result.blocked_reason).to be_nil

      replies.replace(['Hari Minggu toko buka sampai 21.00.'])
      expect(described_class.new(content: content, replies: replies, hits: hits, messages: messages, current_time: '').perform.blocked_reason)
        .to eq('unsupported_number')
    end

    it 'ignores the numbers of a list' do
      replies.replace(["Pilihan kami:\n1. Roti Sobek Coklat Rp25.000\n2) Lainnya menyusul"])

      expect(result.blocked_reason).to be_nil
    end
  end

  describe 'web results' do
    let(:web_results) do
      [AiAgents::WebSearch::Item.new(rank: 3, title: 'Aki soak', url: 'https://otomotif.example/aki-soak', published_at: nil,
                                     highlights: ['Aki biasanya soak setelah 2 tahun pemakaian.']),
       AiAgents::WebSearch::Item.new(rank: 4, title: 'Aki', url: 'https://id.wikipedia.org/wiki/Aki_(otomotif)', published_at: nil,
                                     highlights: ['Aki menyimpan energi listrik.'])]
    end
    let(:content) { { 'decision' => 'answer', 'sources' => [3] } }
    let(:replies) { ['Menurut info di internet, aki biasanya soak setelah 2 tahun: https://otomotif.example/aki-soak'] }
    let(:result) do
      described_class.new(content: content, replies: replies, hits: hits, web_results: web_results, messages: messages, current_time: '').perform
    end

    it 'passes an answer that cites only a web result, with a number of that result and its link' do
      expect(result).to have_attributes(decision: 'answer', sources: [3], blocked_reason: nil)
    end

    it 'blocks a number that the web results it cites do not have' do
      replies.replace(['Aki biasanya soak setelah 3 tahun: https://otomotif.example/aki-soak'])

      expect(result.blocked_reason).to eq('unsupported_number')
    end

    it 'blocks a citation of a rank that neither the knowledge nor the web results had' do
      content['sources'] = [3, 5]

      expect(result.blocked_reason).to eq('unknown_source')
    end

    it 'leaves the links of the web results it cites to the reply generator' do
      content['sources'] = [3, 4]
      replies.replace(['Aki biasanya soak setelah 2 tahun dan menyimpan energi listrik.'])

      expect(result.blocked_reason).to be_nil
    end

    it 'blocks a link that is not one of the web results, the knowledge, or the conversation, also one that extends a known link' do
      replies.replace(['Aki soak setelah 2 tahun: https://otomotif.example/aki-soak, lihat juga https://palsu.example/aki'])
      expect(result.blocked_reason).to eq('unknown_url')

      replies.replace(['Aki soak setelah 2 tahun: https://otomotif.example/aki-soak-murah'])
      expect(described_class.new(content: content, replies: replies, hits: hits, web_results: web_results, messages: messages,
                                 current_time: '').perform.blocked_reason).to eq('unknown_url')
    end

    it 'passes the link of a web result it does not cite, and links from the knowledge or the conversation' do
      hits.first.chunk.content += "\nKatalog: https://toko.example/katalog"
      messages.replace([{ role: :user, content: 'Ini fotonya www.foto.example/aki-saya.jpg, kenapa ya?' }])
      replies.replace(["Aki soak setelah 2 tahun: https://otomotif.example/aki-soak\nBaca juga https://id.wikipedia.org/wiki/Aki_(otomotif), " \
                       'katalog https://toko.example/katalog, dan foto www.foto.example/aki-saya.jpg.'])

      expect(result.blocked_reason).to be_nil
    end

    ['https://www.otomotif.example/aki-soak/', '(https://otomotif.example/aki-soak).', '*https://otomotif.example/aki-soak*',
     'HTTPS://Otomotif.example/aki-soak', 'otomotif.example/aki-soak'].each do |link|
      it "reads #{link} as the link of the web result" do
        replies.replace(["Aki biasanya soak setelah 2 tahun #{link}"])

        expect(result.blocked_reason).to be_nil
      end
    end

    it 'blocks a domain without a scheme or the domain of an e-mail address that is not known' do
      replies.replace(['Aki soak setelah 2 tahun: https://otomotif.example/aki-soak. Promo ganti aki di promo-palsu.example'])
      expect(result.blocked_reason).to eq('unknown_url')

      replies.replace(['Aki soak setelah 2 tahun: https://otomotif.example/aki-soak. Tanya cs@palsu.example'])
      expect(described_class.new(content: content, replies: replies, hits: hits, web_results: web_results, messages: messages,
                                 current_time: '').perform.blocked_reason).to eq('unknown_url')
    end

    it 'passes the name of the site of a web result' do
      replies.replace(['Menurut Otomotif.example dan Wikipedia.org, aki soak setelah 2 tahun: https://otomotif.example/aki-soak'])

      expect(result.blocked_reason).to be_nil
    end

    it 'does not let a web result back a phone number, which only the knowledge or the conversation can' do
      web_results[0] = web_results[0].with(highlights: ['Aki soak setelah 2 tahun. Derek 24 jam: 0812-3456-7890.'])
      replies.replace(['Derek 24 jam di 0812-3456-7890, aki soak setelah 2 tahun: https://otomotif.example/aki-soak'])
      expect(result.blocked_reason).to eq('unsupported_number')

      hits.first.chunk.content += "\nDerek bengkel: 0812-3456-7890"
      content['sources'] = [1, 3]
      expect(described_class.new(content: content, replies: replies, hits: hits, web_results: web_results, messages: messages,
                                 current_time: '').perform.blocked_reason).to be_nil
    end

    it 'does not let a web result back a long number from parts it holds apart' do
      web_results[0] = web_results[0].with(highlights: ['Aki soak setelah 2 tahun. Kode 0812, seri 3456, dan nomor 7890.'])
      replies.replace(['Hubungi 0812-3456-7890, aki soak setelah 2 tahun: https://otomotif.example/aki-soak'])

      expect(result.blocked_reason).to eq('unsupported_number')
    end

    it 'reads a range of years as two numbers of the web result, not as a long number' do
      web_results[0] = web_results[0].with(highlights: ['Recall Xpander | 139,111 unit | produksi 2017 - 2019. Aki soak setelah 2 tahun.'])
      replies.replace(['Recall untuk Xpander produksi 2017-2019, aki soak setelah 2 tahun: https://otomotif.example/aki-soak'])

      expect(result.blocked_reason).to be_nil
    end

    it 'passes the published date of a web result it cites' do
      web_results[0] = web_results[0].with(published_at: Date.new(2022, 5, 10))
      replies.replace(['Artikel 10 Mei 2022 menyebut aki soak setelah 2 tahun: https://otomotif.example/aki-soak'])

      expect(result.blocked_reason).to be_nil
    end

    it 'does not read the digits of a link as numbers' do
      web_results[0] = web_results[0].with(url: 'https://otomotif.example/read/2025/09/16/112200115/aki-soak')
      replies.replace(['Aki biasanya soak setelah 2 tahun: https://otomotif.example/read/2025/09/16/112200115/aki-soak'])

      expect(result.blocked_reason).to be_nil
    end

    it 'keeps the parentheses of a link that has them' do
      content['sources'] = [4]
      replies.replace(['Aki menyimpan energi listrik (lihat https://id.wikipedia.org/wiki/Aki_(otomotif)).'])

      expect(result.blocked_reason).to be_nil
    end

    it 'checks the links of a reply without web results too' do
      content.replace('decision' => 'conversational', 'sources' => [])
      replies.replace(['Silakan cek https://palsu.example/promo'])

      expect(described_class.new(content: content, replies: replies, hits: hits, web_results: [], messages: messages, current_time: '').perform)
        .to have_attributes(blocked_reason: 'unknown_url')
    end

    it 'checks no link for an agent without web search' do
      content.replace('decision' => 'conversational', 'sources' => [])
      replies.replace(['Silakan cek https://palsu.example/promo'])

      expect(described_class.new(content: content, replies: replies, hits: hits, messages: messages, current_time: '').perform)
        .to have_attributes(blocked_reason: nil)
    end
  end
end
