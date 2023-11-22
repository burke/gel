# frozen_string_literal: true

require "test_helper"

class LockedActivateTest < Minitest::Test
  def test_lock_forces_version
    with_fixture_gems_installed(["rack-2.0.3.gem", "rack-0.1.0.gem"]) do |store|
      output = subprocess_output(<<-'END', store: store)
        Gel.open_environment(store)
        Gel.environment.gem "rack"

        puts $:.grep(/\brack/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift


      output = subprocess_output(<<-'END', store: store)
        locked_store = Gel::LockedStore.new(store)
        locked_store.lock("rack" => "0.1.0")

        Gel.open_environment(locked_store)
        Gel.environment.gem "rack"

        puts $:.grep(/\brack/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-0.1.0/lib", output.shift
    end
  end

  def test_lock_excludes_gems
    with_fixture_gems_installed(["hoe-3.0.0.gem", "rack-2.0.3.gem"]) do |store|
      output = subprocess_output(<<-'END', store: store)
        Gel.open_environment(store)
        Gel.environment.gem "rack"

        puts $:.grep(/\brack/).join(":")
      END

      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift


      output = subprocess_output(<<-'END', store: store)
        locked_store = Gel::LockedStore.new(store)
        locked_store.lock("hoe" => "3.0.0")

        Gel.open_environment(locked_store)
        begin
          Gel.environment.gem "rack"
        rescue LoadError => ex
          puts ex.message
        end
      END

      assert_equal "Gem \"rack\" is not present in Gemfile; unable to satisfy requirements: >= 0", output.shift
    end
  end
end
