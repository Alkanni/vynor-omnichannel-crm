# Backport of rails/rails@210ac22d (GHSA-8474-xrp6-wh69), which Rails 7.2 never received.
# When constant lookup raises LoadError, Rails 7.2 builds a Regexp from the requested name, and
# Action Cable passes every subscribe command's channel name here before any channel authenticates
# it, so a client could choose the pattern Ruby compiles. The method body is the Rails 8.0.5.2 one,
# kept verbatim so it is easy to compare and drop.
# TODO: Remove when upgrading to Rails 8.0.5.2 or later (#129), along with its .bundler-audit.yml entry.
module ActiveSupport
  module Inflector
    def safe_constantize(camel_cased_word) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      constantize(camel_cased_word)
    rescue NameError => e
      raise if e.name && !(camel_cased_word.to_s.split('::').include?(e.name.to_s) ||
        e.name.to_s == camel_cased_word.to_s)
    rescue LoadError => e
      message = e.respond_to?(:original_message) ? e.original_message : e.message
      constant_name = camel_cased_word.split('::').find { |part| !part.empty? } || camel_cased_word
      raise unless message.include?("Unable to autoload constant #{constant_name}")
    end
  end
end
