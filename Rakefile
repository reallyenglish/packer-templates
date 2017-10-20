require 'json'
require 'net/http'
require 'pathname'
require 'rainbow'
require 'rspec/core/rake_task'
require 'uri'

VAGRANT_PROVIDERS = {
  virtualbox: {
    builder_type: 'virtualbox-iso'
  },
  vmware_desktop: {
    builder_type: 'vmware-iso'
  }
}.freeze

task default: ['packer:validate', 'packer:check_iso_url']

namespace :packer do
  desc 'Validate all the packer templates'
  task :validate do
    Pathname.glob('*.json').sort.each do |template|
      puts Rainbow("Validating #{template}...").green
      unless system "packer validate #{template}"
        puts Rainbow("#{template} is not a valid packer template").red
        raise "#{template} is not a valid packer template"
      end
    end
  end

  desc 'Check if all the ISO URLs are available'
  task :check_iso_url do
    Pathname.glob('*.json').sort.each do |template|
      json = JSON.parse(template.read)
      mirror = json['variables']['mirror']
      iso_urls = json['builders'].map do |builder|
        builder['iso_url'].sub('{{user `mirror`}}', mirror)
      end
      iso_urls.uniq.each do |iso_url|
        puts Rainbow("Checking if #{iso_url} is available...").green
        request_head(iso_url) do |response|
          unless available?(response)
            puts Rainbow("#{iso_url} is not available: #{response.message}").red
            raise "#{iso_url} is not available"
          end
        end
      end
    end
  end

  desc 'Build and upload the vagrant box to Atlas'
  task :release, [:template, :slug, :version, :provider] do |_t, args|
    template = Pathname.new(args[:template])
    slug     = args[:slug]
    version  = args[:version]
    provider = args[:provider]

    json = JSON.parse(template.read)

    builders = json['builders']
    builders.select! do |builder|
      builder['type'] == VAGRANT_PROVIDERS[provider.to_sym][:builder_type]
    end

    post_processors = json['post-processors']
    post_processors << atlas_post_processor_config(slug, version, provider)
    json['post-processors'] = [post_processors]

    file = Tempfile.open('packer-templates') do |f|
      f.tap do |f|
        JSON.dump(json, f)
      end
    end

    unless system("packer build -var-file=vars/release.json '#{file.path}'")
      puts Rainbow("Failed to release #{slug} to Atlas").red
      raise "Failed to release #{slug} to Atlas"
    end
  end
end

desc 'Run serverspec tests'
RSpec::Core::RakeTask.new(:spec, :host) do |_t, args|
  ENV['HOST'] = args[:host]
end

