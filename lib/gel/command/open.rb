# frozen_string_literal: true

class Gel::Command::Open < Gel::Command::Base
  define_options do |o|
    o.banner = <<~BANNER.chomp
      TODO

      Usage: gel open <gem> [options]

      Options:
    BANNER
    o.string '-v', '--version', 'Select a version of the gem'
  end

  def call(opts)
    command_line = opts.arguments.dup
    require "shellwords"

    raise "Please provide the name of a gem to open in your editor" if command_line.empty?

    gem_name = command_line.shift

    raise "Too many arguments, only one gem name is supported" if command_line.length > 0

    editor = ENV.fetch("GEL_EDITOR", ENV["EDITOR"])
    raise "An editor must be set using either $GEL_EDITOR or $EDITOR" unless editor

    Gel::Environment.activate(output: $stderr, error: false)

    found_gem = Gel::Environment.find_gem(gem_name, opts[:version])
    unless found_gem
      raise Gel::Error::UnsatisfiedDependencyError.new(
        name: gem_name,
        was_locked: Gel::Environment.locked?,
        found_any: Gel::Environment.find_gem(gem_name),
        requirements: Gel::Support::GemRequirement.new(opts[:version]),
        why: nil,
      )
    end

    command = [*Shellwords.split(editor), found_gem.root]
    Dir.chdir(found_gem.root) do
      exec(*command)
    end
  end
end
