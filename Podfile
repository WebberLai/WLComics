use_frameworks!

target 'WLComics' do
  pod 'Swift8ComicSDK', :git => 'https://github.com/RayTW/Swift8ComicSDK.git'
  pod 'Kingfisher'
  pod 'HUD', '~>2.0.1'
end

# if use Xcode9(Swift4.0)
post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['SWIFT_VERSION'] = '3.2'
        end
    end
end
