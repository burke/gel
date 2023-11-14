# frozen_string_literal: true

class Gel::Command::Install < Gel::Command::Base
  define_options do |o|
    o.banner = <<~BANNER.chomp
      Install the gems from the Gemfile.

      Usage: gel install

      Options:
    BANNER
  end

  def call(_opts)
    Gel::Environment.activate(install: true, output: $stderr)
  end
end
