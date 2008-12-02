require 'htmlentities'
require 'net/http'
require 'cgi'
require 'json'

# ActsAsI18nUi

module ActsAsI18nUI
  
  def self.included(base)
    base.extend(ClassMethods)
  end
  
  module ClassMethods
    def acts_as_i18n_ui
      include ActsAsI18nUI::InstanceMethods
    end
  end
  
  module InstanceMethods
 
    # List of translations aplying filters
    def index
      set_params
      @translations = load_translations( @locale, @base_locale, @status, @scope ).sort
      render :template => "i18n_ui/index", :layout => "i18n_ui"
    end
    
    # Edit a translation 
    def edit
      set_params
      @translations = load_translations( @locale, @base_locale, @status, @scope )
      if @translations[params[:key]]
        render :partial => "i18n_ui/edit", :layout => nil
      else
        render :text => "Translation key does not exist anymore"
      end
    end
    
    # Update a translation
    def update
      set_params
      value = nil
      case params[:type]
        when "string"
          if params[:value].is_a? String
            value = params[:value]
          end
        when "array"
          if params[:value].is_a?(Hash)
            value = []
            params[:value].each { |k,v| value[k.to_i]=v }
          end
        when "hash"
          if params[:value].is_a?(Hash)
            value = params[:value]
          end
        when "bool"
          if params[:value] == "true"
            value = true
          elsif params[:value == "false"]
            value = false
          end
        else
      end
  
      update_translation(params[:key], value, @locale ) unless value.nil?
      show_translation
    end
    
    
    # Cancel edit and show back translation
    def cancel
      set_params
      show_translation
    end
    
    # Translates a string from base_locale to locale
    def translate_google
      set_params
      result = send_translate_google_api( params[:value], params[:locale], params[:base_locale] )
      
      unless result.nil?
        render :text => result
      else
        render :text => "error translating"
      end
    end
    
    # Creates a new locale file if it doesn't exist
    def create_locale
      set_params
      create_locale_file( params[:locale], params[:locale_name] )
      redirect_to  :action => "index"
    end
  
  private
  
    # Load translations and render a translation for a single key
    def show_translation
      @translations = load_translations( @locale, @base_locale )
      render :partial => "i18n_ui/translation_body", :locals => { :key => params[:key], :tr => @translations[params[:key]]}, :layout => nil
    end
  
    # Set instance vars from params
    def set_params
      @locale = params[:locale] || "en"
      @base_locale = params[:base_locale] || "en"
      @status = params[:status] || "all"
      @scope = params[:scope] || ""
      @languages = []
      @files = nil
    end
    
    # Update a translation. Creates file if doesn't exist.
    def update_translation( key, value, locale )
      
      # lock file
      filename = File::join RAILS_ROOT, "config/locales", File::basename( locale + ".yml" )
      if( File.exists? filename )
        file = File.new( filename, "r+")
      else
        file = File.new( filename, "w+" ) 
      end
      
      file.flock( File::LOCK_EX )
      
      begin 
        # read project locale file
        data = YAML.load( file )
        unless data.is_a? Hash 
          I18n.load_path << filename
          data = { locale => {} } unless data   
        end
        
  
        tmp = data
        
        # create middle hash keys as needed
        key = locale + "." + key
        keys = key.split(/\./)
        base_key = keys.pop
        
        while tmpkey = keys.shift
          unless tmp[tmpkey].class == Hash
            tmp[tmpkey] = {}
          end
          tmp = tmp[tmpkey]
        end
        
        # update or create value
        tmp[base_key] = value
    
        # save file
        file.truncate( 0 )
        file.rewind
        file.write( data.to_yaml )
      ensure
        # unlock and close file
        file.flock( File::LOCK_UN )
        file.close
      end
      
      I18n.reload!
            
    end
  
    # Raw loading of translation files (requires Simple UI18n backend)
    def load_files
      files = []
      translations = {}
      globals = {}
      I18n.load_path.each do |file|
        data = YAML.load_file(file)
        
        # Try to identify type from file's path name
        # TODO: Try to find a use for that
        case file
          when /\/gems\/activesupport-(.*)\/lib\/active_support\/locale\//:
            type = "ActiveSupport"
          when /\/gems\/activerecord-(.*)\/lib\/active_record\/locale\//:
            type = "ActiveRecord"
          when /\/gems\/actionpack-(.*)\/lib\/action_view\/locale\//:
            type = "ActionView"
          else
            type = "file"
        end
  
        data.keys.collect do |locale|
          files << { :locale => locale, :filename => file, :type => type } 
          locale = locale.to_sym
          # Mix in (from simpe I18n backend)
          translations[locale] ||= {}
          sdata = deep_symbolize_keys(data)
          merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
          translations[locale].merge!(sdata[locale], &merger)
          # Build global translation keys from all locales
          globals.merge!(sdata[locale],&merger)
        end
      end
  
      return {
        :files => files,
        :translations => translations,
        :globals => globals,
      }
      
      return files
    end
    
    # from simple I18n backend
    def deep_symbolize_keys(hash)
      hash.inject({}) { |result, (key, value)|
        value = deep_symbolize_keys(value) if value.is_a? Hash
        result[(key.to_sym rescue key) || key] = value
        result
      }
    end
    
    # Converts a hash to key values ({a=> { b=> { c => d }}} = "a.b.c" => d)
    def scopize(hash, base=nil, options = {})
      
      options ||= {}
      options[:plurals] = true if options[:plurals].nil?
      
      items ||= {}
      hash.each do |key,value|
        name = base || ""
        name += "." if base
        name += key.to_s
        
        if Hash === value
          do_scopize = true        
          if options[:plurals] 
            if value.length > 1 and value.has_key?( :other ) and ( value.has_key?( :one ) or value.has_key?( :zero ))
              items[name] = value
              do_scopize = false
            end
          end
          items.merge! scopize( value, name, options ) if do_scopize
        else 
          items[name] = value
        end
      end
      return items
    end
  
    # Process translation files and build list of keys using a locale and a base_locale
    def load_translations( locale, base_locale="en", type="all", scope="" )
      
      @files ||= load_files
      @languages = @files[:translations].keys.sort {|x,y| x.to_s <=> y.to_s }
      
      # Convert hash to scope string
      global = scopize( @files[:globals] )
      base = scopize( @files[:translations][base_locale.to_sym] )
      dest = scopize( @files[:translations][locale.to_sym] )
      translation = {}
      
      reg = Regexp.new( '^' + Regexp.escape( scope ))
      
      # Process all keys from all locales
      global.keys.each do |key| 
        if((type == "all") or (type=="untranslated" and dest[key].nil?) or (type == "translated" and not ( dest[key].nil? )))
          if scope.empty? or key.match( reg )
            case base[key]
              when Hash
                value_type = "hash"
              when Array
                value_type = "array"
              when TrueClass, FalseClass
                value_type = "bool"
              else
                value_type = "string"
            end
            
            translation[key] = { 
              :base => base[key].nil? ? "Not translated in base [#{base_locale}]" : base[key],
              :value => dest[key],
              :type => value_type,
            }
          end
        end
      end
  
      return translation
    end
  
    # Translate string using Google Translate API 
    def send_translate_google_api(value, locale, base_locale, options = {} )
      # Init params
      str = nil
      options ||= {}
      options[:decode] = true if options[:decode].nil?
      
      uri = URI.parse("http://ajax.googleapis.com/ajax/services/language/translate")
      
      begin 
        # Build parameters and uriencode
        params = { 
          :langpair => "#{base_locale[0..1]}|#{locale[0..1]}", 
          :q => value,
          :v => 1.0 
        }.map { |k,v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
    
        # Send request to google
        str = Net::HTTP.get(uri.host, "#{uri.path}?#{params}")
        
        # Parse result
        str = JSON.parse( str )['responseData']['translatedText']
        str = HTMLEntities.new.decode( str ) if options[:decode]
      rescue Exception => e 
        str = "error: " + e.to_s
      end
      
      return str
    end
    
    def create_locale_file( locale, locale_name )
      update_translation( "locale_name", locale_name, locale )
    end
  end
end