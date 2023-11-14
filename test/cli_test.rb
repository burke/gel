# frozen_string_literal: true

require "test_helper"
require "gel/command"

class CLITest < Minitest::Test
  def setup
    super

    @original_env = ENV.map { |k, v| [k, v.dup] }.to_h

    ENV["GEL_GEMFILE"] = nil
    ENV["GEL_LOCKFILE"] = nil
    ENV["RUBYLIB"] = nil
    ENV["RUBYOPT"] = nil
    Gel::Environment.gemfile = nil
  end

  def teardown
    (@original_env.keys | ENV.keys).each do |key|
      ENV[key] = @original_env[key]
    end

    super
  end

  def test_basic_help
    Gel::Command::Help.expects(:new).returns(mock(run: true))

    Gel::CLI.run(%W(help))
  end

  def test_help_flag
    Gel::Command::Help.expects(:new).returns(mock(run: true))

    Gel::CLI.run(%W(--help))
  end

  def test_version_flag
    Gel::Command::Version.expects(:new).returns(mock(run: true))

    Gel::CLI.run(%W(--version))
  end

  def test_flag_abriviations
    Gel::Command::Version.expects(:new).returns(mock(run: true))
    Gel::Command::Help.expects(:new).returns(mock(run: true))

    Gel::CLI.run(%W(-v))
    Gel::CLI.run(%W(-h))
  end

  def test_basic_install
    Gel::Environment.expects(:activate).with(has_entries(install: true, output: $stderr))

    Gel::CLI.run(%W(install))
  end

  # TODO: There's too much behaviour here, yet it's still not a full
  # integration test. Move the exec logic out of Command::Exec, reducing
  # that to a simple wrapper.
  def test_exec_inline
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)

      File.write("#{dir}/Gemfile", "")
      File.write("#{dir}/Gemfile.lock", "")
      File.write("#{dir}/ruby-executable", "#!/usr/bin/ruby\n")
      FileUtils.chmod 0755, "#{dir}/ruby-executable"

      Gel::Environment.expects(:activate)

      Kernel.expects(:load).with do |path|
        assert_equal "ruby-executable", path

        assert_equal "#{dir}/Gemfile", ENV["GEL_GEMFILE"]
        assert_equal "#{dir}/Gemfile.lock", ENV["GEL_LOCKFILE"]
        assert_nil ENV["RUBYOPT"]
        assert_equal File.expand_path("../slib", __dir__), ENV["RUBYLIB"]

        assert_equal "ruby-executable", $0
        assert_equal ["some", "args"], ARGV
      end

      Dir.chdir(dir) do
        catch(:exit) do
          Gel::CLI.run(%W(exec ruby-executable some args))
        end
      end
    end
  end

  def test_exec_nonruby
    Dir.mktmpdir do |dir|
      dir = File.realpath(dir)

      File.write("#{dir}/Gemfile", "")
      File.write("#{dir}/Gemfile.lock", "")
      File.write("#{dir}/shell-executable", "#!/bin/sh\n")
      FileUtils.chmod 0755, "#{dir}/shell-executable"

      Kernel.expects(:exec).with do |*command|
        assert_equal [["shell-executable", "shell-executable"], "some", "args"], command

        assert_equal "#{dir}/Gemfile", ENV["GEL_GEMFILE"]
        assert_equal "#{dir}/Gemfile.lock", ENV["GEL_LOCKFILE"]
        assert_nil ENV["RUBYOPT"]
        assert_equal File.expand_path("../slib", __dir__), ENV["RUBYLIB"]
      end.throws(:exit)

      Dir.chdir(dir) do
        catch(:exit) do
          Gel::CLI.run(%W(exec shell-executable some args))
        end
      end
    end
  end
end
