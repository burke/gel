# frozen_string_literal: true

require "test_helper"

class VersionTest < Minitest::Test
  def test_version_command
    output = capture_stdout { Gel::Command::Version.new.run }

    assert output =~ %r{Gel version}
  end

  def test_version_flag
    output = capture_stdout { Gel::CLI.run(["--version"]) }

    assert output =~ %r{Gel version}
  end
end
