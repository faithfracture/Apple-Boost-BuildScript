#!/bin/bash
#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
# Modified version
#===============================================================================
#
# Builds a Boost framework for iOS, iOS Simulator, tvOS, tvOS Simulator, and OSX.
# Creates a set of universal libraries that can be used on an iOS and in the
# iOS simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_VERSION:   Which version of Boost to build (e.g. 1.61.0)
#    BOOST_VERSION2:  Same as BOOST_VERSION, but with _ instead of . (e.g. 1_61_0)
#    BOOST_LIBS:      Which Boost libraries to build
#    IOS_SDK_VERSION: iOS SDK version (e.g. 9.0)
#    MIN_IOS_VERSION: Minimum iOS Target Version (e.g. 8.0)
#    OSX_SDK_VERSION: OSX SDK version (e.g. 10.11)
#    MIN_OSX_VERSION: Minimum OS X Target Version (e.g. 10.10)
#
# If a boost tarball (a file named “boost_$BOOST_VERSION2.tar.bz2”) does not
# exist in the current directory, this script will attempt to download the
# version specified by BOOST_VERSION2. You may also manually place a matching 
# tarball in the current directory and the script will use that.
#
#===============================================================================

BOOST_LIBS="atomic chrono date_time exception filesystem program_options random signals system thread test"

BUILD_IOS=
BUILD_TVOS=
BUILD_OSX=
CLEAN=
NO_CLEAN=
NO_FRAMEWORK=

BOOST_VERSION=1.61.0
BOOST_VERSION2=1_61_0

MIN_IOS_VERSION=8.0
IOS_SDK_VERSION=`xcrun --sdk iphoneos --show-sdk-version`

MIN_TVOS_VERSION=9.2
TVOS_SDK_VERSION=`xcrun --sdk appletvos --show-sdk-version`

MIN_OSX_VERSION=10.10
OSX_SDK_VERSION=`xcrun --sdk macosx --show-sdk-version`

OSX_ARCHS="x86_64"
OSX_ARCH_COUNT=0
OSX_ARCH_FLAGS=""
for ARCH in $OSX_ARCHS; do
    OSX_ARCH_FLAGS="$OSX_ARCH_FLAGS -arch $ARCH"
    ((OSX_ARCH_COUNT++))
done

# Applied to all platforms
CXX_FLAGS="-std=c++11 -stdlib=libc++"

XCODE_ROOT=`xcode-select -print-path`
COMPILER="$XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++" 

THREADS="-j8"

CURRENT_DIR=`pwd`
SRCDIR="$CURRENT_DIR/src"


IOS_ARM_DEV_CMD="xcrun --sdk iphoneos"
IOS_SIM_DEV_CMD="xcrun --sdk iphonesimulator"
TVOS_ARM_DEV_CMD="xcrun --sdk appletvos"
TVOS_SIM_DEV_CMD="xcrun --sdk appletvsimulator"
OSX_DEV_CMD="xcrun --sdk macosx"

#===============================================================================
# Functions
#===============================================================================

