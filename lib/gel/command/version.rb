# frozen_string_literal: true

class Gel::Command::Version < Gel::Command::Base
  define_options do |o|
    o.banner = <<~BANNER.chomp
      Prints the current version of Gel.

      Usage: gel version

      Options:
    BANNER
  end

  def call(_opts)
    puts Gel::VERSION
  end
end
