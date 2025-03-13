#!/bin/bash

if [ `id -u` -ne 0 ]; then
    echo "Please run with: sudo -E ./stage-2-build-modules.sh"
    exit
fi

if [ $(cd $HOME/.. && pwd) != "/home" ]; then
    echo "Please run with: sudo -E ./stage-2-build-modules.sh"
    exit
fi

if [[ $(ip link show | grep -o -m1 "\w*wl\w*") == "" ]]; then
    echo "No wireless interfaces found. Please attatch a wireless interface and try again."
    exit
fi

unload_modules_recursively () {
  local output=$(rmmod $@ 2>&1)
  if [[ $output =~ "by:" ]]; then
    unload_modules_recursively $(rmmod $output 2>&1 >/dev/null | grep -o -m1 "by: .*" | cut -c 5-)
  fi
  if [[ $output =~ "missing module name" ]]; then
    return 69 #this doesn't matter, I should really check this but whatever
  fi
  sleep 1
}

no_check_tsf=false



if [[ ! "$@" == "" ]]; then
    if [[ "$@" =~ "--no-check-tsf" ]]; then
        echo "skipping kernel patch check"
        no_check_tsf=true
    fi
fi


if [[ $no_check_tsf == false ]]; then

if [ ! -f "/sys/class/net/$(ip link show | grep -o -m1 "\w*wl\w*")/tsf" ]; then
    echo 'TSF kernel patch not loaded.'
    #ASSUME MODULE IS IN /lib/modules/$(uname -r)/updates/dkms/mac80211.ko
    
    restore_modules=$(rmmod mac80211 2>&1 >/dev/null | grep -o -m1 "by: .*" | cut -c 5-)
    
    if [[ $(awk '{ print $1 }' /proc/modules | xargs modinfo -n | grep "mac80211") =~ "dkms/mac80211.ko" ]]; then
        echo "Patched mac80211 module installed"
    else
        insmod /lib/modules/$(uname -r)/updates/dkms/mac80211.ko 2>&1 | grep -v "File exists"
        if [[ $(awk '{ print $1 }' /proc/modules | xargs modinfo -n | grep "mac80211") =~ "dkms/mac80211.ko" ]]; then
            echo "Patched mac80211 module installed"
        else        
            debug_file=./generated_bug_report.txt
            echo "SCRIPT NAME: ${0}" > $debug_file
            echo "START OF COMMAND awk '{ print $1 }' /proc/modules | xargs modinfo -n" >> $debug_file
            awk '{ print $1 }' /proc/modules | xargs modinfo -n >> $debug_file
            echo -e "\n\n\n\n\nSTART OF COMMAND modinfo iwlmvm | sed -n '/sig_id/q;p'" >> $debug_file
            modinfo mac80211 | sed -n '/sig_id/q;p' >> $debug_file
            
            echo        
            echo "FATAL ERROR: Could not load patched mac80211 module."
            echo "thefloppydriver: I have no idea what just caused this to happen. Please send a detailed bug report if you get this message so that I can catch it properly!!"
            echo "also attatch $(pwd)/generated_bug_report.txt to your bug report :)"
            echo
            read -n 1 -p "(press enter to quit)"
            modprobe $restore_modules
            exit
        fi
    fi

    modprobe $restore_modules
    unload_modules_recursively $restore_modules
    unload_modules_recursively mac80211
    modprobe mac80211
    modprobe $restore_modules
fi


if [ ! -f "/sys/class/net/$(ip link show | grep -o -m1 "\w*wl\w*")/tsf" ]; then
   echo 'TSF kernel patch not loaded.'
   if [ $(uname -r) != '5.11.22' ] ; then
       echo "You're running an unpatched kernel OR something went wrong with EXPERIMENTAL-stage-1-kernel-patch.sh"
       echo "Please reboot to grub and choose Advanced options for Ubuntu > Ubuntu, with Linux 5.11.22   (It should be the selected by default)"
       read -n 1 -p "(press enter to quit)"
       exit
   fi
   echo "You're running the patched kernel version, but the patch isn't working."
   echo "Please reboot and try again or email thefloppydriver@gmail.com for help."
   exit
fi

fi



