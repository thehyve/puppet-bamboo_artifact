require 'net/http'
require 'uri'
require 'yaml'
require 'rexml/document'

Puppet::Type.type(:bamboo_artifact).provide(:bamboo_artifact_provider) do

  def initialize(*args)
    super *args
  end

  def self.generate_property_accessor(prop)
    define_method(prop) do
      read_meta prop
    end
    define_method("#{prop}=".to_sym) do |value|
      # empty body, changes are only made on flush, which reads
      # from the should values directly
    end
  end

  (resource_type.validproperties - [:ensure]).each do |p|
    generate_property_accessor p
  end

  def exists?
    File.file? resource[:path]
  end

  def latest_build
    return @latest_build if @latest_build

    uri = URI("#{resource[:server]}/rest/api/latest/result/#{resource[:plan]}/latest/")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 10
    http.open_timeout = 10

    http_req = Net::HTTP::Get.new(uri.path)

    begin
      http_res = http.request(http_req)
    rescue Exception => e
      raise Exception, "Could not find latest build, request failure for #{uri}: #{e.message}"
    end

    unless http_res.kind_of?(Net::HTTPSuccess)
      raise Exception, "Could not find latest build, bad http request for #{uri}: #{http_res}"
    end

    @latest_build = parse_response http_res.body
    notice "Checked #{uri} for latest build, got #{@latest_build}" unless @latest_build == :skip
    @latest_build
  end

  def create
    # everything done on flush
  end

  def destroy
    # everything done on the dependent file resources
  end

  def flush
    return unless resource[:ensure] == :present

    if desired_build_number == :skip
      fail "No update can be made, as the latest build has failed"
    end

    uri = URI("#{resource[:server]}/browse/#{resource[:plan]}-" \
              "#{desired_build_number}/artifact/#{resource[:artifact_path]}")
    Puppet.notice "Will download #{uri}"
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 10
    http.open_timeout = 10

    req = Net::HTTP::Get.new(uri.path)

    begin
      http.request req do |resp|
        unless resp.kind_of?(Net::HTTPSuccess)
          raise Exception, "Failed to download artifact: #{resp}"
        end

        open temp_file, 'w' do |io|
          resp.read_body do |chunk|
            io.write chunk
          end
        end
        break
      end

      save_meta
      File.rename temp_file, resource[:path]
    rescue
      File.delete temp_file if File.exists? temp_file
      raise
    end
  end

  private

  def desired_build_number
    return latest_build if resource[:build] == :latest
    resource[:build]
  end

  def temp_file
    resource[:path] + '.tmp'
  end

  def parse_response(body)
    xmldoc = REXML::Document.new(body)
    build_state = REXML::XPath.first(xmldoc, 'string(//buildState)')
    build_number = REXML::XPath.first(xmldoc, 'string(/result/@number)')
    if build_state != 'Successful'
      warning "State of build #{build_number} is #{build_state}, not updating"
      return :skip
    end

    build_number.to_i
  end

  def current_meta
    unless @current_meta
      begin
        @current_meta = YAML.load(IO.read(resource.meta_file))
      rescue SystemCallError => e
        @current_meta = {}
        Puppet.debug("Meta-file loading error; possibly doesn't exist yet: #{e}")
      end
    end

    @current_meta
  end

  def save_meta
    @current_meta = resource.to_hash
    current_meta[:build] = latest_build if resource[:build] == :latest
    IO.write(resource.meta_file, YAML.dump(current_meta))
  end

  def read_meta(key)
    current_meta[key]
  end
end
