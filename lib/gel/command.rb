# frozen_string_literal: true

class Gel::Command
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
end
