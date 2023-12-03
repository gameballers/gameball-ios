#
# Be sure to run `pod lib lint GameBallSDK.podspec' to ensure this is a
# valid spec before submitting.

Pod::Spec.new do |s|
  
  #1
  s.platform = :ios
  s.name  = 'Gameball'
  s.ios.deployment_target = '11.0'
  s.summary = 'Gameball SDK for iOS.'
  s.requires_arc = true

  # 2
  s.version    = '2.0.8'

  #3
  s.license          = { :type => 'MIT', :file => 'LICENSE' }

  #4
  s.author           = { 'Gameball' => 'support@gameball.co' }

  
  # 5 - Replace this URL with your own GitHub page's URL (from the address bar)
  s.homepage  = "https://github.com/gameballers/gameball-ios"
  
  
  #7
  s.source           = { :git => "https://github.com/gameballers/gameball-ios.git", :tag => s.version}
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'
  s.readme = "https://github.com/gameballers/gameball-ios/blob/master/README.md"


  # 7
  s.framework = 'UIKit'
  s.static_framework = true
  s.dependency 'Firebase'
  s.dependency 'Firebase/Core'
  s.dependency 'Firebase/Messaging'
  s.dependency 'Firebase/Analytics'

  s.pod_target_xcconfig = {
    
    "ENABLE_BITCODE" => 'NO',
    
    "OTHER_LDFLAGS" => '$(inherited) -framework "GameBallSDK"'
  }
  
  
  #8
  s.source_files = 'Sources/Gameball/**/*.{swift}'

  # 9
  s.resources = 'Sources/Gameball/**/*.{png,jpeg,jpg,storyboard,xib,xcassets,strings,otf,ttf}', 'Sources/Gameball/Resources/GoogleService-Info.plist'
  
  # 10
  s.swift_version = '4.2'
end
