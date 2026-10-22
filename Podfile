use_frameworks!

platform :ios, '14.0'
target 'WLComics' do
  pod 'Kingfisher'
  pod 'SVProgressHUD'

  target 'WLComicsTests' do
    inherit! :search_paths
  end
end

target 'WLTVComics' do
  platform :tvos, '16.0'
  pod 'Kingfisher'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      if config.build_settings['SDKROOT'] == 'appletvos' ||
         target.name.include?('tvos') || target.name.include?('TV')
        config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '16.0'
      else
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      end
    end
  end
end
