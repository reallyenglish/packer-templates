require 'spec_helper'

packages = %w( ansible rsync curl )

packages.each do |p|
  describe package(p) do
    it { should be_installed }
  end
end
