# frozen_string_literal: true

class Gel::Command::ShellSetup < Gel::Command::Base
  def call(opts)
    command_line = opts.arguments
    require "shellwords"

    shell = command_line[0] || File.basename(ENV.fetch("SHELL", "bash"))

    bin_dir = File.expand_path("~/.local/gel/bin")
    unless ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).include?(bin_dir)
      puts export("PATH", "\"#{Shellwords.shellescape bin_dir}#{File::PATH_SEPARATOR}$PATH\"", shell: shell)
    end

    lib_dir = File.expand_path("../../slib", __dir__)
    unless ENV.fetch("RUBYLIB", "").split(File::PATH_SEPARATOR).include?(lib_dir)
      puts export("RUBYLIB", "\"#{Shellwords.shellescape lib_dir}:$RUBYLIB\"", shell: shell)
    end
  end

  def export(env, value, shell: nil)
    case shell
    when "fish"
      "set -x #{env} #{value}"
    else
      "export #{env}=#{value}"
    end
  end
end