if [ ${PWD##*/} != "pc2drc" ]; then
  echo "Parent folder is not named pc2drc. If this script isn't its intended directory you will have an unusable system."
  read -n 1 -p "(press enter to quit)"
  exit
fi

echo -e "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "An internet connection is required for this script to run. Try sudo service network-manager start."
    read -n 1 -p "(press enter to quit)"
    exit
fi

script_dir=$(pwd)


apt --fix-broken install -y

apt-get install libnl-3-dev libnl-genl-3-dev -y

apt-get install ffmpeg libswscale-dev libavutil-dev -y

apt-get install yasm mesa-utils freeglut3 freeglut3-dev libglew-dev libgl1-mesa-dev libsdl1.2-dev libsdl2-dev tigervnc-standalone-server tigervnc-viewer cmake python3 autoconf -y
apt-get remove libx264-dev -y

mkdir -m 775 ./external_pkg_build_dir
mkdir -m 775 ./external_pkg_install_dir

chown -R $USERNAME:$USERNAME ./external_pkg_build_dir
chown -R $USERNAME:$USERNAME ./external_pkg_install_dir

rm -rf ./external_pkg_install_dir/* #careful with this

cd ./external_pkg_build_dir
wget https://openssl.org/source/old/1.0.1/openssl-1.0.1u.tar.gz --no-check-certificate
git clone https://github.com/LibVNC/libvncserver.git



tar -xf ./openssl-1.0.1u.tar.gz
rm ./openssl-1.0.1u.tar.gz*
cd ./openssl-1.0.1u

#~/Documents/bring-back-libdrc/bring-back-libdrc/drc-hostap/hostapd/Makefile Line 475:  LIBS += -lssl -lcrypto -lz -ldl
#~/Documents/bring-back-libdrc/bring-back-libdrc/drc-hostap/wpa_supplicant/Makefile Line 927:  LIBS += -lcrypto -lz
#~/Documents/bring-back-libdrc/bring-back-libdrc/drc-hostap/wpa_supplicant/Makefile Line 928:  LIBS += -lcrypto -lz -ldl

make clean -j`nproc`

./config --prefix=$script_dir/external_pkg_install_dir/ --openssldir=openssl threads zlib no-shared
make -j`nproc`
make install

cd ..


#echo "TODO: COMPILE AND INSTALL LIBVNCSERVER/LIBVNCCLIENT"

mkdir ./libvncserver/build

cd ./libvncserver/build

make clean
cmake ..
cmake --build . --parallel `nproc`
make install

cd ../..

rm -rf ./libvncserver #careful
rm -rf ./openssl-1.0.1u #careful


#wget https://launchpad.net/~ubuntu-security/+archive/ubuntu/ppa/+build/7531893/+files/openssl_1.0.1-4ubuntu5.31_amd64.deb --no-check-certificate
#wget https://launchpad.net/~ubuntu-security/+archive/ubuntu/ppa/+build/7531893/+files/libssl1.0.0_1.0.1-4ubuntu5.31_amd64.deb --no-check-certificate
#wget https://launchpad.net/~ubuntu-security/+archive/ubuntu/ppa/+build/7531893/+files/libssl-dev_1.0.1-4ubuntu5.31_amd64.deb --no-check-certificate

#wget -c http://archive.ubuntu.com/ubuntu/pool/universe/libn/libnl/libnl1_1.1-8ubuntu1_amd64.deb
#wget -c http://archive.ubuntu.com/ubuntu/pool/universe/libn/libnl/libnl-dev_1.1-8ubuntu1_amd64.deb

#dpkg --ignore-depends=multiarch-support -i libssl1.0.0_1.0.1-4ubuntu5.31_amd64.deb
#dpkg -i openssl_1.0.1-4ubuntu5.31_amd64.deb
#dpkg -i libssl-dev_1.0.1-4ubuntu5.31_amd64.deb



cd ..

rm -d ./external_pkg_build_dir


#####git clone https://bitbucket.org/memahaxx/drc-hostap.git
#####cd drc-hostap
#####git clone https://github.com/ITikhonov/netboot.git

cd ./drc-hostap/netboot
rm ./netboot
gcc -o netboot netboot.c

chown $USERNAME:$USERNAME ./netboot
cd ../..

cd ./drc-hostap/hostapd

cp -f ./defconfig ./.config

sed -i "s?/_123sedreplaceme?${script_dir}?g" ./.config

make clean
make -j`nproc`

cd ../..

chown -R $USERNAME:$USERNAME ./drc-hostap/hostapd/*





#apt --fix-broken install -y

#apt remove libnl-3-dev -y

#dpkg --ignore-depends=multiarch-support -i ./libnl1_1.1-8ubuntu1_amd64.deb
#dpkg --ignore-depends=multiarch-support -i ./libnl-dev_1.1-8ubuntu1_amd64.deb



#dpkg --ignore-depends=multiarch-support -i libssl1.0.0_1.0.1-4ubuntu5.31_amd64.deb
#dpkg -i libssl-dev_1.0.1-4ubuntu5.31_amd64.deb
#dpkg -i openssl_1.0.1-4ubuntu5.31_amd64.deb



#rm ./openssl_1.0.1-4ubuntu5.31_amd64.deb
#rm ./libssl1.0.0_1.0.1-4ubuntu5.31_amd64.deb
#rm ./libssl-dev_1.0.1-4ubuntu5.31_amd64.deb
#rm ./external_pkg_build_dir/libnl1_1.1-8ubuntu1_amd64.deb*
#rm ./external_pkg_build_dir/libnl-dev_1.1-8ubuntu1_amd64.deb*

#apt --fix-broken install -y

cd ./drc-hostap/wpa_supplicant

cp -f ./defconfig ./.config

sed -i "s?/_123sedreplaceme?${script_dir}?g" ./.config

make clean
make -j`nproc`

cd ../..

chown -R $USERNAME:$USERNAME ./drc-hostap/wpa_supplicant/*



#apt --fix-broken install


#echo "DEBUG: COMPILE AND INSTALL MODIFIED FFMPEG AND DRC-X264"

cd ./drc-x264
make clean
./configure --prefix=/usr/local --enable-static --enable-pic # --enable-shared   NOTE: NO. DO NOT ENABLE SHARED. SHARED LIBRARIES ARE THE DEVIL.
make -j`nproc`
make install -j`nproc`

cd ..


#echo "DEBUG: COMPILE AND INSTALL MODIFIED LIBDRC"

cd ./libdrc-vnc/libdrc-thefloppydriver

make clean -j`nproc`
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH ./configure --disable-demos --disable-debug --prefix=/usr/local

make -j`nproc`
make install -j`nproc`

cd ../..

chown -R $USERNAME:$USERNAME ./libdrc-vnc/libdrc-thefloppydriver/*
chown -R $USERNAME:$USERNAME ./libdrc-vnc/libdrc-thefloppydriver/src/*







#echo "DEBUG: COMPILE AND INSTALL A VNC VIEWER"

#tigervnc-standalone-server was (hopefully) already installed earlier in the script.


#vncpasswd
mkdir ~/.vnc

#tigervnc startup script that inits for a gamepad connection

#printf '#!/bin/sh\nxrdb $HOME/.Xresources\nxsetroot -solid grey\nexport XKL_XMODMAP_DISABLE=1\n/etc/X11/Xsession\n[ -x /etc/vnc/xstartup ] && exec /etc/vnc/xstartup\n[ -r $HOME/.Xrespirces ] && xrdb $HOME/.Xresources\nvncconfig -iconic &\ndbus-launch --exit-with-session gnome-session &\nsleep 1 && xrandr --fb 854x480 &' > ~/.vnc/xstartup
printf '#!/bin/sh\ntest x"$SHELL" = x"" && SHELL=/bin/bash\ntest x"$1"     = x"" && set -- default\nvncconfig -iconic &\n"$SHELL" -l <<EOF\nexport XDG_SESSION_TYPE=x11\ndbus-launch --exit-with-session gnome-session\nexec /etc/X11/Xsession "$@"\nEOF\nvncserver -kill $DISPLAY' > /etc/vnc/xstartup
printf '#!/bin/sh\n[ -x /etc/vnc/xstartup ] && exec /etc/vnc/xstartup\n[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources\nsleep 1 && xrandr --fb 854x480 &' > ~/.vnc/xstartup

/bin/bash -c "echo -e '\n\nn' | vncpasswd"; echo

chmod 0755 /etc/vnc/xstartup
chmod 0755 ~/.vnc/xstartup
chmod 0664 ~/.vnc/passwd

#echo | vncpasswd -f > ~/.vnc/passwd

chown -R $USERNAME:$USERNAME ~/.vnc

#tigervncserver :1 -passwd ~/.vnc/passwd -geometry 1280x720 -depth 24 -localhost
#xtigervncviewer :1 -passwd ~/.vnc/passwd -DesktopSize=864x480




#echo "DEBUG: COMPILE AND INSTALL drcvncclient"

cd ./libdrc-vnc/drcvncclient

autoreconf -f -i #FIX FOR USERS CASE OF COMPILING FROM CLONED GIT. XXX NEEDS TESTING!

make clean -j`nproc`

x264_LIBS='-L/usr/local/lib -lx264 -L/usr/local/lib -lswscale' ./configure
make -j`nproc`

cd ../..


echo
echo
echo
echo
echo
echo "All modules built successfully! Onto stage 3!"








