# frozen_string_literal: true

class Gel::Command::Update < Gel::Command::Base
  define_options do |o|
    o.banner = <<~BANNER.chomp
      TODO

      Usage: gel update

      Options:
    BANNER
  end

  def run(command_line)
    # Parse and handle help, but just pass unmodified to Lock.
    _opts = parse_options(command_line.dup)

    # Mega update mode
    command_line = ["--major"] if command_line.empty?

    Gel::Command::Lock.new.run(command_line)
    Gel::Environment.activate(install: true, output: $stderr)
  end
end
