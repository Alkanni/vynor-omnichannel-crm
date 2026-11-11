require 'rails_helper'

RSpec.describe AiAgents::TextChunker do
  it 'packs short paragraphs into one chunk' do
    expect(described_class.split("One.\n\nTwo.\n\n\n\nThree.").map(&:text)).to eq(["One.\n\nTwo.\n\nThree."])
  end

  it 'keeps chunks within the size limit without losing text' do
    text = "#{(['word'] * 1_000).join(' ')}\n\n#{'x' * 2_000}"

    chunks = described_class.split(text).map(&:text)

    expect(chunks.size).to be > 3
    expect(chunks.map(&:length).max).to be <= described_class::CHUNK_SIZE
    expect(chunks.join.delete(" \n")).to eq(text.delete(" \n"))
  end

  it 'starts a chunk at each heading and opens it with the heading path' do
    text = "Pembuka.\n\n# Panduan\n\nUmum.\n\n## Cabang Dago\n\n### Kontak\n\nTelepon 1.\n\n### Parkir ###\n\n12 slot.\n\n## Cabang Kopo\n\nTutup."

    expect(described_class.split(text).map(&:text)).to eq(
      ['Pembuka.', "Panduan\n\nUmum.", "Panduan > Cabang Dago > Kontak\n\nTelepon 1.", "Panduan > Cabang Dago > Parkir\n\n12 slot.",
       "Panduan > Cabang Kopo\n\nTutup."]
    )
  end

  it 'numbers the sections between headings so that the chunks of one section share their number' do
    text = "Pembuka.\n\n# Panduan\n\n#{(['kata'] * 600).join(' ')}\n\n## Kontak\n\n### Telepon\n\nTelepon 1.\n\n# Jam buka 08.00"

    chunks = described_class.split(text)

    expect(chunks.map { |chunk| [chunk.section, chunk.text.lines.first.chomp] }).to eq(
      [[0, 'Pembuka.'], [1, 'Panduan'], [1, 'Panduan'], [1, 'Panduan'], [2, 'Panduan > Kontak > Telepon'], [3, 'Jam buka 08.00']]
    )
  end

  it 'keeps the heading path within the chunk size and repeats it on every chunk of a long section' do
    chunks = described_class.split("# Kebijakan\n\n#{(['kata'] * 1_000).join(' ')}").map(&:text)

    expect(chunks.size).to be > 1
    expect(chunks).to all(start_with("Kebijakan\n\nkata"))
    expect(chunks.map(&:length).max).to be <= described_class::CHUNK_SIZE
  end

  it 'keeps a heading with nothing under it as its own chunk' do
    expect(described_class.split("# Cabang\n\nIsi cabang.\n\n## Kopo\n\nIsi Kopo.\n\n## Kontak WA 0812-1111\n\n# Jam buka 08.00\n").map(&:text))
      .to eq(["Cabang\n\nIsi cabang.", "Cabang > Kopo\n\nIsi Kopo.", 'Cabang > Kontak WA 0812-1111', 'Jam buka 08.00'])
  end

  it 'keeps a document of only headings' do
    expect(described_class.split("# Jam buka 08.00-20.00\n\n# Alamat Jl. Merdeka 1").map(&:text))
      .to eq(['Jam buka 08.00-20.00', 'Alamat Jl. Merdeka 1'])
  end

  it 'adds no chunk for a heading that the path of the next, deeper heading carries' do
    expect(described_class.split("# Cabang\n\n## Kopo\n\n### Kontak\n\nTelepon 1.").map(&:text)).to eq(["Cabang > Kopo > Kontak\n\nTelepon 1."])
  end

  it 'shortens a very long heading path on every chunk and keeps its text in full once' do
    heading = (['kata'] * 500).join(' ')

    chunks = described_class.split("# #{heading}\n\nIsi.").map(&:text)

    expect(chunks.map(&:length).max).to be <= described_class::CHUNK_SIZE
    expect(chunks).to all(start_with(heading.truncate(described_class::MAX_HEADING_PATH)))
    expect(chunks.map { |chunk| chunk.split("\n\n", 2).last }.join(' ').delete(" \n")).to eq("#{heading}Isi.".delete(" \n"))
  end

  it 'keeps a very long parent heading that has nothing under it' do
    parent = (['induk'] * 100).join(' ')

    chunks = described_class.split("# #{parent}\n\n## Kontak\n\nTelepon 1.").map(&:text)

    expect(chunks.sole).to end_with("#{parent} > Kontak\n\nTelepon 1.")
  end

  it 'does not read a hashtag or a number sign as a heading' do
    expect(described_class.split("#promo hari ini\n\n#1 di Bandung").map(&:text)).to eq(["#promo hari ini\n\n#1 di Bandung"])
  end

  it 'splits a long table between rows and repeats its header' do
    rows = Array.new(100) { |index| "| GR-#{index} | Roti Sobek Coklat isi #{index} | Rp#{index}.000 |" }
    head = "| Kode | Produk | Harga |\n|---|---|---|"

    chunks = described_class.split("# Harga\n\n#{head}\n#{rows.join("\n")}").map(&:text)

    expect(chunks.size).to be > 1
    expect(chunks).to all(start_with("Harga\n\n#{head}\n| GR-"))
    expect(chunks.map(&:length).max).to be <= described_class::CHUNK_SIZE
    expect(chunks.flat_map { |chunk| chunk.split("\n").drop(4) }).to eq(rows)
  end

  it 'keeps a table that fits with the text around it' do
    text = "Daftar harga.\n\n| Produk | Harga |\n|---|---|\n| Roti | Rp10.000 |"

    expect(described_class.split(text).map(&:text)).to eq([text])
  end

  it 'cuts a table row longer than a chunk, keeping the header' do
    head = "| Produk | Catatan |\n|---|---|"
    row = "| Roti | #{(['kata'] * 500).join(' ')} |"

    chunks = described_class.split("#{head}\n#{row}\n#{row}").map(&:text)

    expect(chunks).to all(start_with("#{head}\n"))
    expect(chunks.map(&:length).max).to be <= described_class::CHUNK_SIZE
  end

  it 'cuts a table like plain text when its header leaves too little room for rows' do
    header = "| #{(['Kolom'] * 200).join(' | ')} |"
    row = "| #{(['isi'] * 200).join(' | ')} |"

    chunks = described_class.split("#{header}\n|---|\n#{row}").map(&:text)

    expect(chunks.size).to be > 1
    expect(chunks.map(&:length).max).to be <= described_class::CHUNK_SIZE
  end

  it 'reads text with Windows line ends' do
    expect(described_class.split("# Judul\r\n\r\nIsi.").map(&:text)).to eq(["Judul\n\nIsi."])
  end
end
