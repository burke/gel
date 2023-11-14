# frozen_string_literal: true

class Gel::Command::Config < Gel::Command::Base
  define_options do |o|
    o.banner = <<~BANNER.chomp
      TODO

      Usage: gel config

      Options:
    BANNER
  end

  def call(opts)
    args = opts.arguments
    if args.size == 1
      puts Gel::Environment.config[args.first]
    else
      Gel::Environment.config[args.shift] = args.join(" ")
    end
  end
end
