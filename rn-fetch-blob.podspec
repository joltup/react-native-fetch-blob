Pod::Spec.new do |s|
  s.name             = "rn-fetch-blob"
  s.version          = "0.10.6"
  s.summary          = "A project committed to make file acess and data transfer easier, effiecient for React Native developers."
  s.requires_arc = true
  s.license      = 'MIT'
  s.homepage     = 'n/a'
  s.source       = { :git => "https://github.com/joltup/rn-fetch-blob", :tag => 'v0.10.10'}
  s.author       = 'Joltup'
  s.source_files = 'ios/**/*.{h,m}'
  s.platform     = :ios, "8.0"
  s.dependency 'React-Core'
end
