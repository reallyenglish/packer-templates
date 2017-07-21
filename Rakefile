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
  @yaml = YAML.load_file("box.reallyenglish.yml")
  ENV['VAGRANT_VAGRANTFILE'] = 'Vagrantfile.reallyenglish'

  desc 'Test all boxes'
  task :test do |_t|
    images = @yaml['box']
    images.each do |image|
      Rake::Task['reallyenglish:do_test'].invoke(image)
      Rake::Task['reallyenglish:do_test'].reenable
    end
  end

  desc 'Test a box'
  task :do_test, [:host] do |_t, args|
    [
      'reallyenglish:build',
      'reallyenglish:import',
      'reallyenglish:up',
      'reallyenglish:spec',
      'reallyenglish:destroy'
    ].each do |task|
      Rake::Task[task].invoke(args[:host])
      Rake::Task[task].reenable
    end
  end

  desc 'Build a box'
  task :build, [:host] do |_t, args|
    json_file = "#{args[:host]}.json"
    r = system("packer build -only virtualbox-iso '#{json_file}'")
    raise "Failed to build #{i}" unless r
  end

  desc 'Import a box'
  task :import, [:host] do |_t, args| 
    box_name = "trombik/test-#{args[:host]}"
    box_file = "#{args[:host]}-virtualbox.box"
    r = system("vagrant box add --force --name '#{box_name}' '#{box_file}'")
    raise "Failed to box add test image #{args[:host]}" unless r
  end

  desc 'Boot a VM'
  task :up, [:host] do |_t, args|
    vagrant_hostname = "#{args[:host].gsub(/[.]/, '_')}-virtualbox"
    r = system("vagrant up '#{vagrant_hostname}'")
    raise "Failed to launch #{i}" unless r
  end

  desc 'Run serverspec tests on a VM'
  RSpec::Core::RakeTask.new(:spec, :host) do |t, args|
    t.pattern = 'reallyenglish_spec/**/*_spec.rb'
    vagrant_hostname = "#{args[:host].gsub(/[.]/, '_')}-virtualbox"
    ENV['HOST'] = vagrant_hostname
  end

  desc 'Destroy a VM'
  task :destroy, [:host] do |_t, args|
    vagrant_hostname = "#{args[:host].gsub(/[.]/, '_')}-virtualbox"
    r = system("vagrant destroy -f '#{vagrant_hostname}'")
    raise "Failed to destroy #{i}" unless r
  end

  desc 'Clean'
  task :clean do |_t|
      ENV['VAGRANT_VAGRANTFILE'] = 'Vagrantfile.reallyenglish'
      r = system('vagrant destroy -f')
      raise "Failed to destroy VMs" unless r
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
