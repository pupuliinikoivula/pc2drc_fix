#!/bin/bash

#key:
 #(<type>) <code or comment>
 #
 #(DESC)       Describes what a function does
 #(NOTE)       Note about a particular bit of code
 #(TODO)       Future implementation
 #(BAD)        This code is bad. Replace ASAP.
 #(UGLY)       This code is unreadable. Replace ASAP.
 #(WRKARND)    This is a workaround to some problem. Best not to touch.
 #(EXCEPT)     Error checking code
 #(UNTESTED)   Untested code
 #(CODE)       Code that's been commented out or obseleted
 #(DEBUG)      Uncomment for a verified debugging moment
 #(FIX)        Fixes a github issue
 #(SANITY)     This line has or is a sanity check
 #(CLEANUP)    This code cleans up a mess made by some previous code
 #(XXX)        Bookmark or where the dev left off aka LOOK AT ME!!
 
 
#(DESC) Template constants
SCRIPT_NAME="stage-1-kernel-patch.sh"
SCRIPT_PARENT_DIR_NAME="pc2drc"
SCRIPT_DIR=$(pwd)


#(DESC) Other constants
debug_file="$(pwd)/generated_bug_report.txt"
distro_name_pretty=$(source /etc/os-release && echo $NAME' '$VERSION_ID) #(NOTE) distro_name_pretty=Ubuntu 20.04.4 LTS (Focal Fossa)
distro_id=$(source /etc/os-release && echo $ID)
distro_version_codename=$(source /etc/os-release && echo $VERSION_CODENAME)



