require 'spec_helper'

packages = %w( ansible rsync curl )

packages.each do |p|
  describe package(p) do
    it { should be_installed }
  end
end

case os[:family]
when "openbsd"
  describe file("/etc/pkg.conf") do
    it { should exist }
    it { should be_file }
    it { should be_mode 644 }
    its(:content) { should match(/^installpath\s*=\s*ftp\.openbsd\.org/) }
  end

  prefix = "/usr/local/bin"
  python_version = "2.7"
  python_symlinks = {
    "#{prefix}/python" => "#{prefix}/python#{python_version}",
    "#{prefix}/2to3" => "#{prefix}/python#{python_version}-2to3",
    "#{prefix}/python-config" => "#{prefix}/python#{python_version}-config",
    "#{prefix}/pydoc" => "#{prefix}/pydoc#{python_version}"
  }
  python_symlinks.each do |k, v|
    describe file(k) do
      it { should exist }
      it { should be_symlink }
      it { should be_linked_to v }
    end

    describe file(v) do
      it { should exist }
      it { should be_file }
      it { should be_mode 755 }
    end
  end
end
