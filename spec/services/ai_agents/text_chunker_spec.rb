require 'rails_helper'

RSpec.describe AiAgents::TextChunker do
  it 'packs short paragraphs into one chunk' do
    expect(described_class.split("One.\n\nTwo.\n\n\n\nThree.")).to eq(["One.\n\nTwo.\n\nThree."])
  end

  it 'keeps chunks within the size limit without losing text' do
    text = "#{(['word'] * 1_000).join(' ')}\n\n#{'x' * 2_000}"

    chunks = described_class.split(text)

    expect(chunks.size).to be > 3
    expect(chunks.map(&:length).max).to be <= described_class::CHUNK_SIZE
    expect(chunks.join.delete(" \n")).to eq(text.delete(" \n"))
  end
end
