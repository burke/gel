# frozen_string_literal: true

require_relative "compatibility"

module Gel::CLI
  extend Gel::Autoload

  gel_autoload :Base, "gel/command/base"

  gel_autoload :Version, "gel/command/version"
  gel_autoload :Install, "gel/command/install"
  gel_autoload :InstallGem, "gel/command/install_gem"
  gel_autoload :Env, "gel/command/env"
  gel_autoload :Exec, "gel/command/exec"
  gel_autoload :Lock, "gel/command/lock"
  gel_autoload :Update, "gel/command/update"
  gel_autoload :Ruby, "gel/command/ruby"
  gel_autoload :Stub, "gel/command/stub"
  gel_autoload :Config, "gel/command/config"
  gel_autoload :ShellSetup, "gel/command/shell_setup"
  gel_autoload :Open, "gel/command/open"

  def self.print_global_help(stream: $stdout)
    stream.puts(options)
  end

  def self.print_command_help(command, stream: $stdout)
    # TODO: this is redundant... we should use a command registry.
    # TODO: support gel-* by exec'ing gel-x --help
    if command.is_a?(String)
      const = command.downcase.sub(/^./, &:upcase).gsub(/[-_]./) { |s| s[1].upcase }
      if const =~ /\A[a-z]+\z/i
        if Gel::Command.const_defined?(const, false)
          command = Gel::Command.const_get(const, false)
        else
          raise Gel::Error::UnknownCommandError.new(command_name: command)
        end
      else
        raise Gel::Error::UnknownCommandError.new(command_name: command)
      end
    end
    stream.puts command.options
  end

  def self.options
    @options ||= Gel::Vendor::Slop::Options.new(subcommands: true) do |o|
      o.banner = <<~BANNER.chomp
        gel is a modern gem manager.

        Usage: gel <command> [<args>]

        Options:
      BANNER

      o.bool '-h', '--help', 'Print help (same as help command)'
      o.on '--version', 'Print the version' do
        Gel::Command::Version.new.run([])
        exit
      end

      o.separator <<~SEPARATOR.chomp

        Most commonly used commands:
            gel help          Get this help, or help for a command.
            gel install       Install the gems from Gemfile.
            gel lock          Update lockfile without installing.
            gel exec          Run command in context of the gel.

        All commands:
            env, install, lock, ruby, stub, version, config, exec,
            install_gem, open, shell_setup, update

        Run `gel help <command>` for more information on a specific command.
      SEPARATOR
    end
  end

  def self.run(argv)
    opts = options.parse(argv)
    argv = opts.arguments
    command_name = argv.shift

    # support both `gel -h exec` and `gel help exec`
    want_help = opts[:help]
    if !want_help && command_name == "help"
      want_help = true
      command_name = argv.shift
    end

    if want_help
      if command_name
        print_command_help(command_name)
      else
        print_global_help
      end
      exit 0
    end

    if command_name.nil?
      print_global_help(stream: $stderr)
      exit 1
    end

    const = command_name.downcase.sub(/^./, &:upcase).gsub(/[-_]./) { |s| s[1].upcase }
    if const =~ /\A[a-z]+\z/i
      if Gel::Command.const_defined?(const, false)
        command = Gel::Command.const_get(const, false).new
        command.run(argv)
      elsif Gel::Environment.activate_for_executable(["gel-#{command_name}", command_name])
        command_name = "gel-#{command_name}" if Gel::Environment.find_executable("gel-#{command_name}")
        command = Gel::Command::Exec.new
        command.run([command_name, *argv])
      else
        raise Gel::Error::UnknownCommandError.new(command_name: command_name)
      end
    elsif stub_name = own_stub_file?(command_name) || other_stub_file?(command_name)
      command = Gel::Command::Exec.new
      command.run([stub_name, *argv], from_stub: true)
    else
      raise Gel::Error::UnknownCommandError.new(command_name: command_name)
    end
  rescue Exception => ex
    raise if $DEBUG || (command && command.reraise)
    handle_error(ex)
  end

  def self.handle_error(ex)
    case ex
    when Gel::Vendor::Slop::Error
      $stderr.puts "gel: #{ex.message}"
      exit 1
    when Gel::ReportableError
      $stderr.puts "ERROR: #{ex.message}"
      if more = ex.details
        $stderr.puts more
      end

      exit ex.exit_code
    when Interrupt
      # Re-signal so our parent knows why we died
      Signal.trap(ex.signo, "SYSTEM_DEFAULT")
      Process.kill(ex.signo, Process.pid)

      # Shouldn't be reached
      raise ex
    when SystemExit, SignalException
      raise ex
    when StandardError, ScriptError, NoMemoryError, SystemStackError
      # We want basically everything here: we definitely care about
      # StandardError and ScriptError... but we also assume that whatever
      # caused NoMemoryError or SystemStackError was way down the call
      # stack, so we've now unwound enough to safely handle even those.

      $stderr.print "\n\n===== Gel Internal Error =====\n\n"

      # We'll improve this later, but for now after the header we'll leave
      # ruby to write the message & backtrace:
      raise ex
    else
      raise ex
    end
  end

  def self.extract_word(arguments)
    if idx = arguments.index { |w| w =~ /^[^-]/ }
      arguments.delete_at(idx)
    end
  end

  def self.own_stub_file?(path)
    # If it's our own stub file, we can skip reading and parsing it, and
    # just trust that the basename is correct.
    if Gel::Environment.store.stub_set.own_stub?(path)
      File.basename(path)
    end
  end

  def self.other_stub_file?(path)
    Gel::Environment.store.stub_set.parse_stub(path)
  end
end
