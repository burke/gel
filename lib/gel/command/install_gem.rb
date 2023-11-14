# frozen_string_literal: true

class Gel::Command::InstallGem < Gel::Command::Base
  define_options do |o|
    o.banner = <<~BANNER.chomp
      Install a gem into the current environment.

      Usage: gel install-gem <gem> [<version>]

      Options:
    BANNER
  end

  def call(opts)
    gem_name, gem_version = opts.arguments

    Gel::WorkPool.new(2) do |work_pool|
      catalog = Gel::Catalog.new("https://rubygems.org", work_pool: work_pool)

      Gel::Environment.install_gem([catalog], gem_name, gem_version, output: $stderr)
    end
  end
end
