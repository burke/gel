# frozen_string_literal: true

class Gel::Command::Base
  extend Gel::Autoload

  def self.define_options(**config, &block)
    define_singleton_method(:options) do
      opts = Gel::Vendor::Slop::Options.new(**config, &block)
      unless opts.options.detect { |o| o.flags.include?('--help') }
        opts.bool '-h', '--help', 'Print this help message'
      end
      opts
    end
  end

  def self.options
    Gel::Vendor::Slop::Options.new do |o|
      o.bool '-h', '--help', 'Print help'
    end
  end

  def parse_options(command_line)
    opts = self.class.options.parse(command_line)
    if opts[:help]
      Gel::CLI.print_command_help(self.class)
      exit 0
    end
    opts
  end

  def run(argv)
    opts = parse_options(argv)
    call(opts)
  end

  # If set to true, an error raised from #run will pass straight up to
  # ruby instead of being treated as an internal Gel error
  attr_accessor :reraise
end