init () {
   #(DESC) check if user is root
    if [ `id -u` -ne 0 ]; then
        echo "Please run with: sudo -E ./${SCRIPT_NAME}"
        exit
    fi
    
   #(DESC) check if non-root user's environment variables have been passed through
    if [ $(cd $HOME/.. && pwd) != "/home" ]; then
        echo "Please run with: sudo -E ./${SCRIPT_NAME}"
        exit
    fi
    
   #(DESC) check if script is in intended directory
    if [ ${PWD##*/} != $SCRIPT_PARENT_DIR_NAME ]; then
      echo "Parent folder should be named ${SCRIPT_PARENT_DIR_NAME}. If this script isn't in its intended directory there may be problems."
      read -p "(press enter to continue)"
    fi
    
   #(DESC) check if there is a wifi interface
    if [[ $(ip link show | grep -o -m1 "\w*wl\w*") == "" ]]; then
        echo "No wireless interfaces found. Please attatch a wireless interface and try again."
        read -p "(press enter to quit)"
        exit
    fi
    
   #(DESC) check for active internet connection
    echo -e "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "An internet connection is required for this script to run. Try \`sudo service network-manager start\`"
        read -p "(press enter to quit)"
        exit
    fi
}; init #(DESC) start function immediately




#(DESC) Unloads a module's dependees, then unloads the module. 
#(NOTE) `restore_modules=$(rmmod ${module_to_unload} 2>&1 >/dev/null | grep -o -m1 "by: .*" | cut -c 5-)` should be run before this and `modprobe $resore_modules` after.
unload_modules_recursively () {
  local output=$(rmmod $@ 2>&1)
  if [[ $output =~ "by:" ]]; then
    unload_modules_recursively $(rmmod $output 2>&1 >/dev/null | grep -o -m1 "by: .*" | cut -c 5-)
  fi
  if [[ $output =~ "missing module name" ]]; then
    return 69 #(TODO) this doesn't matter, I should really check this but whatever
  fi
  sleep 1
}


#(DESC) install required packages
apt-get install git fakeroot build-essential ncurses-dev xz-utils libssl-dev bc flex libelf-dev bison dkms -y


#(DESC) Everyone wants the kernel in a different format, create those formats here.
KERNEL_VER=$(echo `uname -r` | grep -Po -m1 "[0-9]*\.[0-9]*\.[0-9]*" | head -1)
kernel_version_cdn=$(echo $KERNEL_VER | grep -Po -m1 "[0-9]*\.[0-9]*(\.[1-9]+)*" | head -1) #(DESC) cdn.kernel.org formats the kernel versions like so:  x.y.0 -> x.y   x.y.>0 -> x.y.z
kernel_version_x=$(echo $KERNEL_VER | grep -o -m1 "[0-9]*" | head -1) #(DESC) x.y.z -> x
kernel_version_y=$(echo $KERNEL_VER | grep -o -m1 "[0-9]*" | head -2 | tail -1) #(DESC) x.y.z -> y
kernel_version_z=$(echo $KERNEL_VER | grep -o -m1 "[0-9]*" | head -3 | tail -1) #(DESC) x.y.z -> z
    
    
    

cd ./kernel-patch-files

#(DESC) checks in case script has already been run
if [[ -f "./linux-${kernel_version_cdn}.tar.xz" ]] || [[ -f "./linux-${KERNEL_VER}.tar.xz" ]]; then
    echo "Kernel already downloaded, skipping download."
else
    wget https://cdn.kernel.org/pub/linux/kernel/v${kernel_version_x}.x/linux-${kernel_version_cdn}.tar.xz
fi


#(DESC) if kernel hasn't been extracted already extract kernel and rename to PATCH_KERNEL_VER if KERNEL_VER != kernel_version_cdn
if [[ -d "./linux-$KERNEL_VER" ]]; then
    echo "Kernel already decompressed, skipping extraction."
elif [[ -d "./linux-$kernel_version_cdn" ]]; then
    echo "Kernel already decompressed, not renamed. Skipping extraction and renaming."
    test -d ./linux-$kernel_version_cdn && mv ./linux-${kernel_version_cdn} ./linux-${KERNEL_VER}
elif [[ -d "./linux-$(uname -r)" ]]; then
    echo "Kernel already decompressed, not renamed. Skipping extraction and renaming."
    test -d ./linux-$(uname -r) && mv ./linux-$(uname -r) ./linux-${KERNEL_VER}
else
    echo "Extracting kernel..."
    tar xvf linux-${kernel_version_cdn}.tar.xz 2>&1 >/dev/null
    if [[ $kernel_version_cdn != $KERNEL_VER ]]; then
        test -d ./linux-${kernel_version_cdn} && mv ./linux-${kernel_version_cdn} ./linux-${KERNEL_VER}
    fi
fi

cd ..




#(NOTE) function requires that you already be in the top-level linux kernel source directory (e.g. basename $(pwd) == linux-5.11.22)
patch_kernel () {
    if ! [[ -d "./net/mac80211" ]]; then
        echo "/net/mac80211 not found in $(pwd)"
        echo "Please put your kernel folder in $(cd .. && pwd) and try again."
        read -p "(press enter to quit)"
        exit
    fi
    
    
    mac80211_dir=./net/mac80211
      
    
    cp -v /boot/config-$(uname -r) ./.config
    
    
    #(DESC) Allow us to run unsigned kernel modules
    sed -i 's/[#]*CONFIG_SYSTEM_TRUSTED_KEYS/#CONFIG_SYSTEM_TRUSTED_KEYS/g' "./.config" #(NOTE) the [#]* is there to match any # characters just in case we already ran this script.
    
    
    #(DESC) Patch mac80211 in kernel sources
    if [[ -f "./net/mac80211/README.DRC" ]]; then
        echo "Kernel sources already patched, skipping patch."
    else
        if [[ $(echo "${kernel_version_x}.${kernel_version_y}>5.11" | bc -l) == 1 ]]; then
            #(NOTE) -p1 and -p2 strip leading dirnames from the patch, ./mac80211/iface.c -p2 = iface.c   mac80211/iface.c -p1 = iface.c
            #(CODE) patch -p2 < ../../../patches/kernel_above_5_11_mac80211.patch
            echo "Using new patch!"
            patch -p2 -d "./net/mac80211" -i "${SCRIPT_DIR}/kernel-patch-files/patches/kernel_above_5_11_mac80211.patch"
        else
            #(CODE) patch -p1 < ../../../patches/mac80211.patch #add sudo if this doesn't work
            echo "Using old patch!"
            patch -p1 -d "./net/mac80211" -i "${SCRIPT_DIR}/kernel-patch-files/patches/kernel_below_5_12_mac80211.patch"
            #(CODE) patch -p2 -d "./linux-${KERNEL_VER}/net/mac80211" -i "../../../patches/mac80211_rx.patch"
        fi
    fi

    
    echo -e "\nThis could take a few minutes depending on your system configuration"
    read -p "(press enter to build and install kernel patch)"
    
    
    #(DESC) Configure patched linux kernel sources
    make olddefconfig -j`nproc` 
    
    
    #(TODO) Check if this is necessary
    chown $USERNAME:$USERNAME $mac80211_dir/Makefile
    
    
    sed -i 's/obj-$(CONFIG_MAC80211) += mac80211.o/obj-$(CONFIG_MAC80211) += mac80211.o\nKVERSION := $(shell uname -r)/g' $mac80211_dir/Makefile
    
    
    #(DESC) Check if Makefile is already patched
    if grep -xq "all:" $mac80211_dir/Makefile && grep -xq "clean:" $mac80211_dir/Makefile; then
        echo "Makefile already patched, skipping"
    else
        echo -e "\nall:\n\t\$(MAKE) -C /lib/modules/\$(KVERSION)/build M=\$(PWD) modules\n\nclean:\n\t\$(MAKE) -C /lib/modules/\$(KVERSION)/build M=\$(PWD) clean" >> $mac80211_dir/Makefile
    fi
    
    
    #(DESC) Check if dkms.conf is already patched
    if [ -f "${mac80211_dir}/dkms.conf" ]; then
        echo "dkms.conf exists, skipping"
    else
        echo -e 'PACKAGE_NAME="drc-mac80211"\nPACKAGE_VERSION="0.1.0"\nCLEAN="make clean"\nMAKE[0]="make all KVERSION=$kernelver"\nBUILT_MODULE_NAME[0]="mac80211"\nDEST_MODULE_LOCATION[0]="/updates"\nAUTOINSTALL="yes"' > $mac80211_dir/dkms.conf
    fi
    
    
    #(CLEAN) Just in case we've already run
    test -d "/usr/src/drc-mac80211-0.1.0" && rm -rf /usr/src/drc-mac80211-0.1.0
    
    
    #(DESC) Move the patched mac80211 sources to a place that dkms will see
    cp -rf $mac80211_dir /usr/src/drc-mac80211-0.1.0
    
    
    #(TODO)#(NOTE) What is this doing here?? Lmao??? Should I move this????? What was I on when I put this here?
    #(DESC) prepare the kernel source tree for building modules
    make modules_prepare -j`nproc`
    
    
    #(CLEAN) Remove dkms module in case we've already been here
    dkms remove -m drc-mac80211/0.1.0 -k `uname -r` 2> /dev/null
    
    
    #(DESC) Make and install patched mac80211
    dkms install -m drc-mac80211 -v 0.1.0 -j `nproc`
    
} ; cd ${SCRIPT_DIR}/kernel-patch-files/linux-${KERNEL_VER} ; patch_kernel ; cd ${SCRIPT_DIR} #(DESC) Start function immediately 





installed_module_successfully=false

test_kernel_patch () {
    #(NOTE) ASSUME PATCHED MAC80211 MODULE IS IN /lib/modules/$(uname -r)/updates/dkms/mac80211.ko
    
    restore_modules=$(rmmod mac80211 2>&1 >/dev/null | grep -o -m1 "by: .*" | cut -c 5-)
    
    unload_modules_recursively mac80211
    
    
    
    insmod /lib/modules/$(uname -r)/updates/dkms/mac80211.ko 2>&1 | grep -v "File exists"
    if [[ $(awk '{ print $1 }' /proc/modules | xargs modinfo -n | grep "mac80211") =~ "dkms/mac80211.ko" ]]; then
        echo "Patched mac80211 module installed"
        installed_module_successfully=true
    else
        modprobe mac80211 #(UNTESTED) Could have unforseen consequences!!
        if [[ $(awk '{ print $1 }' /proc/modules | xargs modinfo -n | grep "mac80211") =~ "dkms/mac80211.ko" ]]; then
            echo "Patched mac80211 module installed"
            installed_module_successfully=true
        else        
            echo "SCRIPT NAME: ${0}" > $debug_file
            echo "START OF COMMAND awk '{ print $1 }' /proc/modules | xargs modinfo -n" >> $debug_file
            awk '{ print $1 }' /proc/modules | xargs modinfo -n >> $debug_file
            echo -e "\n\n\n\n\nSTART OF COMMAND modinfo mac80211 | sed -n '/sig_id/q;p'" >> $debug_file
            modinfo mac80211 | sed -n '/sig_id/q;p' >> $debug_file
            chown $USERNAME:$USERNAME $debug_file
            
            installed_module_successfully=false
            modprobe $restore_modules
        fi
    fi
} ; test_kernel_patch #(DESC) Start function immediately 






if [[ $installed_module_successfully == false ]]; then
    #(DESC) Only remove extracted kernel directory, do not remove the downloaded kernel archive.
    rm -rf $(find . -type d -regex "./linux-[0-9]+\.[0-9]+\.[0-9]+")
    
    
    echo; echo; echo; echo #(NOTE) \n\n\n\n
    echo "Couldn't install patched module to active kernel using virgin kernel sources version ${KERNEL_VER}"
    echo "Your operating system vendor probably broke compatibility with the version of mac80211 that comes with the virgin kernel."
    #(CODE) read -p "(press enter to acknowledge the tomfoolery)"
    
    mkdir "${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER" && chown $USERNAME:$USERNAME "${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER"
    
    supported_distro_version_codenames="focal" #(TODO) Test on other versions of ubuntu and add them to the list "version1 version2 version3"
    
    
    
    #(UGLY)#(NOTE) Portability? Never heard of it!
    if [[ $distro_id == "ubuntu" ]]; then #(CODE)#(EXCEPT)#(TODO) && if [[ $supported_distro_version_codenames =~ $distro_version_codename ]]; then
        apt_sources="/etc/apt/sources.list"
        country_archive_url=$(cat /etc/apt/sources.list | grep -o -m1 "http://\w*\.archive\.ubuntu\.com/ubuntu/")
        sign_off=" #Added by pc2drc ${SCRIPT_NAME}"
        
        if [[ ! $(cat $apt_sources) =~ $sign_off ]]; then
            echo "deb-src http://archive.ubuntu.com/ubuntu ${distro_version_codename} main restricted${sign_off}" >> $apt_sources
            echo "deb-src ${country_archive_url} ${distro_version_codename} universe multiverse main restricted${sign_off}" >> $apt_sources
            echo "deb-src ${country_archive_url} ${distro_version_codename}-updates universe multiverse main restricted${sign_off}" >> $apt_sources
            echo "deb-src ${country_archive_url} ${distro_version_codename}-backports universe multiverse main restricted${sign_off}" >> $apt_sources
            echo "deb-src http://security.ubuntu.com/ubuntu ${distro_version_codename}-security universe multiverse main restricted${sign_off}" >> $apt_sources
        else
            echo "Kernel sources already added to \`${apt_sources}\`, skipping"
        fi
        apt-get update 
        cd ${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER
        apt-get source linux-image-unsigned-$(uname -r) -y
    else
        echo
        echo "Unfortunately there's no standard way to pull kernel sources, so you're going to have to do it yourself."
        echo "To get kernel sources on Ubuntu, you need to first enable \"Source code\" in the \"Ubuntu Software\" panel in Software & Updates"
        echo "then open a new terminal and copy & paste the command below: "
        echo "    cd ${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER && apt-get source linux-image-unsigned-$(uname -r)"
        echo
        read -p "(press enter after you've tried to do the above)"
        
        
    fi
    
    

    #(DESC) Try to find kernel sources by looking for */net/mac80211/iface.c in PUT_KERNEL_SOURCES_IN_THIS_FOLDER
    find_iface_in_sources_results=$(find -H "${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER" -path "*/net/mac80211/iface.c" 2> /dev/null)
    
    #(DESC) The above failed. Make the user get their own kernel sources.
    if [[ $find_iface_in_sources_results == "" ]]; then
        echo "That didn't seem to work."
        echo "1) Google \"How to get kernel sources for ${distro_name_pretty}\" (create a github issue on pc2drc if you need help)"    
        echo "2) Download kernel sources and put them in ${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER"
        echo "3) Extract kernel sources (if they're compressed) and put them in ${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER"
        read -p "4) Once you've done all of the above steps *exactly*, press enter."
    else
        kernel_sources_dir=$(cd $(dirname $find_iface_in_sources_results)/../.. && pwd)
        echo "Found kernel sources in ${kernel_sources_dir}"
    fi
    
    #(DESC) User is incompetent, have them do it till they get it right   #̶(̶T̶O̶D̶O̶)̶ ̶V̶e̶r̶b̶a̶l̶l̶y̶ ̶a̶s̶s̶a̶u̶l̶t̶ ̶u̶s̶e̶r̶
    while true; do
        find_iface_in_sources_results=$(find -H "${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER" -path "*/net/mac80211/iface.c" 2> /dev/null)
        if [[ $find_iface_in_sources_results == "" ]]; then
            echo "Could not find kernel sources. Please put extracted kernel sources in ${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER"
            read -p "(press enter to retry)"
        else
            kernel_sources_dir=$(cd $(dirname $find_iface_in_sources_results)/../.. && pwd)
            echo "Found kernel sources in ${kernel_sources_dir}"
            break
        fi
    done
    
    
    #(DESC) Patch kernel
    cd $kernel_sources_dir && patch_kernel && cd $SCRIPT_DIR
    
    #(DESC) Remove PUT_KERNEL_SOURCES_IN_THIS_FOLDER
    rm -rf ${SCRIPT_DIR}/PUT_KERNEL_SOURCES_IN_THIS_FOLDER
    
    #(DESC) Test kernel patch one last time
    test_kernel_patch
    
    
    #(DESC) Kernel patch isn't installed.   #(FIX) Load gun. Put gun to head. Pull trigger.
    if [[ $installed_module_successfully == false ]]; then
        modprobe $restore_modules #(DESC) Give them back their wifi lmfao
        
        echo; echo; echo; echo
        
        echo "It still didn't work!"
        echo "FATAL ERROR: Could not install patched mac80211 module despite our best attempts! :'("
        echo "thefloppydriver: I have no idea what just caused this to happen. Please send a detailed bug report if you get this message so that I can catch it properly!!"
        echo "also attatch $(pwd)/generated_bug_report.txt to your bug report :)"
        echo
        read -p "(press enter to quit)"
        exit
    fi
    
fi


#(DESC) Kernel patch is installed. Proceed to celebrate.
if [[ $installed_module_successfully == true ]]; then
    echo "Woohoo! The module installed successfully!"
fi





unload_modules_recursively $restore_modules
unload_modules_recursively mac80211
modprobe mac80211


mac80211_has_no_dependencies=false
#(NOTE) https://stackoverflow.com/a/59592881/11952326
#(DESC) Put the stdout of `modprobe $restore_modules` into modprobe_stdout, and the stderr into modprobe_stderr
{
    IFS=$'\n' read -r -d '' restore_modules_stderr;
    IFS=$'\n' read -r -d '' restore_modules_stdout;
} < <((printf '\0%s\0' "$(modprobe $restore_modules)" 1>&2) 2>&1)


if [[ $restore_modules_stderr == "modprobe: ERROR: missing parameters. See -h." ]]; then
    echo "No devices were using mac80211. You might not be using a compatible wifi interface"
    mac80211_has_no_dependencies=true
elif [[ $restore_modules_stderr == "" ]]; then
    echo $restore_modules_stdout
else
    echo "Error during command \`modprobe ${restore_modules}\`"
    echo "Output: "
    echo "    ${restore_modules_stdout}"
    echo
    echo "Error: "
    echo "    ${modprobe_output}"
fi





echo; echo; echo; echo

if [[ -f "/sys/class/net/$(ip link show | grep -o -m1 "\w*wl\w*")/tsf" ]]; then
    rm -rf ./kernel-patch-files/linux-*
    echo 'Patched mac80211 loaded'
    echo "Kernel patch installed successfully"
    echo "Make sure to run stage 2 next!"
    read -p "(press enter to quit)"
    exit
else
    if [[ $mac80211_has_no_dependencies == true ]] && [[ $installed_module_successfully == true ]]; then
        echo "The kernel patch isn't working, but the module installed successfully."
        echo "This probably means that you don't have any devices that use mac80211."
        echo "You can view the device compatability list at https://github.com/thefloppydriver/pc2drc or by reading the README.md file in the project directory."
    else
        echo 'Kernel patch not working. Try rebooting and running this script again. If that fails, run `sudo -E ./kernel-patch-files/build-patched-kernel.sh` instead.'
    fi

    read -p "(press enter to quit)"
    exit
fi
