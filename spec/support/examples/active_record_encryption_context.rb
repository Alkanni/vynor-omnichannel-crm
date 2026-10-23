# frozen_string_literal: true

# Turns on Active Record encryption (test keys only) for examples whose records encrypt attributes unconditionally,
# since the regular spec run has no encryption keys. The boot configuration is restored afterwards.
RSpec.shared_context 'with active record encryption' do
  around do |example|
    keys = {
      primary_key: 'test-primary-key-0123456789abcdef', deterministic_key: 'test-deterministic-key-0123456789',
      key_derivation_salt: 'test-key-derivation-salt-0123456789'
    }
    env = keys.transform_keys { |key| "ACTIVE_RECORD_ENCRYPTION_#{key.to_s.upcase}" }
    with_modified_env(env) do
      ActiveRecord::Encryption.configure(**keys)
      example.run
    ensure
      ActiveRecord::Encryption.configure(**Rails.application.config.active_record.encryption.slice(*keys.keys))
    end
  end
end
