module MCollective
  # A class that helps creating data description language files
  # for plugins.  You can define meta data, actions, input and output
  # describing the behavior of your agent or other plugins
  #
  # Later you can access this information to assist with creating
  # of user interfaces or online help
  #
  # A sample DDL can be seen below, you'd put this in your agent
  # dir as <agent name>.ddl
  #
  #    metadata :name        => "SimpleRPC Service Agent",
  #             :description => "Agent to manage services using the Puppet service provider",
  #             :author      => "R.I.Pienaar",
  #             :license     => "GPLv2",
  #             :version     => "1.1",
  #             :url         => "http://mcollective-plugins.googlecode.com/",
  #             :timeout     => 60
  #
  #    action "status", :description => "Gets the status of a service" do
  #       display :always
  #
  #       input :service,
  #             :prompt      => "Service Name",
  #             :description => "The service to get the status for",
  #             :type        => :string,
  #             :validation  => '^[a-zA-Z\-_\d]+$',
  #             :optional    => true,
  #             :maxlength   => 30
  #
  #       output :status,
  #              :description => "The status of service",
  #              :display_as  => "Service Status"
  #   end
  class DDL
    attr_reader :meta, :entities, :pluginname, :plugintype

    def initialize(plugin, plugintype=:agent, loadddl=true)
      @entities = {}
      @meta = {}
      @config = Config.instance
      @pluginname = plugin
      @plugintype = plugintype.to_sym

      # used to track if the method_missing that handles the
      # aggregate functions should do so or not
      @process_aggregate_functions = nil

      loadddlfile if loadddl
    end

    def loadddlfile
      if ddlfile = findddlfile
        instance_eval(File.read(ddlfile), ddlfile, 1)
      else
        raise("Can't find DDL for #{@plugintype} plugin '#{@pluginname}'")
      end
    end

    def findddlfile(ddlname=nil, ddltype=nil)
      ddlname = @pluginname unless ddlname
      ddltype = @plugintype unless ddltype

      @config.libdir.each do |libdir|
        ddlfile = File.join([libdir, "mcollective", ddltype.to_s, "#{ddlname}.ddl"])

        if File.exist?(ddlfile)
          Log.debug("Found #{ddlname} ddl at #{ddlfile}")
          return ddlfile
        end
      end
      return false
    end

    # Registers meta data for the introspection hash
    def metadata(meta)
      [:name, :description, :author, :license, :version, :url, :timeout].each do |arg|
        raise "Metadata needs a :#{arg} property" unless meta.include?(arg)
      end

      @meta = meta
    end

    # Creates the definition for a data query
    #
    #    dataquery :description => "Match data using Augeas" do
    #       input  :query,
    #              :prompt      => "Matcher",
    #              :description => "Valid Augeas match expression",
    #              :type        => :string,
    #              :validation  => /.+/,
    #              :maxlength   => 50
    #
    #       output :size,
    #              :description => "The amount of records matched",
    #              :display_as => "Matched"
    #    end
    def dataquery(input, &block)
      raise "Data queries need a :description" unless input.include?(:description)
      raise "Data queries can only have one definition" if @entities[:data]

      @entities[:data]  = {:description => input[:description],
                           :input => {},
                           :output => {}}

      @current_entity = :data
      block.call if block_given?
      @current_entity = nil
    end

    # Creates the definition for new discovery plugins
    #
    #    discovery do
    #       capabilities [:classes, :facts, :identity, :agents, :compound]
    #    end
    def discovery(&block)
      raise "Discovery plugins can only have one definition" if @entities[:discovery]

      @entities[:discovery] = {:capabilities => []}

      @current_entity = :discovery
      block.call if block_given?
      @current_entity = nil
    end

    # records valid capabilities for discovery plugins
    def capabilities(caps)
      raise "Only discovery DDLs have capabilities" unless @plugintype == :discovery

      caps = [caps].flatten

      raise "Discovery plugin capabilities can't be empty" if caps.empty?

      caps.each do |cap|
        if [:classes, :facts, :identity, :agents, :compound].include?(cap)
          @entities[:discovery][:capabilities] << cap
        else
          raise "%s is not a valid capability, valid capabilities are :classes, :facts, :identity, :agents and :compound" % cap
        end
      end
    end

    # Creates the definition for an action, you can nest input definitions inside the
    # action to attach inputs and validation to the actions
    #
    #    action "status", :description => "Restarts a Service" do
    #       display :always
    #
    #       input  "service",
    #              :prompt      => "Service Action",
    #              :description => "The action to perform",
    #              :type        => :list,
    #              :optional    => true,
    #              :list        => ["start", "stop", "restart", "status"]
    #
    #       output "status",
    #              :description => "The status of the service after the action"
    #
    #    end
    def action(name, input, &block)
      raise "Action needs a :description property" unless input.include?(:description)

      unless @entities.include?(name)
        @entities[name] = {}
        @entities[name][:action] = name
        @entities[name][:input] = {}
        @entities[name][:output] = {}
        @entities[name][:display] = :failed
        @entities[name][:description] = input[:description]
      end

      # if a block is passed it might be creating input methods, call it
      # we set @current_entity so the input block can know what its talking
      # to, this is probably an epic hack, need to improve.
      @current_entity = name
      block.call if block_given?
      @current_entity = nil
    end

    # Registers an input argument for a given action
    #
    # See the documentation for action for how to use this
    def input(argument, properties)
      raise "Cannot figure out what entity input #{argument} belongs to" unless @current_entity

      entity = @current_entity

      raise "The only valid input name for a data query is 'query'" if @plugintype == :data && argument != :query

      if @plugintype == :agent
        raise "Input needs a :optional property" unless properties.include?(:optional)
      end

      [:prompt, :description, :type].each do |arg|
        raise "Input needs a :#{arg} property" unless properties.include?(arg)
      end

      @entities[entity][:input][argument] = {:prompt => properties[:prompt],
                                             :description => properties[:description],
                                             :type => properties[:type],
                                             :optional => properties[:optional]}

      case properties[:type]
        when :string
          raise "Input type :string needs a :validation argument" unless properties.include?(:validation)
          raise "Input type :string needs a :maxlength argument" unless properties.include?(:maxlength)

          @entities[entity][:input][argument][:validation] = properties[:validation]
          @entities[entity][:input][argument][:maxlength] = properties[:maxlength]

        when :list
          raise "Input type :list needs a :list argument" unless properties.include?(:list)

          @entities[entity][:input][argument][:list] = properties[:list]
      end
    end

    # Registers an output argument for a given action
    #
    # See the documentation for action for how to use this
    def output(argument, properties)
      raise "Cannot figure out what action input #{argument} belongs to" unless @current_entity
      raise "Output #{argument} needs a description argument" unless properties.include?(:description)
      raise "Output #{argument} needs a display_as argument" unless properties.include?(:display_as)

      action = @current_entity

      @entities[action][:output][argument] = {:description => properties[:description],
                                              :display_as  => properties[:display_as],
                                              :default     => properties[:default]}
    end

    # Sets the display preference to either :ok, :failed, :flatten or :always
    # operates on action level
    def display(pref)
      # defaults to old behavior, complain if its supplied and invalid
      unless [:ok, :failed, :flatten, :always].include?(pref)
        raise "Display preference #{pref} is not valid, should be :ok, :failed, :flatten or :always"
      end

      action = @current_entity
      @entities[action][:display] = pref
    end

    # Calls the summarize block defined in the ddl. Block will not be called
    # if the ddl is getting processed on the server side. This means that
    # aggregate plugins only have to be present on the client side.
    #
    # The @process_aggregate_functions variable is used by the method_missing
    # block to determine if it should kick in, this way we very tightly control
    # where we activate the method_missing behavior turning it into a noop
    # otherwise to maximise the chance of providing good user feedback
    def summarize(&block)
      unless @config.mode == :server
        @process_aggregate_functions = true
        block.call
        @process_aggregate_functions = nil
      end
    end

    # Sets the aggregate array for the given action
    def aggregate(function, format = {:format => nil})
      raise(DDLValidationError, "Formats supplied to aggregation functions should be a hash") unless format.is_a?(Hash)
      raise(DDLValidationError, "Formats supplied to aggregation functions must have a :format key") unless format.keys.include?(:format)
      raise(DDLValidationError, "Functions supplied to aggregate should be a hash") unless function.is_a?(Hash)

      unless (function.keys.include?(:args)) && function[:args]
        raise DDLValidationError, "aggregate method for action '%s' missing a function parameter" % entities[@current_entity][:action]
      end

      entities[@current_entity][:aggregate] ||= []
      entities[@current_entity][:aggregate] << (format[:format].nil? ? function : function.merge(format))
    end

    def template_for_plugintype
      case @plugintype
        when :agent
          return "rpc-help.erb"
        else
          return "#{@plugintype}-help.erb"
      end
    end

    # Generates help using the template based on the data
    # created with metadata and input.
    #
    # If no template name is provided one will be chosen based
    # on the plugin type.  If the provided template path is
    # not absolute then the template will be loaded relative to
    # helptemplatedir configuration parameter
    def help(template=nil)
      template = template_for_plugintype unless template
      template = File.join(@config.helptemplatedir, template) unless template.start_with?(File::SEPARATOR)

      template = File.read(template)
      meta = @meta
      entities = @entities

      erb = ERB.new(template, 0, '%')
      erb.result(binding)
    end

    # Returns an array of actions this agent support
    def actions
      raise "Only agent DDLs have actions" unless @plugintype == :agent
      @entities.keys
    end

    # Returns the interface for the data query
    def dataquery_interface
      raise "Only data DDLs have data queries" unless @plugintype == :data
      @entities[:data] || {}
    end

    # Returns the interface for a specific action
    def action_interface(name)
      raise "Only agent DDLs have actions" unless @plugintype == :agent
      @entities[name] || {}
    end

    def discovery_interface
      raise "Only discovery DDLs have discovery interfaces" unless @plugintype == :discovery
      @entities[:discovery]
    end

    # validate strings, lists and booleans, we'll add more types of validators when
    # all the use cases are clear
    #
    # only does validation for arguments actually given, since some might
    # be optional.  We validate the presense of the argument earlier so
    # this is a safe assumption, just to skip them.
    #
    # :string can have maxlength and regex.  A maxlength of 0 will bypasss checks
    # :list has a array of valid values
    def validate_input_argument(input, key, argument)
      case input[key][:type]
        when :string
          raise DDLValidationError, "Input #{key} should be a string for plugin #{meta[:name]}" unless argument.is_a?(String)

          if input[key][:maxlength].to_i > 0
            if argument.size > input[key][:maxlength].to_i
              raise DDLValidationError, "Input #{key} is longer than #{input[key][:maxlength]} character(s) for plugin #{meta[:name]}"
            end
          end

          unless argument.match(Regexp.new(input[key][:validation]))
            raise DDLValidationError, "Input #{key} does not match validation regex #{input[key][:validation]} for plugin #{meta[:name]}"
          end

        when :list
          unless input[key][:list].include?(argument)
            raise DDLValidationError, "Input #{key} doesn't match list #{input[key][:list].join(', ')} for plugin #{meta[:name]}"
          end

        when :boolean
          unless [TrueClass, FalseClass].include?(argument.class)
            raise DDLValidationError, "Input #{key} should be a boolean for plugin #{meta[:name]}"
          end

        when :integer
          raise DDLValidationError, "Input #{key} should be a integer for plugin #{meta[:name]}" unless argument.is_a?(Fixnum)

        when :float
          raise DDLValidationError, "Input #{key} should be a floating point number for plugin #{meta[:name]}" unless argument.is_a?(Float)

        when :number
          raise DDLValidationError, "Input #{key} should be a number for plugin #{meta[:name]}" unless argument.is_a?(Numeric)
      end

      return true
    end

    # Helper to use the DDL to figure out if the remote call to an
    # agent should be allowed based on action name and inputs.
    def validate_rpc_request(action, arguments)
      raise "Can only validate RPC requests against Agent DDLs" unless @plugintype == :agent

      # is the action known?
      unless actions.include?(action)
        raise DDLValidationError, "Attempted to call action #{action} for #{@pluginname} but it's not declared in the DDL"
      end

      input = action_interface(action)[:input]

      input.keys.each do |key|
        unless input[key][:optional]
          unless arguments.keys.include?(key)
            raise DDLValidationError, "Action #{action} needs a #{key} argument"
          end
        end

        if arguments.keys.include?(key)
          validate_input_argument(input, key, arguments[key])
        end
      end

      true
    end

    # As we're taking arguments on the command line we need a
    # way to input booleans, true on the cli is a string so this
    # method will take the ddl, find all arguments that are supposed
    # to be boolean and if they are the strings "true"/"yes" or "false"/"no"
    # turn them into the matching boolean
    def self.string_to_boolean(val)
      return true if ["true", "t", "yes", "y", "1"].include?(val.downcase)
      return false if ["false", "f", "no", "n", "0"].include?(val.downcase)

      raise "#{val} does not look like a boolean argument"
    end

    # a generic string to number function, if a number looks like a float
    # it turns it into a float else an int.  This is naive but should be sufficient
    # for numbers typed on the cli in most cases
    def self.string_to_number(val)
      return val.to_f if val =~ /^\d+\.\d+$/
      return val.to_i if val =~ /^\d+$/

      raise "#{val} does not look like a number"
    end

    # If the ddl's plugin type is 'agent' and the method name matches a
    # aggregate function, we return the function with args as a hash.
    def method_missing(name, *args, &block)
      super unless @process_aggregate_functions
      super unless is_function?(name)

      return {:function => name, :args => args}
    end

    # Checks if a method name matches a aggregate plugin.
    # This is used by method missing so that we dont greedily assume that
    # every method_missing call in an agent ddl has hit a aggregate function.
    def is_function?(method_name)
      PluginManager.find("aggregate").include?(method_name.to_s)
    end
  end
end
