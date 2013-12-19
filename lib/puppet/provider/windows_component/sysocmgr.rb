Puppet::Type.type(:windows_component).provide(:sysocmgr) do

  # This is a class method in order to be easily mocked in the spec tests.
  # It's also shamelessly hacked from puppetlabs/registry
  def self.initialize_system_api
    if Puppet.features.microsoft_windows?
      begin
        require 'win32/registry'
        require 'win32ole'
      rescue LoadError => exc
        msg = "Could not load the required win32/registry library [#{exc.message}]"
        Puppet.err msg
        error = Puppet::Error.new(msg)
        error.set_backtrace exc.backtrace
        raise error
      end
    end
  end

  def create_answer_file(component,state,tmpdir="#{Puppet[:vardir]}/windows_component_temp",filename="#{resource[:name]}_answers.txt")
    FileUtils::mkdir_p tmpdir
    content = "[Component]\r\n#{component} = #{state}"
    fileloc = "#{tmpdir}/#{filename}"
    begin
      File.write(fileloc,content)
    rescue exc
      msg = "Failed to write answers file for Windows_component[#{resource[:name]} at #{fileloc}"
      Puppet.err msg
      error = Puppet::Error.new(msg)
      error.set_backtrace exc.backtrace
      raise error
    end

    fileloc
  end


  def exists?
    reg_type = Win32::Registry::KEY_READ | 0x100 # because ruby on windows is confused by different architectures
    component_key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OC Manager\Subcomponents'
    Puppet.debug "Checking for HKLM\\#{component_key}\\#{resource[:name]} to see if component is present"
    Win32::Registry::HKEY_LOCAL_MACHINE.open(component_key, reg_type) do |reg|
      begin
        reg.read_i(resource[:name]) == 1
      rescue Win32::Registry::Error
        Puppet.err "#{resource[:name]} is not an available windows component"
        raise
      end
    end
  end

  #If another instance of sysocmgr is running, Windows helpfully displays a graphical
  #error message and hangs forever on user input. @#%^ you, Windows.
  def check_proc process
    procs = WIN32OLE.connect("winmgmts:\\\\.")
    procs.InstancesOf('win32_process').each do |p|
      return true if p.name.to_s.downcase.chomp == process.chomp
    end
    false
  end

  # Yes, what you are seeing here is real. You must edit the registry to set a source path.
  def media_source_path= source, sp
    reg_type = Win32::Registry::KEY_READ | 0x100 # because windows is confused by different architectures
    Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Microsoft\Windows\CurrentVersion\Setup',reg_type) do |reg|
      reg['ServicePackSourcePath'] = sp
      reg['SourcePath'] = source
    end
  end

  def manage_component action
    # Store the old paths, since we may need to change them
    reg_type = Win32::Registry::KEY_READ | 0x100 # because windows is confused by different architectures
    old_source_path = ''
    old_sp_path = ''
    Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Microsoft\Windows\CurrentVersion\Setup',reg_type) do |reg|
      old_sp_path = reg['ServicePackSourcePath']
      old_source_path = reg['SourcePath']
    end

    state =  (action == 'add') ? 'on' : 'off'
    answer_file = create_answer_file(resource[:name],state)
    reboot_flag = resource[:reboot] ? '' : '/r'
    command = ['c:\WINDOWS\system32\sysocmgr.exe','/i:c:\WINDOWS\inf\sysoc.inf','/f','/q',reboot_flag,"/u:#{answer_file}"]


    new_source = resource[:source_path] == nil ? old_source_path : resource[:source_path]
    new_sp = resource[:source_sp_path] == nil ? old_sp_path : resource[:source_sp_path]
    media_source_path = new_source, new_sp

    #Be warned the race condition in this check
    # (another sysocmgr starts after the check, but before the execution)
    if check_proc 'sysocmgr.exe'
      media_source_path = old_source_path, old_sp_path
      raise Puppet::Error.new('Could not execute sysocmgr. Another instance is already running.')
    else
      return_code = Puppet::Util::Execution.execute command
      if return_code != 0
        media_source_path = old_source_path, old_sp_path
        raise Puppet::Error.new("Failed to execute #{command.join(' ')}.")
      end
    end
    media_source_path = old_source_path, old_sp_path
  end

  def create
    Puppet.debug "Installing #{resource[:name]} component"
    manage_component 'add'
  end

  def destroy
    Puppet.notice "Removing #{resource[:name]} component"
    manage_component 'remove'
  end

end
