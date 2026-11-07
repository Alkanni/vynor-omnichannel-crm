require 'rails_helper'

describe ActiveSupport::Inflector do
  describe '.safe_constantize' do
    let(:name_with_regexp_syntax) { 'ActiveSupport::Cache::MemCacheStore::(' }

    before { allow(described_class).to receive(:constantize).and_call_original }

    it 'raises the LoadError instead of compiling the constant name into a Regexp' do
      allow(described_class).to receive(:constantize).with(name_with_regexp_syntax)
                                                     .and_raise(LoadError, 'cannot load such file -- dalli')

      expect { name_with_regexp_syntax.safe_constantize }.to raise_error(LoadError, 'cannot load such file -- dalli')
      expect { described_class.safe_constantize(name_with_regexp_syntax) }.to raise_error(LoadError, 'cannot load such file -- dalli')
    end

    it 'returns nil when the requested constant cannot be autoloaded' do
      allow(described_class).to receive(:constantize).with('Foo::Bar')
                                                     .and_raise(LoadError, 'Unable to autoload constant Foo::Bar, expected foo/bar.rb to define it')

      expect('Foo::Bar'.safe_constantize).to be_nil
    end

    it 'resolves existing constants and returns nil for unknown ones' do
      expect('Conversation'.safe_constantize).to eq(Conversation)
      expect('NoSuchConstant::Inside'.safe_constantize).to be_nil
    end
  end
end
