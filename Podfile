platform :ios, '17.0'
use_frameworks!

# Specify the Xcode project path
project 'ProjectUnmute ProjectUnmute/ProjectUnmute ProjectUnmute.xcodeproj'

target 'ProjectUnmute ProjectUnmute' do
  pod 'MediaPipeTasksVision'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Enable modules (C and Objective-C)
      config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
      # Ensure bitcode is disabled (deprecated)
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      # Exclude from Mac Catalyst builds
      config.build_settings['SUPPORTS_MACCATALYST'] = 'NO'
    end
  end
end