usage()
{
cat << EOF
usage: $0 [{-ios,-tvos,-osx} ...] options
Build Boost for iOS, iOS Simulator, tvOS, tvOS Simulator, and OS X
The -ios, -tvos, and -osx options may be specified together. Default
is to build all of them.

Examples:
    ./boost.sh -ios -tvos --boost-version 1.56.0
    ./boost.sh -osx --no-framework
    ./boost.sh --clean

OPTIONS:
    -h | --help
        Display these options and exit.

    -ios
        Build for the iOS platform.

    -osx
        Build for the OS X platform.

    -tvos
        Build for the tvOS platform.
    
    --boost-version [num]
        Specify which version of Boost to build. Defaults to $BOOST_VERSION.

    --boost-libs [libs]
        Specify which libraries to build. Space-separate list.
        Defaults to:
            $BOOST_LIBS
        Boost libraries requiring separate building are:
            - atomic
            - chrono
            - container
            - context
            - coroutine
            - coroutine2
            - date_time
            - exception
            - filesystem
            - graph
            - graph_parallel
            - iostreams
            - locale
            - log
            - math
            - metaparse
            - mpi
            - program_options
            - python
            - random
            - regex
            - serialization
            - signals
            - system
            - test
            - thread
            - timer
            - type_erasure
            - wave

    --ios-sdk [num]
        Specify the iOS SDK version to build with. Defaults to $IOS_SDK_VERSION.

    --min-ios-version [num]
        Specify the minimum iOS version to target.  Defaults to $MIN_IOS_VERSION.

    --tvos-sdk [num]
        Specify the tvOS SDK version to build with. Defaults to $TVOS_SDK_VERSION.

    --min-tvos_version [num]
        Specify the minimum tvOS version to target. Defaults to $MIN_TVOS_VERSION.

    --osx-sdk [num]
        Specify the OS X SDK version to build with. Defaults to $OSX_SDK_VERSION.

    --min-osx-version [num]
        Specify the minimum OS X version to target.  Defaults to $MIN_OSX_VERSION.

    --no-framework
        Do not create the framework.

    --clean
        Just clean up build artifacts, but don't actually build anything.
        (all other parameters are ignored)

    --no-clean
        Do not clean up existing build artifacts before building.

EOF
}

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

die()
{
    usage
    exit 1
}

missingParameter()
{
    echo $1 requires a parameter
    die
}

unknownParameter()
{
    if [[ -n $2 &&  $2 != "" ]]; then
        echo Unknown argument \"$2\" for parameter $1.
    else
        echo Unknown argument $1
    fi
    die
}

parseArgs()
{
    while [ "$1" != "" ]; do
        case $1 in
            -h | --help)
                usage
                exit
                ;;

            -ios)
                BUILD_IOS=1
                ;;

            -tvos)
                BUILD_TVOS=1
                ;;

            -osx)
                BUILD_OSX=1
                ;;

            --boost-version)
                if [ -n $2 ]; then
                    BOOST_VERSION=$2
                    BOOST_VERSION2="${BOOST_VERSION//./_}"
                    BOOST_TARBALL="$CURRENT_DIR/boost_$BOOST_VERSION2.tar.bz2"
                    BOOST_SRC="$SRCDIR/boost_${BOOST_VERSION2}"
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --boost-libs)
                if [ -n "$2" ]; then
                    BOOST_LIBS="$2"
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --ios-sdk)
                if [ -n $2 ]; then
                    IOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-ios-version)
                if [ -n $2 ]; then
                    MIN_IOS_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --tvos-sdk)
                if [ -n $2]; then
                    TVOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-tvos-version)
                if [ -n $2]; then
                    MIN_TVOS_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --osx-sdk)
                 if [ -n $2 ]; then
                    OSX_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-osx-version)
                if [ -n $2 ]; then
                    MIN_OSX_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --clean)
                CLEAN=1
                ;;

            --no-clean)
                NO_CLEAN=1
                ;;

            --no-framework)
                NO_FRAMEWORK=1
                ;;

            *)
                unknownParameter $1
                ;;
        esac

        shift
    done
}

doneSection()
{
    echo
    echo "Done"
    echo "================================================================="
    echo
}

#===============================================================================

cleanup()
{
    echo Cleaning everything

    if [[ -n $BUILD_IOS ]]; then
        rm -r "$BOOST_SRC/iphone-build"
        rm -r "$BOOST_SRC/iphonesim-build"
        rm -r "$IOSOUTPUTDIR"
    fi
    if [[ -n $BUILD_TVOS ]]; then
        rm -r "$BOOST_SRC/appletv-build"
        rm -r "$BOOST_SRC/appletvsim-build"
        rm -r "$TVOSOUTPUTDIR"
    fi
    if [[ -n $BUILD_OSX ]]; then
        rm -r "$BOOST_SRC/osx-build"
        rm -r "$OSXOUTPUTDIR"
    fi

    doneSection
}

#===============================================================================

downloadBoost()
{
    if [ ! -s $BOOST_TARBALL ]; then
        echo "Downloading boost ${BOOST_VERSION}"
        curl -L -o "$BOOST_TARBALL" \
            http://sourceforge.net/projects/boost/files/boost/${BOOST_VERSION}/boost_${BOOST_VERSION2}.tar.bz2/download
        doneSection
    fi
}

