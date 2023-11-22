# frozen_string_literal: true

class Gel::Command::Install < Gel::Command
  def run(command_line)
    Gel::GodObject.activate(install: true, output: $stderr)
  end
end
