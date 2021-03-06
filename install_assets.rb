##### Install procedure taken from active_scaffold
#
# Workaround a problem with script/plugin and http-based repos.
# See http://dev.rubyonrails.org/ticket/8189
Dir.chdir(Dir.getwd.sub(/vendor.*/, '')) do

##
## Copy over asset files (javascript/css/images) from the plugin directory to public/
##

def copy_files(source_path, destination_path, directory)
  source, destination = File.join(directory, source_path), File.join(Rails.root, destination_path)
  FileUtils.mkdir(destination) unless File.exist?(destination)
  FileUtils.cp_r(Dir.glob(source+'/*.*'), destination)
end

directory = File.dirname(__FILE__)

copy_files("/files/public/images/i18n_ui", "/public/images/i18n_ui", directory)
copy_files("/files/public/stylesheets/i18n_ui", "/public/stylesheets/i18n_ui", directory)
copy_files("/files/app/views/i18n_ui", "/app/views/i18n_ui", directory)
copy_files("/files/app/views/layouts", "/app/views/layouts", directory)

end