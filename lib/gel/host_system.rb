require "rbconfig"

module Gel::HostSystem
  GEMFILE_PLATFORMS = begin
    v = RbConfig::CONFIG["ruby_version"].split(".")[0..1].inject(:+)

    # FIXME: This isn't the right condition
    if defined?(org.jruby.Ruby)
      ["jruby", "jruby_#{v}", "java", "java_#{v}"]
    else
      ["ruby", "ruby_#{v}", "mri", "mri_#{v}"]
    end
  end
end
