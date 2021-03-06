#!/bin/bash

# http://www.nongnu.org/avr-libc/user-manual/install_tools.html

# For optimum compile time this should generally be set to the number of CPU cores your machine has
# Do it automatically, can over-ride from command line.
if [ -z ${JOBCOUNT+x} ]; then
	CORES=$(getconf _NPROCESSORS_ONLN)
	JOBCOUNT=$CORES
fi

# Build Linux toolchain
# A Linux AVR-GCC toolchain is required to build a Windows toolchain
# If the Linux toolchain has already been built then you can set this to 0
if [ -z ${BUILD_LINUX+x} ]; then
	BUILD_LINUX=1
fi

# Build 32 bit Windows toolchain
if [ -z ${BUILD_WIN32+x} ]; then
	BUILD_WIN32=1
fi

# Build 64 bit Windows toolchain
if [ -z ${BUILD_WIN64+x} ]; then
	BUILD_WIN64=1
fi

# Build Binutils?  Can be set on command line.
if [ -z ${BUILD_BINUTILS+x} ]; then
	BUILD_BINUTILS=1
fi

# Build AVR-GCC?  Can be set on command line.
if [ -z ${BUILD_GCC+x} ]; then
	BUILD_GCC=1
fi

# Build AVR-LibC?  Can be set on command line.
if [ -z ${BUILD_LIBC+x} ]; then
	BUILD_LIBC=1
fi

# Output locations for built toolchains
if [ -z ${PREFIX+x} ]; then
	PREFIX=/opt/AVR
fi

PREFIX_LINUX="$PREFIX"/avr-gcc-linux
PREFIX_WIN32="$PREFIX"/avr-gcc-win32
PREFIX_WIN64="$PREFIX"/avr-gcc-win64
PREFIX_LIBC="$PREFIX"/avr-libc3

# Install packages
if [ "$EUID" -eq 0 ]; then
	echo "Running as root, so trying to install dependant packages."
	if hash apt-get 2>/dev/null; then
		# This works for Debian 8 and Ubuntu 16.04
		apt-get install wget make gcc g++ bzip2 mingw-w64
	elif hash yum 2>/dev/null; then
		# This works for CentOS 7
		yum install wget
		rpm -q epel-release-7-6.noarch >/dev/null
		if [ $? -ne 0 ]; then
			# EPEL is for the MinGW stuff
			rm -f epel-release-7-6.noarch.rpm
			wget https://www.mirrorservice.org/sites/dl.fedoraproject.org/pub/epel//7/x86_64/e/epel-release-7-6.noarch.rpm
			rpm -Uvh epel-release-7-6.noarch.rpm
		fi
		yum install make mingw64-gcc mingw64-gcc-c++ mingw32-gcc mingw32-gcc-c++ gcc gcc-c++ bzip2
	elif hash pacman 2>/dev/null; then
		# This works for Arch
		pacman -S --needed wget make mingw-w64-binutils mingw-w64-gcc mingw-w64-crt mingw-w64-headers mingw-w64-winpthreads gcc bzip2
	fi

	echo "We will not build while running as root, run as standard user to build."
	exit 1
fi

# Stop on errors
set -e

NAME_BINUTILS="binutils-2.32"
NAME_GCC="gcc-9.1.0"
NAME_LIBC="avr-libc3.git"

HOST_WIN32="i686-w64-mingw32"
HOST_WIN64="x86_64-w64-mingw32"

OPTS_BINUTILS="
	--target=avr
	--disable-nls
"

OPTS_GCC="
	--target=avr
	--enable-languages=c,c++
	--disable-nls
	--disable-libssp
	--disable-libada
	--with-dwarf2
	--disable-shared
	--enable-static
	--enable-mingw-wildcard
"

OPTS_LIBC=""

TIME_START=$(date +%s)

makeDir()
{
	rm -rf "$1/"
	mkdir -p "$1"
}

echo "Clearing output directories..."
[ $BUILD_LINUX -eq 1 ] && [ $BUILD_BINUTILS -eq 1 ] && makeDir "$PREFIX_LINUX"
[ $BUILD_WIN32 -eq 1 ] && [ $BUILD_BINUTILS -eq 1 ] && makeDir "$PREFIX_WIN32"
[ $BUILD_WIN64 -eq 1 ] && [ $BUILD_BINUTILS -eq 1 ] && makeDir "$PREFIX_WIN64"
[ $BUILD_LIBC -eq 1 ] && makeDir "$PREFIX_LIBC"

