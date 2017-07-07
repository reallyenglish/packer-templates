require 'spec_helper'

describe yumrepo('epel'), if: os[:family] == 'redhat' do
  it { should_not exist }
end
