# Change MBP mid2012 WiFi region code

To solve the MBP connection to 5GHz WiFi issue (wrong region code):

1. disable System Integrity Protection(SIP)
    - reboot with cmd+R
    - run terminal
    - csrutil disable
    - reboot
2. patch kernel extension (kext)
    - sudo perl -pi -e 's|\x81\x78\x30\x6B\x10\x00\x00\x0F\x85|\x81\x78\x30\x6B\x10\x00\x00\x90\xE9|' /System/Library/Extensions/IO80211Family.kext/Contents/PlugIns/AirPortBrcm4360.kext/Contents/MacOS/AirPortBrcm4360 && sudo touch /System/Library/Extensions/ 
    - wait couple minutes (kext cache refresh) 
3. enable System Integrity Protection(SIP)
    -  reboot with Cmd+R
    -  run terminal
    -  csrutil enable
    -  reboot