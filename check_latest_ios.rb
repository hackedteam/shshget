def check_latest_ios(phone_ver, build_ver)
  uri = URI('http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStore.woa/wa/com.apple.jingle.appserver.client.MZITunesClientCheck/version')
  res = Net::HTTP.get(uri)
  versions = Plist::parse_xml(res)

  ver = ""

  v = versions['MobileDeviceSoftwareVersionsByVersion']['9']['MobileDeviceSoftwareVersions'][phone_ver][build_ver]
  if v.has_key?("SameAs")
    bid = v["SameAs"]
    ver = versions['MobileDeviceSoftwareVersionsByVersion']['9']['MobileDeviceSoftwareVersions'][phone_ver][bid]['Restore']['ProductVersion']
  else
    ver = versions['MobileDeviceSoftwareVersionsByVersion']['9']['MobileDeviceSoftwareVersions'][phone_ver][build_ver]['Restore']['ProductVersion']
  end 

  puts phone_ver + "(" + build_ver + ") last ver: " + ver 
  return ver.gsub(".", "").to_i
end

# 5.0.1
last_ios           = 500
# 4.3.3
last_supported_ios = 433

devices = Psych.load(File.open("devices.yaml"))
while true do
  devices.each_pair do |k, v|
    ver   = v['ver']
    build = v['build']

    last_ios_found = check_latest_ios(ver, build)
    # up to last_supported_ios
    if ver == "iPhone1,2"
      if last_supported_ios < last_ios_found
        puts "[-] Found a new version"
        `./shshget.rb #{last_ios_found}`
      end
    else
      if last_ios < last_ios_found
        puts "[-] Found a new version"
        `./shshget.rb #{last_ios_found}`
      end
    end
  end

  # sleep 8h
  sleep(28800)
end
