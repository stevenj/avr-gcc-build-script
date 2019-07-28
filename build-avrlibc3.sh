#!/bin/bash
# Build Binutils ONLY
export BUILD_LINUX=1
export BUILD_WIN32=1
export BUILD_WIN64=1

export BUILD_BINUTILS=0
export BUILD_GCC=0
export BUILD_LIBC=1

./build.sh
