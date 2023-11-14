# frozen_string_literal: true

class Gel::Command::Env < Gel::Command::Base
  define_options do |o|
    o.banner = <<~BANNER.chomp
      TODO

      Usage: gel env

      Options:
    BANNER
  end

  def call(_opts)
    raise "TODO"
  end
end
