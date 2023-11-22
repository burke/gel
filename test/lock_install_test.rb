# frozen_string_literal: true

require "test_helper"

class LockInstallTest < Minitest::Test
  def test_install_simple_lockfile
    lockfile = Tempfile.new("")
    lockfile.write(<<LOCKFILE)
GEM
  remote: https://rubygems.org/
  specs:
    rack (2.0.3)
    rack-test (0.6.3)
      rack (>= 1.0)

DEPENDENCIES
  rack-test
LOCKFILE
    lockfile.close

    with_empty_store do |store|
      output = subprocess_output(<<-'END', store: store, lock_path: lockfile.path)
        stub_request(:get, "https://index.rubygems.org/versions").
          to_return(body: <<VERSIONS)
created_at: 2017-03-27T04:38:13+00:00
---
rack 2.0.3 xxx
rack-test 0.6.3 xxx
VERSIONS

        stub_request(:get, "https://index.rubygems.org/info/rack").
          to_return(body: <<INFO)
---
2.0.3 |checksum:zzz
INFO

        stub_request(:get, "https://index.rubygems.org/info/rack-test").
          to_return(body: <<INFO)
---
0.6.3 |checksum:zzz
INFO

        stub_request(:get, "https://rubygems.org/gems/rack-2.0.3.gem").
          to_return(body: File.open(fixture_file("rack-2.0.3.gem")))

        stub_request(:get, "https://rubygems.org/gems/rack-test-0.6.3.gem").
          to_return(body: File.open(fixture_file("rack-test-0.6.3.gem")))

        loader = Gel::LockLoader.new(Gel::ResolvedGemSet.load(lock_path))
        locked = loader.activate(Gel::GodObject, store, install: true)
        Gel::GodObject.open locked

        puts $:.grep(/\brack(?!-test)/).join(":")
        puts $:.grep(/rack-test/).join(":")
        puts $:.grep(/hoe/).join(":")
        puts $".grep(/rack\/test\//).join(":")
      END

      # Both gems listed in the lockfile are activated
      assert_equal "#{store.root}/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/gems/rack-test-0.6.3/lib", output.shift

      # Other installed gems are not
      assert_equal "", output.shift

      # Nothing has been required
      assert_equal "", output.shift
    end
  end

  def test_arch_aware_installation
    lockfile = Tempfile.new("")
    lockfile.write(<<LOCKFILE)
GEM
  remote: https://rubygems.org/
  specs:
    atomic (1.1.16)
    atomic (1.1.16-java)
    rack (2.0.3)
    rack-test (0.6.3)
      rack (>= 1.0)

PLATFORMS
  java
  ruby

DEPENDENCIES
  atomic
  rack-test
LOCKFILE
    lockfile.close

    with_empty_multi_store do |store|
      output = subprocess_output(<<-'END', store: store, lock_path: lockfile.path)
        stub_request(:get, "https://index.rubygems.org/versions").
          to_return(body: <<VERSIONS)
created_at: 2017-03-27T04:38:13+00:00
---
atomic 1.1.16,1.1.16-java xxx
rack 2.0.3 xxx
rack-test 0.6.3 xxx
VERSIONS

        stub_request(:get, "https://index.rubygems.org/info/atomic").
          to_return(body: <<INFO)
---
1.1.16 |checksum:zzz
1.1.16-java |checksum:zzz
INFO

        stub_request(:get, "https://index.rubygems.org/info/rack").
          to_return(body: <<INFO)
---
2.0.3 |checksum:zzz
INFO

        stub_request(:get, "https://index.rubygems.org/info/rack-test").
          to_return(body: <<INFO)
---
0.6.3 |checksum:zzz
INFO

        if jruby?
          stub_request(:get, "https://rubygems.org/gems/atomic-1.1.16-java.gem").
            to_return(body: File.open(fixture_file("atomic-1.1.16-java.gem")))
        else
          stub_request(:get, "https://rubygems.org/gems/atomic-1.1.16.gem").
            to_return(body: File.open(fixture_file("atomic-1.1.16.gem")))
        end

        stub_request(:get, "https://rubygems.org/gems/rack-2.0.3.gem").
          to_return(body: File.open(fixture_file("rack-2.0.3.gem")))

        stub_request(:get, "https://rubygems.org/gems/rack-test-0.6.3.gem").
          to_return(body: File.open(fixture_file("rack-test-0.6.3.gem")))

        loader = Gel::LockLoader.new(Gel::ResolvedGemSet.load(lock_path))
        locked = loader.activate(Gel::GodObject, store, install: true)
        Gel::GodObject.open locked

        puts $:.grep(/\brack(?!-test)/).join(":")
        puts $:.grep(/rack-test/).join(":")
        puts $:.grep(/atomic/).join(":")
        puts $:.grep(/hoe/).join(":")
        puts $".grep(/rack\/test\//).join(":")
      END

      # All gems listed in the lockfile are activated
      assert_equal "#{store.root}/ruby/gems/rack-2.0.3/lib", output.shift
      assert_equal "#{store.root}/ruby/gems/rack-test-0.6.3/lib", output.shift
      # and in the right directories
      if jruby?
        assert_equal "#{store.root}/java/gems/atomic-1.1.16/lib", output.shift
      else
        assert_equal "#{store.root}/#{Gel::MultiStore::VERSION}/gems/atomic-1.1.16/lib:#{store.root}/#{Gel::MultiStore::VERSION}/ext/atomic-1.1.16", output.shift
      end

      # Other installed gems are not
      assert_equal "", output.shift

      # Nothing has been required
      assert_equal "", output.shift
    end
  end
end
