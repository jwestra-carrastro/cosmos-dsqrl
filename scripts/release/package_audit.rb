require 'httpclient'
require 'dotenv'
require 'json'
Dotenv.load

version_tag = ARGV[0] || "latest"

def get_docker_version(path)
  File.open("#{__dir__}/../../#{path}") do |file|
    file.each do |line|
      if line.include?("FROM")
        return line.split(':')[-1].strip
      end
    end
  end
end

# Get versions from the Dockerfiles
traefik_version = get_docker_version("openc3-traefik/Dockerfile")
redis_version = get_docker_version("openc3-redis/Dockerfile")
minio_version = get_docker_version("openc3-minio/Dockerfile")

# Manual list - MAKE SURE UP TO DATE especially base images
containers = [
  # This should match the values in the .env file
  { name: "openc3inc/openc3-ruby:#{version_tag}", base_image: "alpine:#{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD']}", apk: true, gems: true },
  { name: "openc3inc/openc3-node:#{version_tag}", base_image: "openc3inc/openc3-ruby:#{version_tag}", apk: true },
  { name: "openc3inc/openc3-base:#{version_tag}", base_image: "openc3inc/openc3-ruby:#{version_tag}", apk: true, gems: true },
  { name: "openc3inc/openc3-cosmos-cmd-tlm-api:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true },
  { name: "openc3inc/openc3-cosmos-init:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true,
    yarn: ["/openc3/plugins/yarn.lock", "/openc3/plugins/yarn-tool-base.lock"] },
  { name: "openc3inc/openc3-operator:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true },
  { name: "openc3inc/openc3-cosmos-script-runner-api:#{version_tag}", base_image: "openc3inc/openc3-base:#{version_tag}", apk: true, gems: true },
  { name: "openc3inc/openc3-redis:#{version_tag}", base_image: "redis:#{redis_version}", apt: true },
  { name: "openc3inc/openc3-traefik:#{version_tag}", base_image: "traefik:#{traefik_version}", apk: true },
  { name: "openc3inc/openc3-minio:#{version_tag}", base_image: "minio/minio:#{minio_version}", rpm: true },
]

$overall_apk = []
$overall_apt = []
$overall_rpm = []
$overall_gems = []
$overall_yarn = []

def make_sorted_hash(name_versions)
  result = {}
  name_versions.sort!
  name_versions.each do |name, version, package|
    result[name] ||= [[], []]
    result[name][0] << version
    result[name][1] << package
  end
  result.each do |name, data|
    data[0].uniq!
    data[1].uniq!
  end
  result
end

def breakup_versioned_package(line, name_versions, package)
  split_line = line.split('-')
  found = false
  (split_line.length - 1).times do |index|
    i = index + 1
    if (split_line[i][0] =~ /\d/) or split_line[i -1] == 'pubkey'
      name = split_line[0..(i - 1)].join('-')
      version = split_line[i..-1].join('-')
      name_versions << [name, version, package]
      found = true
      break
    end
  end
  raise "Couldn't breakup version for #{package}" unless found
end

def extract_apk(container)
  container_name = container[:name]
  name_versions = []
  lines = `docker run --rm #{container_name} apk list -I`
  lines.each_line do |line|
    package = line.split(' ')[0]
    breakup_versioned_package(package, name_versions, package)
  end
  $overall_apk.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_apt(container)
  container_name = container[:name]
  results = `docker run --rm #{container_name} apt list --installed`
  name_versions = []
  results.each_line do |line|
    next if line =~ /Listing/
    name = line.split("/now")[0]
    version = line.split(' ')[1]
    name_versions << [name, version, nil]
  end
  $overall_apt.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_rpm(container)
  container_name = container[:name]
  name_versions = []
  lines = `docker run --entrypoint "" --rm #{container_name} rpm -qa`
  lines.each_line do |line|
    full_package = line.strip
    split_line = full_package.split('.')
    if split_line.length > 1
      split_line = split_line[0..-3] # Remove el8 and arch
    end
    line = split_line.join('.')
    breakup_versioned_package(line, name_versions, full_package)
  end
  $overall_rpm.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_gems(container)
  container_name = container[:name]
  name_versions = []
  lines = `docker run --rm #{container_name} gem list --local`
  lines.each_line do |line|
    split_line = line.strip.split(' ')
    name = split_line[0]
    rest = split_line[1..-1].join(' ')
    versions = rest[1..-2]
    versions.gsub!("default: ", "")
    versions = versions.split(',')
    name_versions << [name, versions, nil]
  end
  $overall_gems.concat(name_versions)
  make_sorted_hash(name_versions)
end

def extract_yarn(container)
  container_name = container[:name]
  name_versions = []
  yarn_lock_paths = container[:yarn]
  yarn_lock_paths.each do |path|
    id = `docker create #{container_name}`.strip
    `docker cp #{id}:#{path} .`
    `docker rm -v #{id}`
    data = File.read(path.split('/')[-1])
    name_versions.concat(process_yarn(data))
  end
  $overall_yarn.concat(name_versions)
  make_sorted_hash(name_versions)
end

def process_yarn(data)
  result = []
  name = nil
  version_next = false
  data.each_line do |line|
    if version_next
      version_next = false
      version = line.split('"')[1]
      result << [name, version, nil]
    end
    if line[0] != " " and line[0] != '#' and line.strip != ""
      if line[0] == '"'
        part = line.split('"')[1]
        last_at = part.rindex('@')
        name = part[0..(last_at - 1)]
      else
        name = line.split('@')[0]
      end
      version_next = true
    end
  end
  result
end

def build_section(title, name_version_hash, show_full_packages = false)
  report = ""
  report << "#{title}:\n"
  name_version_hash.each do |name, data|
    versions = data[0]
    packages = data[1]
    if show_full_packages
      report << "  #{name} (#{versions.join(', ')}) [#{packages.join(', ')}]\n"
    else
      report << "  #{name} (#{versions.join(', ')})\n"
    end
  end
  report
end

def build_summary_report(containers)
  report = ""
  report << "OpenC3 COSMOS Package Report Summary\n"
  report << "-" * 80
  report << "\n\nCreated: #{Time.now}\n\n"
  report << "Containers:\n"
  containers.each do |container|
    if container[:base_image]
      report << "  #{container[:name]} - Base Image: #{container[:base_image]}\n"
    else
      report << "  #{container[:name]}\n"
    end
  end
  report << "\n"
  if $overall_apk.length > 0
    report << build_section("APK Packages", make_sorted_hash($overall_apk), false)
    report << "\n"
  end
  if $overall_apt.length > 0
    report << build_section("APT Packages", make_sorted_hash($overall_apt), false)
    report << "\n"
  end
  if $overall_rpm.length > 0
    report << build_section("RPM Packages", make_sorted_hash($overall_rpm), true)
    report << "\n"
  end
  if $overall_gems.length > 0
    report << build_section("Ruby Gems", make_sorted_hash($overall_gems), false)
    report << "\n"
  end
  if $overall_yarn.length > 0
    report << build_section("Node Packages", make_sorted_hash($overall_yarn), false)
    report << "\n"
  end
  report
end

def build_container_report(container)
  report = ""
  report << "Container: #{container[:name]}\n"
  report << "Base Image: #{container[:base_image]}\n" if container[:base_image]
  report << build_section("APK Packages", extract_apk(container), false) if container[:apk]
  report << build_section("APT Packages", extract_apt(container), false) if container[:apt]
  report << build_section("RPM Packages", extract_rpm(container), true) if container[:rpm]
  report << build_section("Ruby Gems", extract_gems(container), false) if container[:gems]
  report << build_section("Node Packages", extract_yarn(container), false) if container[:yarn]
  report << "\n"
  report
end

def build_report(containers)
  report = ""
  report << "Individual Container Reports\n"
  report << "-" * 80
  report << "\n\n"
  containers.each do |container|
    report << build_container_report(container)
  end
  report
end

def check_latest_alpine(client)
  resp = client.get_content('http://dl-cdn.alpinelinux.org/alpine/')
  major, minor = ENV['ALPINE_VERSION'].split('.')
  major = major.to_i
  minor = minor.to_i
  if resp.include?(ENV['ALPINE_VERSION'])
    if resp.include?("#{major + 1}.0")
      puts "NOTE: Alpine has a new major version: #{major}.0. Read release notes at https://wiki.alpinelinux.org/wiki/Release_Notes_for_Alpine_#{major}.0.0"
    end
    if resp.include?("#{major}.#{minor + 1}")
      puts "NOTE: Alpine has a new minor version: #{major}.#{minor + 1}. Read release notes at https://alpinelinux.org/posts/Alpine-#{major}.#{minor + 1}.0-released.html"
    end
    resp = client.get_content("http://dl-cdn.alpinelinux.org/alpine/v#{ENV['ALPINE_VERSION']}/releases/armv7")
    if resp.include?("alpine-virt-#{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD'].to_i + 1}-armv7.iso")
      puts "Alpine has a new patch version: #{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD'].to_i + 1}"
    end
    if !resp.include?("alpine-virt-#{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD']}-armv7.iso")
      puts "ERROR: Could not find Alpine build: #{ENV['ALPINE_VERSION']}.#{ENV['ALPINE_BUILD']}"
    end
  else
    puts "ERROR: Could not find Alpine build: #{ENV['ALPINE_VERSION']}"
  end
end

def check_latest_minio(client, containers)
  container = containers.select { |val| val[:name].include?('openc3-minio') }[0]
  minio_version = container[:base_image].split(':')[-1]
  resp = client.get_content('https://registry.hub.docker.com/v2/repositories/minio/minio/tags?page_size=1024')
  images = JSON.parse(resp)['results']
  versions = []
  images.each do |image|
    versions << image['name']
  end
  if versions.include?(minio_version)
    split_version = minio_version.split('.')
    minio_time = Time.parse(split_version[1])
    versions.each do |version|
      split_version = version.split('.')
      if split_version[0] == 'RELEASE'
        version_time = Time.parse(split_version[1])
        if version_time > minio_time
          puts "NOTE: Minio has a new version: #{version}, Current Version: #{minio_version}"
          return
        end
      end
    end
    puts "Minio up to date: #{minio_version}"
  else
    puts "ERROR: Could not find Minio image: #{minio_version}"
  end
end

def check_latest_container_version(client, containers, name)
  container = containers.select { |val| val[:name].include?("openc3-#{name}") }[0]
  version = container[:base_image].split(':')[-1]
  resp = client.get_content("https://registry.hub.docker.com/v2/repositories/library/#{name}/tags?page_size=1024")
  images = JSON.parse(resp)['results']
  versions = []
  images.each do |image|
    versions << image['name']
  end
  if versions.include?(version)
    new_version = false
    major, minor, patch = version.split('.')
    if versions.include?("#{major.to_i + 1}.0")
      puts "NOTE: #{name} has a new major version: #{major.to_i + 1}, Current Version: #{version}"
      new_version = true
    end
    if versions.include?("#{major}.#{minor.to_i + 1}")
      puts "NOTE: #{name} has a new minor version: #{major}.#{minor.to_i + 1}, Current Version: #{version}"
      new_version = true
    end
    if versions.include?("#{major}.#{minor}.#{patch.to_i + 1}")
      puts "NOTE: #{name} has a new patch version: #{major}.#{minor}.#{patch.to_i + 1}, Current Version: #{version}"
      new_version = true
    end
    puts "#{name} is is up to date with #{version}" unless new_version
  else
    puts "ERROR: Could not find #{name} image: #{version}"
  end
end

# Update the bundles
Dir.chdir(File.join(__dir__, '../../openc3')) do
  `bundle update`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-cmd-tlm-api')) do
  `bundle update`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-script-runner-api')) do
  `bundle update`
end

# Build reports
report = build_report(containers)
summary_report = build_summary_report(containers)

# Now check for latest versions
client = HTTPClient.new
check_latest_alpine(client)
check_latest_container_version(client, containers, 'traefik')
check_latest_minio(client, containers)
check_latest_container_version(client, containers, 'redis')

# Check the bundles
Dir.chdir(File.join(__dir__, '../../openc3')) do
  puts "\nChecking outdated gems in openc3:"
  puts `bundle outdated`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-cmd-tlm-api')) do
  puts "\nChecking outdated gems in openc3-cosmos-cmd-tlm-api:"
  puts `bundle outdated`
end
Dir.chdir(File.join(__dir__, '../../openc3-cosmos-script-runner-api')) do
  puts "\nChecking outdated gems in openc3-cosmos-script-runner-api:"
  puts `bundle outdated`
end

File.open("openc3_package_report.txt", "w") do |file|
  file.write(summary_report)
  file.write(report)
end

puts "\n\nRun the following in openc3-cosmos-init/plugins and openc3-cosmos-init/plugins/openc3-tool-base:"
puts "  yarn upgrade-interactive --latest"
