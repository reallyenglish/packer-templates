require "spec_helper"

case os[:family]
when "openbsd"
  describe file("/bsd.sp") do
    it { should exist }
    it { should be_file }
  end
end
