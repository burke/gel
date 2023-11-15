# frozen_string_literal: true

require "test_helper"

class HelpTest < Minitest::Test
  def test_help
    output = capture_stdout { Gel::CLI.run(%W(help)) }

    assert output =~ %r{gel is a modern gem manager}i
    assert output =~ %r{most commonly used commands}i
    assert output =~ %r{https://gel\.dev}
  end

  def test_help_flag
    output = capture_stdout { Gel::CLI.run(%W(--help)) }

    assert output =~ %r{gel is a modern gem manager}i
    assert output =~ %r{most commonly used commands}i
    assert output =~ %r{https://gel\.dev}
  end

  def test_help_short_flag
    output = capture_stdout { Gel::CLI.run(%W(-h)) }

    assert output =~ %r{gel is a modern gem manager}i
    assert output =~ %r{most commonly used commands}i
    assert output =~ %r{https://gel\.dev}
  end
end
