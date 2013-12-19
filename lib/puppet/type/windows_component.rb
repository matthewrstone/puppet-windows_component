Puppet::Type.newtype(:windows_component) do
  desc "Manage the state of Windows 2003 Components"

  ensurable

  newparam(:name, :namevar => true) do
    desc 'The name of the component. Must match the value in HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\Oc Manager\Subcomponents'
  end

  newparam(:reboot) do
    desc 'Whether to reboot on component (un)installation if needed'
    newvalues(:true, :false)
    defaultto :false
  end

  newparam(:source_path) do
    desc 'The media source path for component installation'
  end

  newparam(:source_sp_path) do
    desc 'The installation media source path for service packs'
  end

  #TODO add property for subcomponents
  #newproperty(:subcomponents, :array_matching => :all) do
  #end

end
