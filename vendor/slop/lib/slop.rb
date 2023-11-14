# frozen-string-literal: true

require_relative 'slop/option'
require_relative 'slop/options'
require_relative 'slop/parser'
require_relative 'slop/result'
require_relative 'slop/types'
require_relative 'slop/error'

module Gel::Vendor::Slop
  VERSION = '4.10.1'

  # Parse an array of options (defaults to ARGV). Accepts an
  # optional hash of configuration options and block.
  #
  # Example:
  #
  #   opts = Gel::Vendor::Slop.parse(["-host", "localhost"]) do |o|
  #     o.string '-host', 'a hostname', default: '0.0.0.0'
  #   end
  #   opts.to_hash #=> { host: 'localhost' }
  #
  # Returns a Gel::Vendor::Slop::Result.
  def self.parse(items = ARGV, **config, &block)
    Options.new(**config, &block).parse(items)
  end

  # Example:
  #
  #   Gel::Vendor::Slop.option_defined?(:string) #=> true
  #   Gel::Vendor::Slop.option_defined?(:omg)    #=> false
  #
  # Returns true if an option is defined.
  def self.option_defined?(name)
    const_defined?(string_to_option(name.to_s))
  rescue NameError
    # If a NameError is raised, it wasn't a valid constant name,
    # and thus couldn't have been defined.
    false
  end

  # Example:
  #
  #   Gel::Vendor::Slop.string_to_option("string")     #=> "StringOption"
  #   Gel::Vendor::Slop.string_to_option("some_thing") #=> "SomeThingOption"
  #
  # Returns a camel-cased class looking string with Option suffix.
  def self.string_to_option(s)
    s.gsub(/(?:^|_)([a-z])/) { $1.capitalize } + "Option"
  end

  # Example:
  #
  #   Gel::Vendor::Slop.string_to_option_class("string") #=> Gel::Vendor::Slop::StringOption
  #   Gel::Vendor::Slop.string_to_option_class("foo")    #=> uninitialized constant FooOption
  #
  # Returns the full qualified option class. Uses `#string_to_option`.
  def self.string_to_option_class(s)
    const_get(string_to_option(s))
  end
end
