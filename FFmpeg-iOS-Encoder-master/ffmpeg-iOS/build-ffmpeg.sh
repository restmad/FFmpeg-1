#!/bin/bash
#  Builds ffmpeg for all three current iPhone targets: iPhoneSimulator-i386,
#  iPhoneOS-armv7, iPhoneOS-armv7s.
#
#  FFmpeg modifications by Chris Ballinger
#  Copyright 2012 Chris Ballinger <chris@openwatch.net>
#  
#  Copyright 2012 Mike Tigas <mike@tig.as>
#
#  Based on work by Felix Schulze on 16.12.10.
#  Copyright 2010 Felix Schulze. All rights reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
###########################################################################
#  Choose your ffmpeg version and your currently-installed iOS SDK version:
#
VERSION="1.0"
SDKVERSION="6.0"
#
#
###########################################################################
#
# Don't change anything under this line!
#
###########################################################################

# No need to change this since xcode build will only compile in the
# necessary bits from the libraries we create
ARCHS="i386 armv7"

DEVELOPER=`xcode-select -print-path`

cd "`dirname \"$0\"`"
REPOROOT=$(pwd)

# Where we'll end up storing things in the end
OUTPUTDIR="${REPOROOT}/dependencies"
mkdir -p ${OUTPUTDIR}/include
mkdir -p ${OUTPUTDIR}/lib
mkdir -p ${OUTPUTDIR}/bin


BUILDDIR="${REPOROOT}/build"

# where we will keep our sources and build from.
SRCDIR="${BUILDDIR}/src"
mkdir -p $SRCDIR
# where we will store intermediary builds
INTERDIR="${BUILDDIR}/built"
mkdir -p $INTERDIR

########################################

cd $SRCDIR

# Exit the script if an error happens
set -e

if [ ! -e "${SRCDIR}/ffmpeg-${VERSION}.tar.bz2" ]; then
	echo "Downloading ffmpeg-${VERSION}.tar.bz2"
    curl -LO http://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.bz2
else
	echo "Using ffmpeg-${VERSION}.tar.bz2"
fi

tar zxf ffmpeg-${VERSION}.tar.bz2 -C $SRCDIR
cd "${SRCDIR}/ffmpeg-${VERSION}"

set +e # don't bail out of bash script if ccache doesn't exist
CCACHE=`which ccache`
if [ $? == "0" ]; then
    echo "Building with ccache: $CCACHE"
    CCACHE="${CCACHE} "
else
    echo "Building without ccache"
    CCACHE=""
fi
set -e # back to regular "bail out on error" mode

for ARCH in ${ARCHS}
do
	if [ "${ARCH}" == "i386" ];
	then
		PLATFORM="iPhoneSimulator"
        EXTRA_CONFIG="--arch=i386 --disable-asm"
        EXTRA_CFLAGS="-arch i386"
        EXTRA_LDFLAGS=""
	else
		PLATFORM="iPhoneOS"
        EXTRA_CONFIG="--arch=arm --target-os=darwin --enable-cross-compile --cpu=cortex-a8 --disable-armv5te"
        EXTRA_CFLAGS="-w -arch ${ARCH} -mfpu=neon"
        EXTRA_LDFLAGS="-mfpu=neon"
	fi

	mkdir -p "${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"

	./configure --disable-shared --enable-static --enable-pic \
    --disable-everything --enable-libvpx \
    --enable-encoder=vp8 --enable-decoder=vp8 --enable-encoder=libvpx --enable-decoder=libvpx --enable-encoder=mpeg1video --enable-encoder=mp2 \
    --enable-encoder=mpeg4 \
    --cc=${CCACHE}${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/usr/bin/gcc ${EXTRA_CONFIG} \
    --prefix="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk" \
    --sysroot=${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk \
    --extra-ldflags="-arch ${ARCH} ${EXTRA_LDFLAGS} -L${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk/usr/lib/system -isysroot=${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk $LDFLAGS -L${OUTPUTDIR}/lib" \
    --extra-cflags="$CFLAGS ${EXTRA_CFLAGS} -I${OUTPUTDIR}/include -isysroot ${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk" \
    --extra-cxxflags="$CPPFLAGS -I${OUTPUTDIR}/include -isysroot ${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk"

    # Build the application and install it to the fake SDK intermediary dir
    # we have set up. Make sure to clean up afterward because we will re-use
    # this source tree to cross-compile other targets.
	make -j2
	make install
	make clean
done

########################################

echo "Build library..."

# These are the libs that comprise ffmpeg.
OUTPUT_LIBS="libavcodec.a libavdevice.a libavformat.a libavutil.a libswscale.a"
for OUTPUT_LIB in ${OUTPUT_LIBS}; do
    INPUT_LIBS=""
    for ARCH in ${ARCHS}; do
        if [ "${ARCH}" == "i386" ];
        then
            PLATFORM="iPhoneSimulator"
        else
            PLATFORM="iPhoneOS"
        fi
        INPUT_ARCH_LIB="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/lib/${OUTPUT_LIB}"
        if [ -e $INPUT_ARCH_LIB ]; then
            INPUT_LIBS="${INPUT_LIBS} ${INPUT_ARCH_LIB}"
        fi
    done
    # Combine the three architectures into a universal library.
    if [ -n "$INPUT_LIBS"  ]; then
        lipo -create $INPUT_LIBS \
        -output "${OUTPUTDIR}/lib/${OUTPUT_LIB}"
    else
        echo "$OUTPUT_LIB does not exist, skipping (are the dependencies installed?)"
    fi
done

for ARCH in ${ARCHS}; do
    if [ "${ARCH}" == "i386" ];
    then
        PLATFORM="iPhoneSimulator"
    else
        PLATFORM="iPhoneOS"
    fi
    cp -R ${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/include/* ${OUTPUTDIR}/include/
    if [ $? == "0" ]; then
        # We only need to copy the headers over once. (So break out of forloop
        # once we get first success.)
        break
    fi
done

for ARCH in ${ARCHS}; do
    if [ "${ARCH}" == "i386" ];
    then
        PLATFORM="iPhoneSimulator"
    else
        PLATFORM="iPhoneOS"
    fi
    cp -R ${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/bin/* ${OUTPUTDIR}/bin/
    if [ $? == "0" ]; then
        # We only need to copy the binaries over once. (So break out of forloop
        # once we get first success.)
        break
    fi
done

####################

echo "Building done."
echo "Cleaning up..."
rm -fr ${INTERDIR}
rm -fr "${SRCDIR}/ffmpeg-${VERSION}"
echo "Done."
