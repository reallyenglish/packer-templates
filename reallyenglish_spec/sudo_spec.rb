require "spec_helper"

cmd = ""
case os[:family]
when "freebsd"
  cmd = "su -m root -c 'sudo echo'"
else
  cmd = "su -l -s /bin/sh root -c 'sudo echo'"
end

describe command(cmd) do
  its(:exit_status) { should eq 0 }
end
