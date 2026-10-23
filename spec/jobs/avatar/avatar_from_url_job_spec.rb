require 'rails_helper'

RSpec.describe Avatar::AvatarFromUrlJob do
  let(:valid_url) { 'https://example.com/avatar.png' }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
  end

  it 'enqueues the job' do
    contact = create(:contact)
    expect { described_class.perform_later(contact, 'https://example.com/avatar.png') }
      .to have_enqueued_job(described_class).on_queue('purgable')
  end

  context 'with rate-limited avatarable (Contact)' do
    let(:avatarable) { create(:contact) }

    it 'attaches and updates sync attributes' do
      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, valid_url)
      avatarable.reload
      expect(avatarable.avatar).to be_attached
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(valid_url))
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
    end

    it 'attaches webp avatars and updates sync attributes' do
      webp_url = 'https://example.com/avatar.webp'

      stub_request(:get, webp_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/webp' }
        )

      described_class.perform_now(avatarable, webp_url)
      avatarable.reload

      expect(avatarable.avatar).to be_attached
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(webp_url))
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
    end

    it 'attaches avatars with parameterized content type headers' do
      parameterized_url = 'https://example.com/avatar-parameterized.png'

      stub_request(:get, parameterized_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'IMAGE/PNG; charset=binary' }
        )

      described_class.perform_now(avatarable, parameterized_url)
      avatarable.reload

      expect(avatarable.avatar).to be_attached
      expect(avatarable.avatar.blob.content_type).to eq('image/png')
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(parameterized_url))
    end

    it 'attaches avatars from URLs with embedded basic auth credentials' do
      authenticated_url = 'https://user:pass@example.com/avatar-authenticated.png'

      stub_request(:get, 'https://example.com/avatar-authenticated.png')
        .with(headers: { 'Authorization' => 'Basic dXNlcjpwYXNz' })
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, authenticated_url)
      avatarable.reload

      expect(avatarable.avatar).to be_attached
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(authenticated_url))
    end

    it 'returns early when rate limited' do
      ts = 30.seconds.ago.iso8601
      avatarable.update(additional_attributes: { 'last_avatar_sync_at' => ts })

      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, valid_url)
      avatarable.reload
      expect(avatarable.avatar).not_to be_attached
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(Time.zone.parse(avatarable.additional_attributes['last_avatar_sync_at']))
        .to be > Time.zone.parse(ts)
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(valid_url))
      expect(WebMock).not_to have_requested(:get, valid_url)
    end

    it 'returns early when hash unchanged' do
      avatarable.update(additional_attributes: { 'avatar_url_hash' => Digest::SHA256.hexdigest(valid_url) })

      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, valid_url)
      expect(avatarable.avatar).not_to be_attached
      avatarable.reload
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(valid_url))
      expect(WebMock).not_to have_requested(:get, valid_url)
    end

    it 'updates sync attributes even when URL is invalid' do
      invalid_url = 'invalid_url'
      described_class.perform_now(avatarable, invalid_url)
      avatarable.reload
      expect(avatarable.avatar).not_to be_attached
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(invalid_url))
    end

    it 'updates sync attributes when file download is valid but content type is unsupported' do
      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: '<invalid>content</invalid>',
          headers: { 'Content-Type' => 'application/xml' }
        )

      described_class.perform_now(avatarable, valid_url)
      avatarable.reload

      expect(avatarable.avatar).not_to be_attached
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(valid_url))
    end

    it 'updates sync attributes when the avatar URL is blocked by SSRF protection' do
      blocked_url = 'http://127.0.0.1/avatar.png'

      expect do
        described_class.perform_now(avatarable, blocked_url)
      end.not_to raise_error

      avatarable.reload
      expect(avatarable.avatar).not_to be_attached
      expect(avatarable.additional_attributes['last_avatar_sync_at']).to be_present
      expect(avatarable.additional_attributes['avatar_url_hash']).to eq(Digest::SHA256.hexdigest(blocked_url))
    end
  end

  context 'with a Telegram file URL' do
    let(:telegram_url) { 'https://api.telegram.org/file/bot123456:SECRET-TOKEN/photos/file_0.jpg' }

    before do
      allow(Resolv).to receive(:getaddresses).with('api.telegram.org').and_return(['149.154.167.220'])
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end

    it 'filters the bot token from the not found log' do
      stub_request(:get, telegram_url).to_return(status: 404)

      described_class.perform_now(create(:contact), telegram_url)

      expect(Rails.logger).to have_received(:info)
        .with('AvatarFromUrlJob: avatar not found at https://api.telegram.org/file/bot[FILTERED]/photos/file_0.jpg')
    end

    it 'filters the bot token from the error log' do
      stub_request(:get, telegram_url).to_return(status: [500, 'Internal Server Error'])

      described_class.perform_now(create(:contact), telegram_url)

      expect(Rails.logger).to have_received(:error).with(
        'AvatarFromUrlJob error for https://api.telegram.org/file/bot[FILTERED]/photos/file_0.jpg: SafeFetch::HttpError - 500 Internal Server Error'
      )
    end

    it 'does not log its arguments' do
      expect(described_class.log_arguments).to be(false)
    end
  end

  context 'with regular avatarable' do
    let(:avatarable) { create(:agent_bot) }

    it 'downloads and attaches avatar' do
      stub_request(:get, valid_url)
        .to_return(
          status: 200,
          body: File.read(Rails.root.join('spec/assets/avatar.png')),
          headers: { 'Content-Type' => 'image/png' }
        )

      described_class.perform_now(avatarable, valid_url)
      expect(avatarable.avatar).to be_attached
    end
  end

  # ref: https://github.com/chatwoot/chatwoot/issues/10449
  it 'does not raise error when downloaded file has no filename (invalid content)' do
    contact = create(:contact)
    invalid_file = Tempfile.new('avatar-without-name')

    allow(SafeFetch).to receive(:fetch)
      .with(
        valid_url,
        max_bytes: Avatar::AvatarFromUrlJob::MAX_DOWNLOAD_SIZE,
        allowed_content_type_prefixes: [],
        allowed_content_types: Avatar::AvatarFromUrlJob::ALLOWED_CONTENT_TYPES
      ).and_yield(
        SafeFetch::Result.new(
          tempfile: invalid_file,
          filename: nil,
          content_type: 'image/png'
        )
      )

    expect { described_class.perform_now(contact, valid_url) }.not_to raise_error
    expect(contact.reload.avatar).not_to be_attached
  ensure
    invalid_file.close!
  end

  it 'skips sync attribute updates when URL is nil' do
    contact = create(:contact)

    expect { described_class.perform_now(contact, nil) }.not_to raise_error

    contact.reload
    expect(contact.additional_attributes['last_avatar_sync_at']).to be_nil
    expect(contact.additional_attributes['avatar_url_hash']).to be_nil
  end
end
