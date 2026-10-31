require 'rails_helper'

RSpec.describe AiAgents::DocxMarkdown do
  let(:namespace) { 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"' }
  let(:header) { '<w:tr><w:tc><w:p><w:r><w:t>Kode</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Harga</w:t></w:r></w:p></w:tc></w:tr>' }

  it 'reads a table row inside a content control' do
    row = '<w:tr><w:tc><w:p><w:r><w:t>GR-1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Rp1.000</w:t></w:r></w:p></w:tc></w:tr>'
    table = "<w:tbl>#{header}<w:sdt><w:sdtContent>#{row}</w:sdtContent></w:sdt></w:tbl>"
    document = Nokogiri::XML("<w:document #{namespace}><w:body>#{table}</w:body></w:document>")

    expect(described_class.new(document, nil).text).to eq("| Kode | Harga |\n| --- | --- |\n| GR-1 | Rp1.000 |")
  end

  it 'reads a table cell inside a content control' do
    price = '<w:tc><w:p><w:r><w:t>Rp2.000</w:t></w:r></w:p></w:tc>'
    row = "<w:tr><w:tc><w:p><w:r><w:t>GR-2</w:t></w:r></w:p></w:tc><w:sdt><w:sdtContent>#{price}</w:sdtContent></w:sdt></w:tr>"
    document = Nokogiri::XML("<w:document #{namespace}><w:body><w:tbl>#{header}#{row}</w:tbl></w:body></w:document>")

    expect(described_class.new(document, nil).text).to eq("| Kode | Harga |\n| --- | --- |\n| GR-2 | Rp2.000 |")
  end

  it 'keeps a nested table inside its cell, once' do
    nested = '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Kecil</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Besar</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
    row = "<w:tr><w:tc>#{nested}</w:tc><w:tc><w:p><w:r><w:t>Rp3.000</w:t></w:r></w:p></w:tc></w:tr>"
    document = Nokogiri::XML("<w:document #{namespace}><w:body><w:tbl>#{header}#{row}</w:tbl></w:body></w:document>")

    expect(described_class.new(document, nil).text).to eq("| Kode | Harga |\n| --- | --- |\n| Kecil Besar | Rp3.000 |")
  end
end
