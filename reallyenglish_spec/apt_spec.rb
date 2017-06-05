require 'spec_helper'

case os[:family]
when "ubuntu"
  describe file("/etc/apt/apt.conf.d/10disable-periodic") do
    it { should be_exist }
    it { should be_file }
    it { should be_mode 644 }
    its(:content) { should match(/^APT::Periodic::Enable\s+"0";/) }
  end
end