namespace :reallyenglish do
  require 'yaml'
  require 'vagrant_cloud'
  vagrantcloud_user_name = ENV["VAGRANTCLOUD_USERNAME"] || "trombik"

  # workaround "can't find executable vagrant for gem vagrant. vagrant is not
  # currently included in the bundle, perhaps you meant to add it to your
  # Gemfile? (Gem::Exception)". in _bundled_ environemnt, bundler cannot find
  # `vagrant` gem installed outside of the environment.
  vagrant_path = ""
  Bundler.with_clean_env do
    vagrant_path = Pathname.new(`gem which vagrant`).parent.parent + 'bin'
  end
  ENV['PATH'] = "#{vagrant_path}:#{ENV['PATH']}"

  @yaml = YAML.load_file("box.reallyenglish.yml")
  @all_boxes = @yaml["box"].map { |i| i["name"] }
  ENV['VAGRANT_VAGRANTFILE'] = 'Vagrantfile.reallyenglish'

  namespace 'test' do
    def vagrant_hostname(name)
      "#{name.gsub(/[.]/, '_')}-virtualbox"
    end

    def version_of(name)
      box = @yaml["box"].select { |i| i["name"] == name }.first
      raise "cannot find #{name}" unless box
      raise "box #{name} does not have `version` key" unless box.key?("version")
      box["version"]
    end

    desc 'build and test all boxes'
    task :all => @all_boxes.map { |i| "test:#{i}" }

    @all_boxes.each do |b|
      desc "Test #{b}"
      task b.to_sym => ["reallyenglish:build:#{b}",
                        "reallyenglish:import:#{b}",
                        "reallyenglish:boot:#{b}",
                        "reallyenglish:spec:#{b}",
                        "reallyenglish:destroy:#{b}"]
    end
  end
  namespace 'build' do
    desc 'build all boxes'
    task :all => @all_boxes.map { |i| "build:#{i}" }

    @all_boxes.each do |b|
      desc "Build #{b}"
      task b.to_sym do |_t|
        json_file = "#{b}.json"
        r = system("packer build -only virtualbox-iso -var 'cpus=2' '#{json_file}'")
        raise "Failed to build #{i}" unless r
      end
    end
  end

  namespace 'import' do
    desc 'import all boxes'
    task :all => @all_boxes.map { |i| "import:#{i}" }

    @all_boxes.each do |b|
      desc "import #{b} as a test box"
      task b.to_sym do |_t|
        box_name = "#{vagrantcloud_user_name}/test-#{b}"
        box_file = "#{b}-virtualbox.box"
        r = system("vagrant box add --force --name '#{box_name}' '#{box_file}'")
        raise "Failed to box add test image #{b}" unless r
      end
    end
  end

  namespace 'boot' do
    desc 'import boot all boxes'
    task :all => @all_boxes.map { |i| "boot:#{i}" }

    @all_boxes.each do |b|
      desc "boot #{b} box"
      task b.to_sym do |_t|
        r = system("vagrant up '#{vagrant_hostname(b)}'")
        raise "Failed to boot #{i}" unless r
      end
    end
  end

  namespace 'spec' do
    desc 'Run serverspec tests on a VM'
    task :all => @all_boxes.map { |i| "spec:#{i}" }

    @all_boxes.each do |b|
      desc "Run serverspec on #{b} box"
      RSpec::Core::RakeTask.new("#{b}") do |t|
        t.pattern = 'reallyenglish_spec/**/*_spec.rb'
        ENV['HOST'] = vagrant_hostname(b)
      end
    end
  end

  namespace 'destroy' do
    desc 'Destroy all VMs'
    task :all => @all_boxes.map { |i| "destroy:#{i}" }

    @all_boxes.each do |b|
      desc "Destroy #{b} VM"
      task b.to_sym do |_t|
        r = system("vagrant destroy -f '#{vagrant_hostname(b)}'")
        raise "Failed to destroy #{vagrant_hostname(b)}" unless r
      end
    end
  end

  namespace 'clean' do
    desc 'Clean all VMs'
    task :all => @all_boxes.map { |i| "clean:#{i}" }

    @all_boxes.each do |b|
      desc "Clean #{b}"
      task b.to_sym do |_t|
        r = system("rm -f #{vagrant_hostname(b)}.box")
        raise "Failed to remove #{vagrant_hostname(b)}.box" unless r
      end
    end
  end

  namespace 'upload' do
    @all_boxes.each do |b|
      desc "Upload #{vagrant_hostname(b)}.box to vagrant cloud"
      task b.to_sym do |_t|
        unless ENV["VAGRANTCLOUD_ACCESS_TOKEN"]
          raise "environment variable VAGRANTCLOUD_ACCESS_TOKEN must be defined"
        end
        vagrantcloud_access_token = ENV["VAGRANTCLOUD_ACCESS_TOKEN"]
        account = VagrantCloud::Account.new(vagrantcloud_user_name, vagrantcloud_access_token)
        filename = "#{b}-virtualbox.box"
        raise "cannot find #{filename}" unless File.exist?(filename)
        puts "Ensuring the `#{b}` box is created in vagrantcloud"
        box = account.ensure_box(b)
        puts "Ensuring the box has version `#{version_of(b)}`"
        version = box.ensure_version(version_of(b))
        puts "Ensuring the version `#{version_of(b)}` has virtualbox provider"
        provider = version.ensure_provider('virtualbox', nil)
        puts "Uploading `#{filename}` to vagrantcloud"
        provider.upload_file(filename)
      end
    end
  end

  desc "Destroy all VMs and clean all created boxes"
  task :clean do
    begin
      system("vagrant destroy -f")
    ensure
      r = system("rm -f *.box")
      raise "Failed to destroy VMs" unless r
    end
  end
end

def request_head(uri, &block)
  uri = URI(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true if uri.scheme == 'https'
  http.request_head(uri, &block)
end

def available?(response)
  response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
end

def atlas_post_processor_config(slug, version, provider)
  {
    'type' => 'atlas',
    'artifact' => slug,
    'artifact_type' => 'vagrant.box',
    'metadata' => {
      'version' => version,
      'provider' => provider
    }
  }
end
