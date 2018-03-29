require "spec_helper"

case os[:family]
when "openbsd"
  if ENV['VAGRANT_CPU_CORE'] == "1"
    describe file("/bsd.sp") do
      it { should_not exist }
    end

    describe command("sysctl -n hw.ncpu") do
      its(:exit_status) { should eq 0 }
      its(:stdout) { should eq "1\n" }
    end

    describe command("sysctl -n hw.ncpufound") do
      its(:exit_status) { should eq 0 }
      its(:stdout) { should eq "1\n" }
    end
  else
    describe file("/bsd.sp") do
      it { should exist }
      it { should be_file }
    end

    describe command("sysctl -n hw.ncpu") do
      its(:exit_status) { should eq 0 }
      its(:stdout) { should eq "2\n" }
    end

    describe command("sysctl -n hw.ncpufound") do
      its(:exit_status) { should eq 0 }
      its(:stdout) { should eq "2\n" }
    end
  end
end
