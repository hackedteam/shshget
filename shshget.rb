#!/usr/bin/env ruby

#
# Jan 3 2012
#
# Pretty hackish
# Will make at least 3 requests every 8 hours
# Needs a bit of cleaning and some heavy testing on all
# the different kind of idevices
#
# Whenever there's a new device, add it to devices.yaml
#
# rev
#

require 'net/http'
require 'objspace'
require 'plist'
require 'psych'
require 'cgi'
require 'logger'

def log(level, msg)
  log_file = "shsh.log"
  log = Logger.new(File.open(log_file, "a+"))
  log.level = Logger::DEBUG
  log.send(level, msg)
  log.close
end

def build_plist_for_manifest(manifest, ecid)
  obj = {}
  obj['@APTicket'] = true
  obj['@BBTicket'] = true
  obj['ApNonce'] = 'MTAwMQ==' # 1001 base64
  obj['@HostIpAddress'] = '192.168.0.1'
  obj['@HostPlatformInfo'] = 'mac'
  obj['@Locality'] = 'en_US'
  obj['@VersionInfo'] = 'libauthinstall-68.1'
  obj['ApBoardID'] = manifest["BuildIdentities"][0]["ApBoardID"]
  obj['ApChipID'] = manifest["BuildIdentities"][0]["ApChipID"]
  obj['ApECID'] = ecid
  obj['ApProductionMode'] = true
  obj['ApSecurityDomain'] = 1
  obj['UniqueBuildID'] = manifest["BuildIdentities"][0]["UniqueBuildID"]
  #obj['UniqueBuildID'] = 'bZ/+6gi44GhO84bgFlIkxw0V+d8='

  t = manifest["BuildIdentities"][0]["Manifest"]["AppleLogo"]
  t.delete("Info")
  obj['AppleLogo'] = t

  #t = manifest["BuildIdentities"][0]["Manifest"]["BasebandFirmware"]
  #t.delete("Info")
  #obj['BasebandFirmware'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["BatteryCharging"]
  t.delete("Info")
  obj['BatteryCharging'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["BatteryCharging0"]
  t.delete("Info")
  obj['BatteryCharging0'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["BatteryCharging1"]
  t.delete("Info")
  obj['BatteryCharging1'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["BatteryFull"]
  t.delete("Info")
  obj['BatteryFull'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["BatteryLow0"]
  t.delete("Info")
  obj['BatteryLow0'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["BatteryLow1"]
  t.delete("Info")
  obj['BatteryLow1'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["BatteryPlugin"]
  t.delete("Info")
  obj['BatteryPlugin'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["DeviceTree"]
  t.delete("Info")
  obj['DeviceTree'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["KernelCache"]
  t.delete("Info")
  obj['KernelCache'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["LLB"]
  t.delete("Info")
  obj['LLB'] = t

  #t = manifest["BuildIdentities"][0]["Manifest"]["NeedService"]
  #t.delete("Info")
  #obj['NeedService'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["RecoveryMode"]
  t.delete("Info")
  obj['RecoveryMode'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["RestoreDeviceTree"]
  t.delete("Info")
  obj['RestoreDeviceTree'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["RestoreKernelCache"]
  t.delete("Info")
  obj['RestoreKernelCache'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["RestoreLogo"]
  t.delete("Info")
  obj['RestoreLogo'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["RestoreRamDisk"]
  t.delete("Info")
  obj['RestoreRamDisk'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["iBEC"]
  t.delete("Info")
  obj['iBEC'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["iBSS"]
  t.delete("Info")
  obj['iBSS'] = t

  t = manifest["BuildIdentities"][0]["Manifest"]["iBoot"]
  t.delete("Info")
  obj['iBoot'] = t

  # serialize
  plist = obj.to_plist
  plist_data = plist.dump.gsub("\"<", "<").gsub("\\n\"", "").gsub("\\n", "\n").gsub("\\t", "\t").gsub("\\", "")

  return plist_data
end

def request_shsh(plist_data)
  uri = URI('http://gs.apple.com.akadns.net/TSS/controller?action=2')

  req = Net::HTTP::Post.new(uri.request_uri)
  req["Accept"] = "*/*"
  req["Cache-Control"] = "no-cache"
  req["Content-type"] = "text/xml; charset=\"utf-8\""
  req["User-Agent"] = "InetURL/1.0"
  req["Host"] = "gs.apple.com.akadns.net"
  req["Content-Length"] = plist_data.bytesize
  req.body = plist_data

  res = Net::HTTP.start('gs.apple.com.akadns.net', '80') { |http|
    http.request(req)
  }

  return res.response
end

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

  entry = (phone_ver + "(" + build_ver + ") last ver: " + ver)
  log(:info, entry)
  return ver
end

manifest_dir = "manifests/"
ecid_dir = "ecids/"

while true do
  File.open("devices.yaml", "r+") { |f|
    devices = Psych.load(f.read)
    index = 0

    devices.each_pair do |k, v|
      ecid      = v['ecid']
      phone_ver = v['phone_ver']
      build     = v['build']
      last_shsh = v['last_shsh']

      last_ios_ver_avail = check_latest_ios(phone_ver, build)
      entry = "Last ios version for " + phone_ver + "(" + build + ") is " + last_ios_ver_avail
      log(:info, entry)

      if last_shsh < last_ios_ver_avail
        # Update devices.yaml for latest ios shsh
        dev = "Device " + index.to_s
        devices[dev]['last_shsh'] = last_ios_ver_avail

        manifest_path = manifest_dir + "BuildManifest-" + phone_ver.downcase + "-" + last_ios_ver_avail + ".plist.gz"
        entry = "Manifest Path: " + manifest_path
        log(:info, entry)

        manifest_content = ''
        Zlib::GzipReader.open(manifest_path) { |gz|
          manifest_content = gz.read
        }

        manifest = Plist::parse_xml(manifest_content)
        plist_data = build_plist_for_manifest(manifest, ecid)

        res = request_shsh(plist_data)
        # Response will be in the form STATUS=0&MESSAGE=SUCCESS&REQUEST_STRING=
        d = CGI::parse(res.body)

        if d['MESSAGE'][0] == "SUCCESS"
          entry = "Correctly retrieved shsh for " + phone_ver + "(" + build + ")"
          log(:info, entry)

          ecid_path = ecid_dir + ecid.to_s + "-" + phone_ver + "-" + last_ios_ver_avail + ".shsh"
          File.open(ecid_path, "w") { |f|
            f.write(d['REQUEST_STRING'][0])
          }
        else
          entry = "Error while retrieving shsh for " + phone_ver + "(" + build + ")"
          log(:fatal, entry)
          entry = "Response: " + res.body
          log(:debug, entry)
        end
      end

      index += 1
    end

    # update yaml for latest ios shsh
    f.truncate(0)
    f.seek(0)
    f.write(devices.to_yaml)
    f.close()
  }

  # sleep 8h
  sleep(28800)
end