#===============================================================================

unpackBoost()
{
    [ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."

    echo Unpacking boost into "$SRCDIR"...

    [ -d $SRCDIR ]    || mkdir -p "$SRCDIR"
    [ -d $BOOST_SRC ] || ( cd "$SRCDIR"; tar xfj "$BOOST_TARBALL" )
    [ -d $BOOST_SRC ] && echo "    ...unpacked as $BOOST_SRC"

    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers

    cp "$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IOS_SDK_VERSION}.sdk/usr/include/"{crt_externs,bzlib}.h "$BOOST_SRC"
}

#===============================================================================

updateBoost()
{
    echo Updating boost into $BOOST_SRC...

    if [[ "$1" == "iOS" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${IOS_SDK_VERSION}~iphone
: $COMPILER -arch armv7 -arch arm64 $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${IOS_SDK_VERSION}~iphonesim
: $COMPILER -arch i386 -arch x86_64 $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
EOF
    fi

    if [[ "$1" == "tvOS" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${TVOS_SDK_VERSION}~appletv
: $COMPILER -arch arm64 $EXTRA_TVOS_FLAGS -I${XCODE_ROOT}/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS${TVOS_SDK_VERSION}.sdk/usr/include
: <striper> <root>$XCODE_ROOT/Platforms/AppleTVOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${TVOS_SDK_VERSION}~appletvsim
: $COMPILER -arch x86_64 $EXTRA_TVOS_FLAGS -I${XCODE_ROOT}/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator${TVOS_SDK_VERSION}.sdk/usr/include
: <striper> <root>$XCODE_ROOT/Platforms/AppleTVSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
EOF
    fi

    if [[ "$1" == "OSX" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${OSX_SDK_VERSION}
: $COMPILER $OSX_ARCH_FLAGS $EXTRA_OSX_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/MacOSX.platform/Developer
: <architecture>x86 <target-os>darwin
;
EOF
    fi

    doneSection
}

#===============================================================================

bootstrapBoost()
{
    cd $BOOST_SRC
    BOOTSTRAP_LIBS=$BOOST_LIBS
    if [[ "$1" == "tvOS" ]]; then
        # Boost Test makes a call that is not available on tvOS (as of 1.61.0)
        # If we're bootstraping for tvOS, just remove the test library
        BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e "s/test//g")
    fi

    BOOST_LIBS_COMMA=$(echo $BOOTSTRAP_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping for $1 (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA

    doneSection
}

#===============================================================================

buildBoost_iOS()
{
    cd "$BOOST_SRC"
    mkdir -p $IOSOUTPUTDIR

    echo Building Boost for iPhone
    # Install this one so we can copy the headers for the frameworks...
    ./b2 $THREADS --build-dir=iphone-build --stagedir=iphone-build/stage \
        --prefix="$IOSOUTPUTDIR/prefix" toolset=darwin cxxflags="${CXX_FLAGS}" architecture=arm target-os=iphone \
        macosx-version=iphone-${IOS_SDK_VERSION} define=_LITTLE_ENDIAN \
        link=static stage >> "${IOSOUTPUTDIR}/iphone-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging iPhone. Check log."; exit 1; fi
    
    ./b2 $THREADS --build-dir=iphone-build --stagedir=iphone-build/stage \
        --prefix="$IOSOUTPUTDIR/prefix" toolset=darwin cxxflags="${CXX_FLAGS}" architecture=arm \
        target-os=iphone macosx-version=iphone-${IOS_SDK_VERSION} \
        define=_LITTLE_ENDIAN link=static install >> "${IOSOUTPUTDIR}/iphone-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error installing iPhone. Check log."; exit 1; fi
    doneSection

    echo Building Boost for iPhoneSimulator
    ./b2 $THREADS --build-dir=iphonesim-build --stagedir=iphonesim-build/stage \
        toolset=darwin-${IOS_SDK_VERSION}~iphonesim cxxflags="${CXX_FLAGS}" architecture=x86 \
        target-os=iphone macosx-version=iphonesim-${IOS_SDK_VERSION} \
        link=static stage >> "${IOSOUTPUTDIR}/iphone-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging iPhoneSimulator. Check log."; exit 1; fi
    doneSection
}

buildBoost_tvOS()
{
    cd "$BOOST_SRC"
    mkdir -p $TVOSOUTPUTDIR

    echo Building Boost for AppleTV
    ./b2 $THREADS --build-dir=appletv-build --stagedir=appletv-build/stage \
        --prefix="$TVOSOUTPUTDIR/prefix" toolset=darwin-${TVOS_SDK_VERSION}~appletv \
        cxxflags="${CXX_FLAGS}" architecture=arm target-os=iphone define=_LITTLE_ENDIAN \
        link=static stage >> "${TVOSOUTPUTDIR}/tvos-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging AppleTV. Check log."; exit 1; fi

    ./b2 $THREADS --build-dir=appletv-build --stagedir=appletv-build/stage \
        --prefix="$TVOSOUTPUTDIR/prefix" toolset=darwin-${TVOS_SDK_VERSION}~appletv \
        cxxflags="${CXX_FLAGS}" architecture=arm target-os=iphone define=_LITTLE_ENDIAN \
        link=static install >> "${TVOSOUTPUTDIR}/tvos-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error installing AppleTV. Check log."; exit 1; fi
    doneSection

    echo Building Boost for AppleTVSimulator
    ./b2 $THREADS --build-dir=appletv-build --stagedir=appletvsim-build/stage \
        toolset=darwin-${TVOS_SDK_VERSION}~appletvsim architecture=x86 \
        cxxflags="${CXX_FLAGS}" target-os=iphone link=static stage >> "${TVOSOUTPUTDIR}/tvos-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging AppleTVSimulator. Check log."; exit 1; fi
    doneSection
}

buildBoost_OSX()
{
    cd "$BOOST_SRC"
    mkdir -p $OSXOUTPUTDIR

    echo building Boost for OSX
    ./b2 $THREADS --build-dir=osx-build --stagedir=osx-build/stage toolset=clang \
        --prefix="$OSXOUTPUTDIR/prefix" cxxflags="${CXX_FLAGS} ${OSX_ARCH_FLAGS}" \
        linkflags="-stdlib=libc++" link=static threading=multi \
        macosx-version=${OSX_SDK_VERSION} stage >> "${OSXOUTPUTDIR}/osx-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging OSX. Check log."; exit 1; fi

    ./b2 $THREADS --build-dir=osx-build --stagedir=osx-build/stage \
        --prefix="$OSXOUTPUTDIR/prefix" toolset=clang \
        cxxflags="${CXX_FLAGS} ${OSX_ARCH_FLAGS}" \
        linkflags="-stdlib=libc++" link=static threading=multi \
        macosx-version=${OSX_SDK_VERSION} install >> "${OSXOUTPUTDIR}/osx-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error installing OSX. Check log."; exit 1; fi

    doneSection
}

#===============================================================================

unpackArchive()
{
    BUILDDIR="$1"
    LIBNAME="$2"

    echo "Unpacking $BUILDDIR/$LIBNAME"

    if [[ -d "$BUILDDIR/$LIBNAME" ]]; then 
        cd "$BUILDDIR/$LIBNAME"
        rm *.o
        rm *.SYMDEF*
    else
        mkdir -p "$BUILDDIR/$LIBNAME"
    fi

    (
        cd "$BUILDDIR/$NAME"; ar -x "../../libboost_$NAME.a";
        for FILE in *.o; do
            NEW_FILE="${NAME}_${FILE}"
            mv "$FILE" "$NEW_FILE"
        done
    )
}

scrunchAllLibsTogetherInOneLibPerPlatform()
{
    cd "$BOOST_SRC"

    if [[ -n $BUILD_IOS ]]; then
        # iOS Device
        mkdir -p "$IOSBUILDDIR/armv7/obj"
        mkdir -p "$IOSBUILDDIR/arm64/obj"

        # iOS Simulator
        mkdir -p "$IOSBUILDDIR/i386/obj"
        mkdir -p "$IOSBUILDDIR/x86_64/obj"
    fi

    if [[ -n $BUILD_TVOS ]]; then
        # tvOS Device
        mkdir -p "$TVOSBUILDDIR/arm64/obj"

        # tvOS Simulator
        mkdir -p "$TVOSBUILDDIR/x86_64/obj"
    fi

    if [[ -n $BUILD_OSX ]]; then
        # OSX
        for ARCH in $OSX_ARCHS; do
            mkdir -p "$OSXBUILDDIR/$ARCH/obj"
        done
    fi

    ALL_LIBS=""

    echo Splitting all existing fat binaries...

    for NAME in $BOOST_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        ALL_LIBS="$ALL_LIBS libboost_$NAME.a"

        if [[ -n $BUILD_IOS ]]; then
            $IOS_ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" \
                -thin armv7 -o "$IOSBUILDDIR/armv7/libboost_$NAME.a"
            $IOS_ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" \
                -thin arm64 -o "$IOSBUILDDIR/arm64/libboost_$NAME.a"

            $IOS_SIM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" \
                -thin i386 -o "$IOSBUILDDIR/i386/libboost_$NAME.a"
            $IOS_SIM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" \
                -thin x86_64 -o "$IOSBUILDDIR/x86_64/libboost_$NAME.a"
        fi

        if [[ -n $BUILD_TVOS ]]; then
            $TVOS_ARM_DEV_CMD lipo "appletv-build/stage/lib/libboost_$NAME.a" \
                -thin arm64 -o "$TVOSBUILDDIR/arm64/libboost_$NAME.a"

            $TVOS_SIM_DEV_CMD lipo "appletvsim-build/stage/lib/libboost_$NAME.a" \
                -thin x86_64 -o "$TVOSBUILDDIR/x86_64/libboost_$NAME.a"
        fi

        if [[ -n $BUILD_OSX ]]; then
            if (( $OSX_ARCH_COUNT == 1 )); then
                cp "osx-build/stage/lib/libboost_$NAME.a" \
                    "$OSXBUILDDIR/$ARCH/libboost_$NAME.a"
            else
                for ARCH in $OSX_ARCHS; do
                    $OSX_DEV_CMD lipo "osx-build/stage/lib/libboost_$NAME.a" \
                        -thin $ARCH -o "$OSXBUILDDIR/$ARCH/libboost_$NAME.a"
                done
            fi
        fi
    done

    echo "Decomposing each architecture's .a files"

    for NAME in $BOOST_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        echo "Decomposing libboost_${NAME}.a"
        if [[ -n $BUILD_IOS ]]; then
            unpackArchive "$IOSBUILDDIR/armv7/obj" $NAME
            unpackArchive "$IOSBUILDDIR/arm64/obj" $NAME
            unpackArchive "$IOSBUILDDIR/i386/obj" $NAME
            unpackArchive "$IOSBUILDDIR/x86_64/obj" $NAME
        fi

        if [[ -n $BUILD_TVOS ]]; then
            unpackArchive "$TVOSBUILDDIR/arm64/obj" $NAME
            unpackArchive "$TVOSBUILDDIR/x86_64/obj" $NAME
        fi

        if [[ -n $BUILD_OSX ]]; then
            for ARCH in $OSX_ARCHS; do
                unpackArchive "$OSXBUILDDIR/$ARCH/obj" $NAME
            done
        fi
    done

    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
    if [[ -n $BUILD_IOS ]]; then
        cd "$IOSBUILDDIR"
        rm */libboost.a
    fi
    if [[ -n $BUILD_TVOS ]]; then
        cd "$TVOSBUILDDIR"
        rm */libboost.a
    fi
    if [[ -n $BUILD_OSX ]]; then
        for ARCH in $OSX_ARCHS; do
            rm "$OSXBUILDDIR/$ARCH/libboost.a"
        done
    fi

    for NAME in $BOOST_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        echo "Archiving $NAME"

        # The obj/$NAME/*.o below should all be quotet, but I couldn't figure out how to do that elegantly.
        # Boost lib names probably won't contain non-word characters any time soon, though. ;) - Jan

        if [[ -n $BUILD_IOS ]]; then
            echo ...armv7
            (cd "$IOSBUILDDIR/armv7"; $IOS_ARM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            echo ...arm64
            (cd "$IOSBUILDDIR/arm64"; $IOS_ARM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )

            echo ...i386
            (cd "$IOSBUILDDIR/i386";  $IOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            echo ...x86_64
            (cd "$IOSBUILDDIR/x86_64";  $IOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
        fi

        if [[ -n $BUILD_TVOS ]]; then
            echo ...tvOS-arm64
            (cd "$TVOSBUILDDIR/arm64"; $TVOS_ARM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            echo ...tvOS-x86_64
            (cd "$TVOSBUILDDIR/x86_64";  $TVOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
        fi

        if [[ -n $BUILD_OSX ]]; then
            for ARCH in $OSX_ARCHS; do
                echo ...osx-$ARCH
                (cd "$OSXBUILDDIR/$ARCH";  $OSX_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            done
        fi
    done
}

#===============================================================================
buildFramework()
{
    : ${1:?}
    FRAMEWORKDIR="$1"
    BUILDDIR="$2/build"
    PREFIXDIR="$2/prefix"

    VERSION_TYPE=Alpha
    FRAMEWORK_NAME=boost
    FRAMEWORK_VERSION=A

    FRAMEWORK_CURRENT_VERSION="$BOOST_VERSION"
    FRAMEWORK_COMPATIBILITY_VERSION="$BOOST_VERSION"

    FRAMEWORK_BUNDLE="$FRAMEWORKDIR/$FRAMEWORK_NAME.framework"
    echo "Framework: Building $FRAMEWORK_BUNDLE from $BUILDDIR..."

    rm -rf "$FRAMEWORK_BUNDLE"

    echo "Framework: Setting up directories..."
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources"
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers"
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation"

    echo "Framework: Creating symlinks..."
    ln -s "$FRAMEWORK_VERSION"               "$FRAMEWORK_BUNDLE/Versions/Current"
    ln -s "Versions/Current/Headers"         "$FRAMEWORK_BUNDLE/Headers"
    ln -s "Versions/Current/Resources"       "$FRAMEWORK_BUNDLE/Resources"
    ln -s "Versions/Current/Documentation"   "$FRAMEWORK_BUNDLE/Documentation"
    ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_BUNDLE/$FRAMEWORK_NAME"

    FRAMEWORK_INSTALL_NAME="$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME"

    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    cd "$BUILDDIR"
    if [[ -n $BUILD_IOS ]]; then
        $IOS_ARM_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi
    if [[ -n $BUILD_TVOS ]]; then
        $TVOS_ARM_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi
    if [[ -n $BUILD_OSX ]]; then
        $OSX_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi

    echo "Framework: Copying includes..."
    cd "$PREFIXDIR/include/boost"
    cp -r * "$FRAMEWORK_BUNDLE/Headers/"

    echo "Framework: Creating plist..."
    cat > "$FRAMEWORK_BUNDLE/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleExecutable</key>
<string>${FRAMEWORK_NAME}</string>
<key>CFBundleIdentifier</key>
<string>org.boost</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundlePackageType</key>
<string>FMWK</string>
<key>CFBundleSignature</key>
<string>????</string>
<key>CFBundleVersion</key>
<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF

    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

parseArgs "$@"

if [[ -z $BUILD_IOS && -z $BUILD_TVOS && -z $BUILD_OSX ]]; then
    BUILD_IOS=1
    BUILD_TVOS=1
    BUILD_OSX=1
fi

# The EXTRA_FLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

# Must set these after parseArgs to fill in overriden values
EXTRA_FLAGS="-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS -g -DNDEBUG \
    -fvisibility=hidden -fvisibility-inlines-hidden \
    -Wno-unused-local-typedef -fembed-bitcode"
EXTRA_IOS_FLAGS="$EXTRA_FLAGS -mios-version-min=$MIN_IOS_VERSION"
EXTRA_TVOS_FLAGS="$EXTRA_FLAGS -mtvos-version-min=$MIN_TVOS_VERSION"
EXTRA_OSX_FLAGS="$EXTRA_FLAGS -mmacosx-version-min=$MIN_OSX_VERSION"

BOOST_TARBALL="$CURRENT_DIR/boost_$BOOST_VERSION2.tar.bz2"
BOOST_SRC="$SRCDIR/boost_${BOOST_VERSION2}"
OUTPUT_DIR="$CURRENT_DIR/build/boost/$BOOST_VERSION"
IOSOUTPUTDIR="$OUTPUT_DIR/ios"
TVOSOUTPUTDIR="$OUTPUT_DIR/tvos"
OSXOUTPUTDIR="$OUTPUT_DIR/osx"
IOSBUILDDIR="$IOSOUTPUTDIR/build"
TVOSBUILDDIR="$TVOSOUTPUTDIR/build"
OSXBUILDDIR="$OSXOUTPUTDIR/build"
IOSLOG="> $IOSOUTPUTDIR/iphone.log 2>&1"
IOSFRAMEWORKDIR="$IOSOUTPUTDIR/framework"
TVOSFRAMEWORKDIR="$TVOSOUTPUTDIR/framework"
OSXFRAMEWORKDIR="$OSXOUTPUTDIR/framework"

format="%-20s %s\n"
format2="%-20s %s (%u)\n"
printf "$format" "BUILD_IOS:" $( [[ -n $BUILD_IOS ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_TVOS:" $( [[ -n $BUILD_TVOS ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_OSX:" $( [[ -n $BUILD_OSX ]] && echo "YES" || echo "NO")
printf "$format" "BOOST_VERSION:" "$BOOST_VERSION"
printf "$format" "IOS_SDK_VERSION:" "$IOS_SDK_VERSION"
printf "$format" "MIN_IOS_VERSION:" "$MIN_IOS_VERSION"
printf "$format" "TVOS_SDK_VERSION:" "$TVOS_SDK_VERSION"
printf "$format" "MIN_TVOS_VERSION:" "$MIN_TVOS_VERSION"
printf "$format" "OSX_SDK_VERSION:" "$OSX_SDK_VERSION"
printf "$format" "MIN_OSX_VERSION:" "$MIN_OSX_VERSION"
printf "$format2" "OSX_ARCHS:" "$OSX_ARCHS" $OSX_ARCH_COUNT
printf "$format" "BOOST_LIBS:" "$BOOST_LIBS"
printf "$format" "BOOST_SRC:" "$BOOST_SRC"
printf "$format" "IOSBUILDDIR:" "$IOSBUILDDIR"
printf "$format" "OSXBUILDDIR:" "$OSXBUILDDIR"
printf "$format" "IOSFRAMEWORKDIR:" "$IOSFRAMEWORKDIR"
printf "$format" "OSXFRAMEWORKDIR:" "$OSXFRAMEWORKDIR"
printf "$format" "XCODE_ROOT:" "$XCODE_ROOT"
echo

if [ -n "$CLEAN" ]; then
    cleanup
    exit
fi

if [ -z $NO_CLEAN ]; then
    cleanup
fi

downloadBoost
unpackBoost
inventMissingHeaders

if [[ -n $BUILD_IOS ]]; then
    updateBoost "iOS"
    bootstrapBoost "iOS"
    buildBoost_iOS
fi
if [[ -n $BUILD_TVOS ]]; then
    updateBoost "tvOS"
    bootstrapBoost "tvOS"
    buildBoost_tvOS
fi
if [[ -n $BUILD_OSX ]]; then
    updateBoost "OSX"
    bootstrapBoost "OSX"
    buildBoost_OSX
fi

scrunchAllLibsTogetherInOneLibPerPlatform

if [ -z $NO_FRAMEWORK ]; then
    if [[ -n $BUILD_IOS ]]; then
        buildFramework "$IOSFRAMEWORKDIR" "$IOSOUTPUTDIR"
    fi

    if [[ -n $BUILD_TVOS ]]; then
        buildFramework "$TVOSFRAMEWORKDIR" "$TVOSOUTPUTDIR"
    fi

    if [[ -n $BUILD_OSX ]]; then
        buildFramework "$OSXFRAMEWORKDIR" "$OSXOUTPUTDIR"
    fi
fi

echo "Completed successfully"
