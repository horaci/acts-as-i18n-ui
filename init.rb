# Include hook code here

unless Rails::VERSION::MAJOR == 2 && Rails::VERSION::MINOR >= 2
  raise "This version of ActiveScaffold requires Rails 2.2 or higher.  Please use an earlier version."
end


begin
  require File.dirname(__FILE__) + '/install_assets'
rescue
  raise $! unless Rails.env == 'production'
end


ActionController::Base.class_eval do
  include ActsAsI18nUI
end