require 'rails_helper'

# Behind the proxy, REMOTE_ADDR is the proxy's private address and X-Forwarded-For the client's (see
# config/initializers/forwarded_header.rb).
RSpec.describe 'Client address behind the proxy' do
  let(:proxy_env) { { 'REMOTE_ADDR' => '172.18.0.5' } }

  it 'takes the X-Forwarded-For address when the client sends a Forwarded header with another one' do
    get '/api', headers: { 'X-Forwarded-For' => '203.0.113.7', 'Forwarded' => 'for=198.51.100.9' }, env: proxy_env

    expect(response).to have_http_status(:ok)
    expect(request.remote_ip).to eq('203.0.113.7')
    expect(Rack::Attack::Request.new(request.env).ip).to eq('203.0.113.7')
  end

  it 'does not let a Forwarded header from a private address claim a safelisted address' do
    get '/api', headers: { 'X-Forwarded-For' => '172.18.0.9', 'Forwarded' => 'for=127.0.0.1' }, env: proxy_env

    expect(request.remote_ip).to eq('172.18.0.9')
    expect(Rack::Attack::Request.new(request.env)).not_to be_allowed_ip
  end

  it 'takes the X-Forwarded-For address of a request without a Forwarded header' do
    get '/api', headers: { 'X-Forwarded-For' => '203.0.113.7' }, env: proxy_env

    expect(request.remote_ip).to eq('203.0.113.7')
    expect(Rack::Attack::Request.new(request.env).ip).to eq('203.0.113.7')
  end
end
