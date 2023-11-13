# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require "rbconfig"

# Here we're verifying that executing `gel` works regardless of whether the executables
# are being invoked directly or via binstubs. See the commentary in exe/_gel-ruby-disable-gems
# for more explanation.
class ExeTest < Minitest::Test
  EXE_DIR = File.expand_path('../exe', __dir__)

  def test_exe_without_binstubs
    err, stat = gel_version_in_path(EXE_DIR)
    assert stat.success?, "gel version without binstubs failed: #{err}"
  end

  # This one actually doesn't execute _gel-ruby-disable-gems at all.
  def test_exe_with_binstubs
    Dir.mktmpdir do |dir|
      %w(gel _gel-ruby-disable-gems).each do |exe|
        File.write(File.join(dir, exe), <<~BINSTUB, perm: 0755)
          #!#{RbConfig.ruby}
          ARGV.shift
          load '#{File.join(EXE_DIR, exe)}'
        BINSTUB
      end
      err, stat = gel_version_in_path(dir)
      assert stat.success?, "gel version with binstubs failed: #{err}"
    end
  end

  def test_gel_ruby_disable_gems_from_binstub
    Dir.mktmpdir do |dir|
      exe = "_gel-ruby-disable-gems"
      File.write(File.join(dir, exe), <<~BINSTUB, perm: 0755)
        #!#{RbConfig.ruby}
        ARGV.shift
        load '#{File.join(EXE_DIR, exe)}'
      BINSTUB
      err, stat = gel_version_in_path(dir, bin: '_gel-ruby-disable-gems')
      assert stat.success?, "welp: #{err}"
    end
  end

  private

  def gel_version_in_path(dir, bin: 'gel')
    _, err, stat = Open3.capture3(
      # open3 doesn't resolve the initial binary from the provided path,
      # but we do need to provide it because there's another binary resolved from
      # that one.
      { 'PATH' => "#{dir}:#{ENV['PATH']}" }, File.join(dir, bin), 'version',
    )
    [err, stat]
  end
end
