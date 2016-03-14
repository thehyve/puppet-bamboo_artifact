Puppet::Type.newtype(:bamboo_artifact) do

  ensurable

  def self.mandatory_property(prop_clazz)
    prop_clazz.class_eval do
      isrequired
      defaultto :absent
      validate do |val|
        fail "#{name} must be given in #{resource}" if val == :absent
      end
    end
  end

  type_class = self

  newproperty :server do
    type_class.mandatory_property self
  end

  newproperty :plan do
    type_class.mandatory_property self
  end

  newproperty :build do
    desc 'The build number, or "latest" for the latest build. ' \
         'Defaults to \"latest\".'

    defaultto :latest

    munge do |value|
      return value.to_i if value.to_s =~ /\A\d+\z/
      return :latest if value.to_s == 'latest'
      fail "Build must be a number or 'latest'"
    end

    def insync?(is)
      return super(is) if should != :latest

      [is.to_i, :skip].include? provider.latest_build
    end
  end

  newproperty :artifact_path do
    desc 'Path to the artifact on the server, including shared/ if appropriate.'

    type_class.mandatory_property self
  end

  newparam :path do
    desc 'Path where the artifact will be downloaded to (incl. file).'

    validate do |val|
      fail "'#{val}' must be absolute" unless Pathname.new(val).absolute?
    end

    isnamevar
  end

  newparam :user do
    desc 'The owner of the file to be downloaded.'
  end

  def autonotify(rel_catalog = nil)
    reqs = super

    rel_catalog ||= catalog

    file_params = {
      ensure:  self[:ensure] == :present ? 'file' : 'absent',
      catalog: catalog,
    }

    file_params[:owner] = self[:user] if self[:user]

    meta_file_res = Puppet::Type.type(:file).new(file_params.merge({ title: meta_file, }))

    reqs << Puppet::Relationship.new(self, meta_file_res)

    unless file_res = rel_catalog.resource(:file, self[:path])
      file_res = Puppet::Type.type(:file).new(file_params.merge({ title:   self[:path], }))
    end

    reqs << Puppet::Relationship.new(self, file_res)
  end

  autorequire(:user) do
    [self[:user]]
  end

  def meta_file
    "#{File.dirname(self[:path])}#{File::SEPARATOR}.#{File.basename(self[:path])}-meta.yaml"
  end
end
