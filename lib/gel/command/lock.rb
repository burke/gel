# frozen_string_literal: true

class Gel::Command::Lock < Gel::Command::Base
  define_options do |o|
    o.banner = <<~BANNER.chomp
      TODO

      Usage: gel lock [<lockfile>] [<override>...]

      Mode selection options:
    BANNER
    o.bool "--hold", "Don't bump any versions (default)"
    o.bool "--patch", "Bump only patch versions"
    o.bool "--minor", "Bump patch and minor versions"
    o.bool "--major", "Bump patch, minor, and major versions"
    o.separator("\nOther options:")
    o.bool "--strict", "Use strict version constraints"
    o.string "--lockfile", "Specify a lockfile to use"
  end

  def call(opts)
    env_options = {}

    mode = :hold
    mode = :patch if opts[:patch]
    mode = :minor if opts[:minor]
    mode = :major if opts[:major]

    env_options[:lockfile] = opts[:lockfile] || opts.arguments.shift

    overrides = {}

    opts.arguments.each do |arg|
      case arg
      when /\A((?!-)[A-Za-z0-9_-]+)(?:(?:[\ :\/]|(?=[<>~=]))([<>~=,\ 0-9A-Za-z.-]+))?\z/x
        overrides[$1] = Gel::Support::GemRequirement.new($2 ? $2.split(/\s+(?=[0-9])|\s*,\s*/) : [])
      else
        raise "invalid override arugment"
      end
    end

    env_options[:preference_strategy] = lambda do |gem_set|
      Gel::PubGrub::PreferenceStrategy.new(gem_set, overrides, bump: mode, strict: opts[:strict])
    end

    Gel::Environment.write_lock(output: $stderr, **env_options)
  end
end