PATH="$PREFIX_LINUX"/bin:"$PATH"
export PATH

CC=""
export CC

echo "Downloading sources..."

# Create a temp directory for downloading and building in, to not polute base directory
makeDir buildtemp
cd buildtemp

if [ $BUILD_BINUTILS -eq 1 ]; then
	rm -f $NAME_BINUTILS.tar.xz
	rm -rf $NAME_BINUTILS/
	wget ftp://ftp.mirrorservice.org/sites/ftp.gnu.org/gnu/binutils/$NAME_BINUTILS.tar.xz
fi

if [ $BUILD_GCC -eq 1 ]; then
	rm -f $NAME_GCC.tar.xz
	rm -rf $NAME_GCC/
	wget ftp://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/$NAME_GCC/$NAME_GCC.tar.xz
fi

if [ $BUILD_LIBC -eq 1 ]; then
	rm -rf $NAME_LIBC/
	if [ "$NAME_LIBC" = "avr-libc3.git" ]; then
		git clone https://github.com/stevenj/avr-libc3.git "$NAME_LIBC"
		echo "Preparing"
		cd $NAME_LIBC
		git checkout 8e93ef44b707cdcddf46e5e8d770fd68c59829cc
		./bootstrap
		cd ..
	else
		wget ftp://ftp.mirrorservice.org/sites/download.savannah.gnu.org/releases/avr-libc/$NAME_LIBC.tar.bz2
	fi
fi

confMake()
{
	../configure --prefix=$1 $2 $3 $4
	make -j $JOBCOUNT
	make install-strip
	rm -rf *
}

# Make AVR-Binutils
if [ $BUILD_BINUTILS -eq 1 ]; then
	echo "Making Binutils..."
	echo "Extracting..."
	tar xf $NAME_BINUTILS.tar.xz
	mkdir -p $NAME_BINUTILS/obj-avr
	cd $NAME_BINUTILS/obj-avr
	if [ $BUILD_LINUX -eq 1 ]; then
		echo "********** BUILDING LINUX BINUTILS *************"
		confMake "$PREFIX_LINUX" "$OPTS_BINUTILS"
	fi
	if [ $BUILD_WIN32 -eq 1 ]; then
		echo "********** BUILDING WIN32 BINUTILS *************"
		confMake "$PREFIX_WIN32" "$OPTS_BINUTILS" --host=$HOST_WIN32 --build=`../config.guess`
	fi
	if [ $BUILD_WIN64 -eq 1 ]; then
		echo "********** BUILDING WIN64 BINUTILS *************"
		confMake "$PREFIX_WIN64" "$OPTS_BINUTILS" --host=$HOST_WIN64 --build=`../config.guess`
	fi
	cd ../../
fi

# Make AVR-GCC
if [ $BUILD_GCC -eq 1 ]; then
	echo "Making GCC..."
	echo "Extracting..."
	tar xf $NAME_GCC.tar.xz
	mkdir -p $NAME_GCC/obj-avr
	cd $NAME_GCC
	chmod +x ./contrib/download_prerequisites
	./contrib/download_prerequisites
	cd obj-avr
	[ $BUILD_LINUX -eq 1 ] && confMake "$PREFIX_LINUX" "$OPTS_GCC"
	[ $BUILD_WIN32 -eq 1 ] && confMake "$PREFIX_WIN32" "$OPTS_GCC" --host=$HOST_WIN32 --build=`../config.guess`
	[ $BUILD_WIN64 -eq 1 ] && confMake "$PREFIX_WIN64" "$OPTS_GCC" --host=$HOST_WIN64 --build=`../config.guess`
	cd ../../
fi

# Make AVR-LibC
if [ $BUILD_LIBC -eq 1 ]; then
	echo "Making AVR-LibC..."
	if [ "$NAME_LIBC" != "avr-libc3.git" ]; then
		echo "Extracting..."
		bunzip2 -c $NAME_LIBC.tar.bz2 | tar xf -
	fi
	mkdir -p $NAME_LIBC/obj-avr
	cd $NAME_LIBC/obj-avr
	confMake "$PREFIX_LIBC" "$OPTS_LIBC" --host=avr --build=`../config.guess`
	cd ../../
fi

TIME_END=$(date +%s)
TIME_RUN=$(($TIME_END - $TIME_START))

echo ""
echo "Done in $TIME_RUN seconds"

exit 0
