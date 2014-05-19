#!/bin/bash

# --- Configuration -------------------------------------------------------------
VERSION="Cubietruck"
SOURCE_COMPILE="yes"
DEST_LANG="en_GB"
DEST_LANGUAGE="en"
DEST=~/cubieboard/Cubietruck-Debian/final
DISPLAY=3  # "3:hdmi; 4:vga"
# --- End -----------------------------------------------------------------------
SRC=$(pwd)
#set -e

#Requires root ..
if [ "$UID" -ne 0 ]
  then echo "Please run as root"
  exit
fi
echo "Building Cubietruck-Debian in $DEST from $SRC"
sleep 3
#--------------------------------------------------------------------------------
# Downloading necessary files
#--------------------------------------------------------------------------------
echo "------ Downloading necessary files"
apt-get update
apt-get upgrade
apt-get -qq -y install binfmt-support bison build-essential ccache debootstrap flex gawk fakeroot kernel-package gcc-arm-linux-gnueabi gcc-arm-linux-gnueabihf gettext linux-headers-generic linux-image-generic lvm2 qemu-user-static texinfo texlive u-boot-tools uuid-dev zlib1g-dev unzip libncurses5-dev pkg-config libusb-1.0-0-dev

#--------------------------------------------------------------------------------
# Preparing output / destination files
#--------------------------------------------------------------------------------

echo "------ Fetching files from github"
mkdir -p $DEST/output
cp output/uEnv.* $DEST/output

if [ -d "$DEST/u-boot-sunxi" ]
then
	cd $DEST/u-boot-sunxi ; git pull; cd $SRC
else
	#git clone https://github.com/cubieboard/u-boot-sunxi $DEST/u-boot-sunxi # Boot loader
	git clone https://github.com/patrickhwood/u-boot -b pat-cb2-ct  $DEST/u-boot-sunxi # CB2 / CT Dual boot loader
fi
if [ -d "$DEST/sunxi-tools" ]
then
	cd $DEST/sunxi-tools; git pull; cd $SRC
else
	git clone https://github.com/linux-sunxi/sunxi-tools.git $DEST/sunxi-tools # Allwinner tools
fi
if [ -d "$DEST/cubie_configs" ]
then
	cd $DEST/cubie_configs; git pull; cd $SRC
else
	git clone https://github.com/cubieboard/cubie_configs $DEST/cubie_configs # Hardware configurations
	#git clone https://github.com/linux-sunxi/sunxi-boards.git $DEST/cubie_configs # Hardware configurations Power features
fi
if [ -d "$DEST/linux-sunxi" ]
then
	cd $DEST/linux-sunxi; git pull -f; cd $SRC
else
	git clone https://github.com/cubieboard/linux-sunxi.git -b ct/sunxi-3.4 $DEST/linux-sunxi # Kernel 3.4.61+
	#git clone https://github.com/patrickhwood/linux-sunxi -b pat-3.4.75-ct $DEST/linux-sunxi # Patwood's kernel 3.4.75+
	#git clone https://github.com/cubieboard/linux-sunxi.git $DEST/linux-sunxi #Original Cubie Kernel All features
	#git clone https://github.com/linux-sunxi/linux-sunxi.git $DEST/linux-sunxi
fi

# Applying Patch for 2gb memory
patch -f $DEST/u-boot-sunxi/include/configs/sunxi-common.h < $SRC/patch/memory.patch || true

#From now on just include all patches in one patch file.
cd $DEST/linux-sunxi/
patch -p1 < $SRC/patch/ctcombine.patch
cd $DEST/

# Applying Patch for gpio
#patch -f $DEST/linux-sunxi/drivers/gpio/gpio-sunxi.c < $SRC/patch/gpio.patch || true

# Apply patch to fix sound soc
#cd $DEST/linux-sunxi/
#patch -p1 < $SRC/patch/0001-I2S-module-rework.patch
#cd $DEST/

