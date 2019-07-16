#!/bin/bash

# http://www.nongnu.org/avr-libc/user-manual/install_tools.html

# For optimum compile time this should generally be set to the number of CPU cores your machine has
JOBCOUNT=8

# Build Linux toolchain
# A Linux AVR-GCC toolchain is required to build a Windows toolchain
# If the Linux toolchain has already been built then you can set this to 0
BUILD_LINUX=1

# Build 32 bit Windows toolchain
BUILD_WIN32=0

# Build 64 bit Windows toolchain
BUILD_WIN64=0

# Build AVR-LibC
BUILD_LIBC=1

# Output locations for built toolchains
PREFIX_LINUX=/opt/AVR/linux
PREFIX_WIN32=/omgwtfbbq/win32
PREFIX_WIN64=/omgwtfbbq/win64
PREFIX_LIBC=/opt/AVR/libc

# Install packages
if hash apt-get 2>/dev/null; then
	# This works for Debian 8 and Ubuntu 16.04
	apt-get install wget make gcc g++ bzip2
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

# Stop on errors
set -e

NAME_BINUTILS="binutils-2.32"
NAME_GCC="gcc-9.1.0"
NAME_LIBC="avr-libc-SVN"

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

fixGCCAVR()
{
	# In GCC 7.1.0 there seems to be an issue with INT8_MAX and some other things being undefined in /gcc/config/avr/avr.c when building for Windows.
	# Adding '#include <stdint.h>' doesn't fix it, but manually defining the values does the trick.

	echo "Fixing missing defines..."

	DEFSFIX="
		#if (defined _WIN32 || defined __CYGWIN__)
		#define INT8_MIN (-128)
		#define INT16_MIN (-32768)
		#define INT8_MAX 127
		#define INT16_MAX 32767
		#define UINT8_MAX 0xff
		#define UINT16_MAX 0xffff
		#endif
	"

	ORIGINAL=$(cat ../gcc/config/avr/avr.c)
	echo "$DEFSFIX" > ../gcc/config/avr/avr.c
	echo "$ORIGINAL" >> ../gcc/config/avr/avr.c
}

echo "Clearing output directories..."
[ $BUILD_LINUX -eq 1 ] && makeDir "$PREFIX_LINUX"
[ $BUILD_WIN32 -eq 1 ] && makeDir "$PREFIX_WIN32"
[ $BUILD_WIN64 -eq 1 ] && makeDir "$PREFIX_WIN64"
[ $BUILD_LIBC -eq 1 ] && makeDir "$PREFIX_LIBC"

PATH="$PATH":"$PREFIX_LINUX"/bin
export PATH

CC=""
export CC

echo "Downloading sources..."
rm -f $NAME_BINUTILS.tar.xz
rm -rf $NAME_BINUTILS/
wget ftp://ftp.mirrorservice.org/sites/ftp.gnu.org/gnu/binutils/$NAME_BINUTILS.tar.xz
rm -f $NAME_GCC.tar.xz
rm -rf $NAME_GCC/
wget ftp://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/$NAME_GCC/$NAME_GCC.tar.xz
if [ $BUILD_LIBC -eq 1 ]; then
	rm -f $NAME_LIBC.tar.bz2
	rm -rf $NAME_LIBC/
	if [ "$NAME_LIBC" = "avr-libc-SVN" ]; then
		rm -f avrxmega3-v9.diff.bz2
		wget -O avrxmega3-v9.diff.bz2 https://savannah.nongnu.org/patch/download.php?file_id=45738
		svn co svn://svn.savannah.nongnu.org/avr-libc/trunk
		mv trunk/avr-libc $NAME_LIBC
		rm -rf trunk
		echo "Patching for XMEGA3 support"
		cat avrxmega3-v9.diff.bz2 | bzip2 -dc - | patch -d avr-libc-SVN -p0
		echo "Preparing"
		cd $NAME_LIBC
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
echo "Making Binutils..."
echo "Extracting..."
tar xf $NAME_BINUTILS.tar.xz
mkdir -p $NAME_BINUTILS/obj-avr
cd $NAME_BINUTILS/obj-avr
[ $BUILD_LINUX -eq 1 ] && confMake "$PREFIX_LINUX" "$OPTS_BINUTILS"
[ $BUILD_WIN32 -eq 1 ] && confMake "$PREFIX_WIN32" "$OPTS_BINUTILS" --host=$HOST_WIN32 --build=`../config.guess`
[ $BUILD_WIN64 -eq 1 ] && confMake "$PREFIX_WIN64" "$OPTS_BINUTILS" --host=$HOST_WIN64 --build=`../config.guess`
cd ../../

# Make AVR-GCC
echo "Making GCC..."
echo "Extracting..."
tar xf $NAME_GCC.tar.xz
mkdir -p $NAME_GCC/obj-avr
cd $NAME_GCC
chmod +x ./contrib/download_prerequisites
./contrib/download_prerequisites
cd obj-avr
# fixGCCAVR
[ $BUILD_LINUX -eq 1 ] && confMake "$PREFIX_LINUX" "$OPTS_GCC"
[ $BUILD_WIN32 -eq 1 ] && confMake "$PREFIX_WIN32" "$OPTS_GCC" --host=$HOST_WIN32 --build=`../config.guess`
[ $BUILD_WIN64 -eq 1 ] && confMake "$PREFIX_WIN64" "$OPTS_GCC" --host=$HOST_WIN64 --build=`../config.guess`
cd ../../

# Make AVR-LibC
if [ $BUILD_LIBC -eq 1 ]; then
	echo "Making AVR-LibC..."
	if [ "$NAME_LIBC" != "avr-libc-SVN" ]; then
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

