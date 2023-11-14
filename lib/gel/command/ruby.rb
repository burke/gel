# frozen_string_literal: true

class Gel::Command::Ruby < Gel::Command::Base
  # Manually defined so we don't get the help option.
  def self.options
    Gel::Vendor::Slop::Options.new do |o|
      o.banner = <<~BANNER.chomp
        Invoke ruby with the current environment.

        Usage: gel ruby [<arguments>]
      BANNER
    end
  end

  # No options: even --help should be passed to ruby.
  def run(command_line)
    command = Gel::Command::Exec.new
    command.run(["ruby", *command_line])
  ensure
    self.reraise = command.reraise if command
  end
end