# Apply patch to fix asix RX issues
#cd $DEST/linux-sunxi/
#patch -p1 < $SRC/patch/asix.patch
#cd $DEST/

# Apply patch to include ax88179_178a
#cd $DEST/linux-sunxi/
#patch -p1 < $SRC/patch/ax88179_178a.patch
#cd $DEST/

# Apply patch to builddeb
#cd $DEST/linux-sunxi/
#patch -p1 < $SRC/patch/builddeb.patch
#cd $DEST/

# Applying Patch for high load. Could cause troubles with USB OTG port
sed -e 's/usb_detect_type     = 1/usb_detect_type     = 0/g' $DEST/cubie_configs/sysconfig/linux/cubietruck.fex > $DEST/cubie_configs/sysconfig/linux/ct.fex

# Prepare fex files for VGA & HDMI
sed -e 's/screen0_output_type.*/screen0_output_type     = 3/g' $DEST/cubie_configs/sysconfig/linux/ct.fex > $DEST/cubie_configs/sysconfig/linux/ct-hdmi.fex
sed -e 's/screen0_output_type.*/screen0_output_type     = 4/g' $DEST/cubie_configs/sysconfig/linux/ct.fex > $DEST/cubie_configs/sysconfig/linux/ct-vga.fex


# Copying Kernel config
cp $DEST/cubie_configs/kernel-configs/3.4/cubietruck_defconfig $DEST/linux-sunxi/kernel.config
#cp $SRC/config/kernel.config $DEST/linux-sunxi/

#--------------------------------------------------------------------------------
# Compiling everything
#--------------------------------------------------------------------------------
if [ "$SOURCE_COMPILE" = "yes" ]; then
echo "------ Compiling kernel boot loaderb"
cd $DEST/u-boot-sunxi
# boot loader
ln -s /usr/bin/arm-linux-gnueabihf-gcc /usr/bin/arm-linux-gcc 2>/dev/null

make clean && make -j2 'cubietruck' CROSS_COMPILE=arm-linux-gnueabihf-
echo "------ Compiling sunxi tools"
cd $DEST/sunxi-tools
# sunxi-tools
make clean && make fex2bin && make bin2fex
cp fex2bin bin2fex /usr/local/bin/
# hardware configuration
fex2bin $DEST/cubie_configs/sysconfig/linux/ct-vga.fex $DEST/output/ct-vga.bin
fex2bin $DEST/cubie_configs/sysconfig/linux/ct-hdmi.fex $DEST/output/ct-hdmi.bin

# kernel image
echo "------ Compiling kernel"
cd $DEST/linux-sunxi
#make clean

# Adding wlan firmware to kernel source
cd $DEST/linux-sunxi/firmware
unzip -o $SRC/bin/ap6210.zip
cd $DEST/linux-sunxi

#make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sun7i_defconfig
# get proven config
cp $DEST/linux-sunxi/kernel.config $DEST/linux-sunxi/.config
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- uImage modules
sleep 2
#make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=output modules_install
#make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_HDR_PATH=output headers_install
# Build Deb packages
export ARCH=arm
export DEB_HOST_ARCH=armhf
export CONCURRENCY_LEVEL=`grep -m1 cpu\ cores /proc/cpuinfo | cut -d : -f 2`
#fakeroot make-kpkg --arch arm --cross-compile arm-linux-gnueabihf- --initrd  kernel_image kernel_source kernel_headers
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KBUILD_DEBARCH=armhf KBUILD_IMAGE=uImage deb-pkg
cp $DEST/linux-sunxi/arch/arm/boot/uImage $DEST/
cd $DEST/usb-redirector-linux-arm-eabi/files/modules/src/tusbd
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- KERNELDIR=$DEST/linux-sunxi/
cp $DEST/usb-redirector-linux-arm-eabi/files/modules/src/tusbd/tusbd.ko $DEST/
fi
