require "spec_helper"

packages = %w( ansible rsync curl sudo )

packages.each do |p|
  describe package(p) do
    it { should be_installed }
  end
end

case os[:family]
when "freebsd"
  describe package("virtualbox-ose-additions-nox11") do
    it { should be_installed }
  end
when "openbsd"
  if os[:release].to_f >= 6.1
    describe file("/etc/installurl") do
      it { should be_file }
      it { should be_mode 644 }
      its(:content) { should match(/^#{Regexp.escape("http://ftp.openbsd.org/pub/OpenBSD")}$/) }
    end
  else
    describe file("/etc/pkg.conf") do
      it { should exist }
      it { should be_file }
      it { should be_mode 644 }
      its(:content) { should match(/^installpath\s*=\s*ftp\.openbsd\.org/) }
    end
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
      it { should be_mode os[:release].to_f >= 6.0 ? 755 : 555 }
    end
  end
  # Specify a package branch
  describe file("/usr/local/lib/python2.7/site-packages/ansible/modules/extras/packaging/os/openbsd_pkg.py") do
    it { should exist }
    it { should be_file }
    its(:content) { should match(/^#{Regexp.escape("# Specify a package branch (requires at least OpenBSD 6.0)")}$/) }
  end
end
