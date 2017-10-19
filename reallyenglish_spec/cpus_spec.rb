require "spec_helper"

case os[:family]
when "openbsd"
  describe command("sysctl -n hw.ncpu") do
    its(:exit_status) { should eq 0 }
    its(:stdout) { should eq "2\n" }
  end
end
