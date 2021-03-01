#!/bin/bash
#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
# Modified version
#===============================================================================
#
# Builds a Boost framework for iOS, iOS Simulator, tvOS, tvOS Simulator, and macOS.
# Creates a set of universal libraries that can be used on an iOS and in the
# iOS simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_VERSION:   Which version of Boost to build (e.g. 1.69.0)
#    BOOST_LIBS:      Which Boost libraries to build
#    IOS_SDK_VERSION: iOS SDK version (e.g. 12.0)
#    MIN_IOS_VERSION: Minimum iOS Target Version (e.g. 11.0)
#    TVOS_SDK_VERSION: iOS SDK version (e.g. 12.0)
#    MIN_TVOS_VERSION: Minimum iOS Target Version (e.g. 11.0)
#    MACOS_SDK_VERSION: macOS SDK version (e.g. 10.14)
#    MIN_MACOS_VERSION: Minimum macOS Target Version (e.g. 10.12)
#    MACOS_SILICON_SDK_VERSION: macOS SDK version for Apple Silicon (e.g. 11.0)
#    MIN_MACOS_SILICON_VERSION: Minimum macOS Target Version for Apple Silicon (e.g. 11.0)
#    MAC_CATALYST_SDK_VERSION: macOS SDK version when building a Mac Catalyst app (e.g. 10.15)
#    MIN_MAC_CATALYST_VERSION: Minimum iOS Target Version when building a Mac Catalyst app (e.g. 13.0)
#
# If a boost tarball (a file named “boost_$BOOST_VERSION2.tar.bz2”) does not
# exist in the current directory, this script will attempt to download the
# version specified. You may also manually place a matching
# tarball in the current directory and the script will use that.
#
#===============================================================================

BOOST_VERSION=1.73.0

BOOST_LIBS="atomic chrono date_time exception filesystem program_options random system thread test"
ALL_BOOST_LIBS_1_68="atomic chrono container context coroutine coroutine2
date_time exception fiber filesystem graph graph_parallel iostreams locale log
math metaparse mpi program_options python random regex serialization signals
system test thread timer type_erasure wave"
ALL_BOOST_LIBS_1_69="atomic chrono container context coroutine coroutine2
date_time exception fiber filesystem graph graph_parallel iostreams locale log
math metaparse mpi program_options python random regex serialization signals2
system test thread timer type_erasure wave"
BOOTSTRAP_LIBS=""

MIN_IOS_VERSION=11.0
MIN_TVOS_VERSION=11.0
MIN_MACOS_VERSION=10.12
MIN_MACOS_SILICON_VERSION=11
MACOS_SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
MACOS_SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
MIN_MAC_CATALYST_VERSION=13.0

MACOS_ARCHS=("i386" "x86_64")
MACOS_SILICON_ARCHS=("arm64")
IOS_ARCHS=("armv7" "arm64")
IOS_SIM_ARCHS=("i386" "x86_64")
MAC_CATALYST_ARCHS=("x86_64")

# Applied to all platforms
CXX_FLAGS=""
LD_FLAGS=""
OTHER_FLAGS="-std=c++14 -stdlib=libc++ -DNDEBUG"

XCODE_VERSION=$(xcrun xcodebuild -version | head -n1 | tr -Cd '[:digit:].')
XCODE_ROOT=$(xcode-select -print-path)
COMPILER="$XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"

THREADS="-j$(sysctl -n hw.ncpu)"

CURRENT_DIR=$(pwd)
SRCDIR="$CURRENT_DIR/src"

IOS_DEV_CMD="xcrun --sdk iphoneos"
IOS_SIM_DEV_CMD="xcrun --sdk iphonesimulator"
TVOS_DEV_CMD="xcrun --sdk appletvos"
TVOS_SIM_DEV_CMD="xcrun --sdk appletvsimulator"
MACOS_DEV_CMD="xcrun --sdk macosx"
MACOS_SILICON_DEV_CMD="xcrun --sdk macosx"
MAC_CATALYST_DEV_CMD="xcrun --sdk macosx"

BUILD_VARIANT=release

#===============================================================================
# Functions
#===============================================================================

sdkVersion()
{
    FULL_VERSION=$(xcrun --sdk "$1" --show-sdk-version)
    read -ra VERSION <<< "${FULL_VERSION//./ }"
    echo "${VERSION[0]}.${VERSION[1]}"
}

IOS_SDK_VERSION=$(sdkVersion iphoneos)
TVOS_SDK_VERSION=$(sdkVersion appletvos)
MACOS_SDK_VERSION=$(sdkVersion macosx)
MACOS_SILICON_SDK_VERSION=$(sdkVersion macosx)
MAC_CATALYST_SDK_VERSION=$(sdkVersion macosx)

sdkPath()
{
    xcrun --sdk "$1" --show-sdk-path
}

IOS_SDK_PATH=$(sdkPath iphoneos)
IOSSIM_SDK_PATH=$(sdkPath iphonesimulator)
TVOS_SDK_PATH=$(sdkPath appletvos)
TVOSSIM_SDK_PATH=$(sdkPath appletvsimulator)
MACOS_SDK_PATH=$(sdkPath macosx)
MAC_CATALYST_SDK_PATH=$(sdkPath macosx)
MACOS_SILICON_SDK_PATH=$(sdkPath macosx)

usage()
{
cat << EOF
usage: $0 [{-ios,-tvos,-macos} ...] options
Build Boost for iOS, iOS Simulator, tvOS, tvOS Simulator, and macOS
The -ios, -tvos, and -macOS options may be specified together. Default
is to build all of them.

Examples:
    ./boost.sh -ios -tvos --boost-version 1.68.0
    ./boost.sh -macos --no-framework
    ./boost.sh --clean

OPTIONS:
    -h | --help
        Display these options and exit.

    -ios
        Build for the iOS platform.

    -macos
        Build for the macOS platform.

    -tvos
        Build for the tvOS platform.

    -mac-catalyst
        Build for the Mac Catalyst platform (UIKit on Mac).

    --boost-version [num]
        Specify which version of Boost to build.
        Defaults to $BOOST_VERSION.

    --boost-libs "{all|none|(lib, ...)}"
        Specify which libraries to build. Space-separate list. Pass 'all' to
        build all optional libraries. Pass 'none' to skip building optional
        libraries.
        Defaults to: $BOOST_LIBS

        Boost libraries requiring separate building are:
            - atomic
            - chrono
            - container (Unavailable on tvOS)
            - context   (macOS only)
            - coroutine (macOS only)
            - coroutine2    (macOS only)
            - date_time
            - exception
            - fiber     (No complaints when building for iOS / tvOS, but no library is output)
            - filesystem
            - graph
            - graph_parallel    (No complaints when building for iOS / tvOS, but no library is output)
            - iostreams
            - locale
            - log
            - math  (Unavailable* on iOS, tvOS)
            - metaparse (Unavailable on tvOS)
            - mpi   (macOS only. Requires mpic++ (openmpi))
            - program_options
            - python
            - random
            - regex
            - serialization
            - signals
            - system
            - test      (Unavailable on tvOS)
            - thread
            - timer
            - type_erasure
            - wave

        NOTE:
        Unsupported and unavailable libraries are ignored when building for the
        platforms they are unsupported on. It's OK to pass them as arguments,
        just be aware that they will not be built for those platforms.

        Several libraries are unavailable on tvOS only because they make calls
        that are not available in tvOS.

        There are a couple of libraries that *appear* to build successfully for
        iOS and / or tvOS, but there is no library output, so I don't know that
        they are actually built for those platforms. I don't use them so I can't
        say for certain. If you find out one way or the other, please let me
        know so I can update this.

        * math fails for iOS and tvOS with a complaint about using a PCH with
        multiple architectures defined. I don't know how to get around this if
        you need a specific architecture (like arm64), since the only RISC
        option for the <architeciture> jamfile feature tag is 'arm'. I'm sure
        there's a way to get this working by tweaking user-config, but I haven't
        the time to figure it out now.

    --ios-sdk [num]
        Specify the iOS SDK version to build with.
        Defaults to $IOS_SDK_VERSION

    --min-ios-version [num]
        Specify the minimum iOS version to target. Since iOS 11+ are 64-bit only,
        if the minimum iOS version is set to iOS 11.0 or later, iOS archs is
        automatically set to 'arm64' and iOS Simulator archs is set to "x86_64",
        unless '--ios-archs' is also specified.
        Defaults to $MIN_IOS_VERSION

    --ios-archs "(archs, ...)"
        Specify the iOS architectures to build for. Also updates the iOS Simulator
        architectures to match. Space-separate list.

    --tvos-sdk [num]
        Specify the tvOS SDK version to build with.
        Defaults to $TVOS_SDK_VERSION

    --min-tvos_version [num]
        Specify the minimum tvOS version to target.
        Defaults to $MIN_TVOS_VERSION

    --macos-sdk [num]
        Specify the macOS SDK version to build with.
        Defaults to $MACOS_SDK_VERSION

    --macos-silicon-sdk
        Specify the macOS SDK version to build Apple Silicon binaries with.
        Defaults to $MACOS_SILICON_SDK_VERSION

    --min-macos-version [num]
        Specify the minimum macOS version to target.
        Defaults to $MIN_MACOS_VERSION

    --min-macos-silicon-version [NUM]
        Specify the minimum macOS Apple Silicon version to target.
        Defaults to $MIN_MACOS_SILICON_VERSION

    --macos-archs "(archs, ...)"
        Specify the macOS architectures to build for. Space-separate list.
        Defaults to ${MACOS_ARCHS[*]}

    --macos-silicon-archs "(archs, ...)"
        Specify the macOS Apple Silicon architectures to build for. Space-separate list.
        Defaults to ${MACOS_SILICON_ARCHS[*]}
    --mac-catalyst-sdk [num]
        Specify the macOS SDK version to build the Mac Catalyst slice with.
        Defaults to $MAC_CATALYST_SDK_VERSION

    --min-mac-catalyst-version [num]
        Specify the minimum iOS version to target for the Mac Catalyst slice.
        Defaults to $MIN_MAC_CATALYST_VERSION

    --mac-catalyst-archs "(archs, ...)"
        Specify the Mac Catalyst architectures to build for. Space-separate list.
        Defaults to ${MAC_CATALYST_ARCHS[*]}

    --hidden-visibility
        Compile using -fvisibility=hidden and -fvisibility-inlines-hidden

    --no-framework
        Do not create the xcframework.

    --universal
        Create universal FAT binary.

    --debug
        Build a debug variant.

    --clean
        Just clean up build artifacts, but don't actually build anything.
        (all other parameters are ignored)

    --purge
        Removes everything (build directory, src, Boost tarball, etc.).
        Similar to --clean, but more thorough.

    --no-clean
        Do not clean up existing build artifacts before building.

    -j | --threads [num]
        Specify the number of threads to use.
        Defaults to $THREADS

EOF
}

abort()
{
    echo
    echo "Aborted:" "$@"
    exit 1
}

die()
{
    usage
    exit 1
}

cd_or_abort()
{
    cd "$1" || abort "Could not change directory into \"$1\""
}

missingParameter()
{
    echo "$1 requires a parameter"
    die
}

unknownParameter()
{
    if [[ -n $2 &&  $2 != "" ]]; then
        echo "Unknown argument \"$2\" for parameter $1."
    else
        echo "Unknown argument $1"
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

            -macos)
                BUILD_MACOS=1
                ;;

            -macossilicon)
                BUILD_MACOS_SILICON=1
                ;;

            -mac-catalyst)
                BUILD_MAC_CATALYST=1
                ;;

            --boost-version)
                if [ -n "$2" ]; then
                    BOOST_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --boost-libs)
                if [ -n "$2" ]; then
                    CUSTOM_LIBS=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --ios-sdk)
                if [ -n "$2" ]; then
                    IOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --min-ios-version)
                if [ -n "$2" ]; then
                    MIN_IOS_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --ios-archs)
                if [ -n "$2" ]; then
                    CUSTOM_IOS_ARCHS=$2
                    shift;
                else
                    missingParameter "$1"
                fi
                ;;

            --tvos-sdk)
                if [ -n "$2" ]; then
                    TVOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --min-tvos-version)
                if [ -n "$2" ]; then
                    MIN_TVOS_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --macos-sdk)
                 if [ -n "$2" ]; then
                    MACOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --macos-silicon-sdk)
                 if [ -n "$2" ]; then
                    MACOS_SILICON_SDK_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --min-macos-version)
                if [ -n "$2" ]; then
                    MIN_MACOS_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --min-macos-silicon-version)
                if [ -n "$2" ]; then
                    MIN_MACOS_SILICON_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --macos-archs)
                if [ -n "$2" ]; then
                    CUSTOM_MACOS_ARCHS=$2
                    shift;
                else
                    missingParameter "$1"
                fi
                ;;

            --macos-silicon-archs)
                if [ -n "$2" ]; then
                    CUSTOM_MACOS_SILICON_ARCHS=$2
                else
                    missingParameter "$1"
                fi
                ;;

            --mac-catalyst-sdk)
                 if [ -n "$2" ]; then
                    MAC_CATALYST_SDK_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --min-mac-catalyst-version)
                if [ -n "$2" ]; then
                    MIN_MAC_CATALYST_VERSION=$2
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            --mac-catalyst-archs)
                if [ -n "$2" ]; then
                    CUSTOM_MAC_CATALYST_ARCHS=$2
                    shift;
                else
                    missingParameter "$1"
                fi
                ;;

            --hidden-visibility)
                CXX_FLAGS="$CXX_FLAGS -fvisibility=hidden -fvisibility-inlines-hidden"
                ;;

            --universal)
                UNIVERSAL=1
                ;;

            --debug)
                BUILD_VARIANT=debug
                ;;

            --clean)
                CLEAN=1
                ;;

            --purge)
                PURGE=1
                ;;

            --no-clean)
                NO_CLEAN=1
                ;;

            --no-framework)
                NO_FRAMEWORK=1
                ;;

            -j | --threads)
                if [ -n "$2" ]; then
                    THREADS="-j$2"
                    shift
                else
                    missingParameter "$1"
                fi
                ;;

            *)
                unknownParameter "$1"
                ;;
        esac

        shift
    done

    if [[ -n $CUSTOM_LIBS ]]; then
        if [[ "$CUSTOM_LIBS" == "none" ]]; then
            CUSTOM_LIBS=""
        elif [[ "$CUSTOM_LIBS" == "all" ]]; then
            read -ra BOOST_PARTS <<< "${BOOST_VERSION//./ }"
            if [[ ${BOOST_PARTS[1]} -lt 69 ]]; then
                CUSTOM_LIBS=$ALL_BOOST_LIBS_1_68
            else
                CUSTOM_LIBS=$ALL_BOOST_LIBS_1_69
            fi
        fi
        BOOST_LIBS=$CUSTOM_LIBS
    fi

    # Force 32/64-bit architecture when building universal macOS.
    # Forcing i386 & x86_64 is fine for now, but if macOS ever supports
    # other architectures in the future we'll need to be a bit smarter
    # about this.
    if [[ -n $BUILD_MACOS && -n $UNIVERSAL ]]; then
        CUSTOM_MACOS_ARCHS=("i386 x86_64")
    fi

    if [[ "${#CUSTOM_MACOS_ARCHS[@]}" -gt 0 ]]; then
        read -ra MACOS_ARCHS <<< "${CUSTOM_MACOS_ARCHS[@]}"
    fi

    if [[ "${#CUSTOM_MACOS_SILICON_ARCHS[@]}" -gt 0 ]]; then
        read -ra MACOS_SILICON_ARCHS <<< "${CUSTOM_MACOS_SILICON_ARCHS[@]}"
    fi

    if [[ "${#CUSTOM_MAC_CATALYST_ARCHS[@]}" -gt 0 ]]; then
        read -ra MAC_CATALYST_ARCHS <<< "${CUSTOM_MAC_CATALYST_ARCHS[@]}"
    fi

    if [[ "${#CUSTOM_IOS_ARCHS[@]}" -gt 0 ]]; then
        read -ra IOS_ARCHS <<< "${CUSTOM_IOS_ARCHS[@]}"
        IOS_SIM_ARCHS=()
        # As of right now this matches the currently available ARM architectures
        # Add 32-bit simulator for 32-bit arm
        if [[ "${IOS_ARCHS[*]}" =~ armv ]]; then
            IOS_SIM_ARCHS+=("i386")
        fi
        # Add 64-bit simulator for 64-bit arm
        if [[ "${IOS_ARCHS[*]}" =~ arm64 ]]; then
            IOS_SIM_ARCHS+=("x86_64")
        fi
    else
        read -ra MIN_IOS_PARTS <<< "${MIN_IOS_VERSION//./ }"
        if [[ ${MIN_IOS_PARTS[0]} -ge 11 ]]; then
            # iOS 11 dropped support for 32bit devices
            IOS_ARCHS=("arm64")
            IOS_SIM_ARCHS=("x86_64")
        fi
    fi
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
        rm -r "$IOS_OUTPUT_DIR"
    fi
    if [[ -n $BUILD_TVOS ]]; then
        rm -r "$BOOST_SRC/appletv-build"
        rm -r "$BOOST_SRC/appletvsim-build"
        rm -r "$TVOS_OUTPUT_DIR"
    fi
    if [[ -n $BUILD_MACOS ]]; then
        rm -r "$BOOST_SRC/macos-build"
        rm -r "$MACOS_OUTPUT_DIR"
    fi
    if [[ -n $BUILD_MACOS_SILICON ]]; then
        rm -r "$BOOST_SRC/macos-silicon-build"
        rm -r "$MACOS_SILICON_OUTPUT_DIR"
    fi
    if [[ -n $BUILD_MACOS ]] || [[ -n $BUILD_MACOS_SILICON ]] ; then
        rm -r "$MACOS_COMBINED_OUTPUT_DIR"
    fi
    if [[ -n $BUILD_MAC_CATALYST ]]; then
        rm -r "$BOOST_SRC/mac-catalyst-build"
        rm -r "$MAC_CATALYST_OUTPUT_DIR"
    fi

    doneSection
}

#===============================================================================

# version() from https://stackoverflow.com/a/37939589/3938401
version() { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

downloadBoost()
{
    if [ "$(version "$BOOST_VERSION")" -ge "$(version "1.63.0")" ]; then
        DOWNLOAD_SRC=https://dl.bintray.com/boostorg/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION2}.tar.bz2
    else
        DOWNLOAD_SRC=http://sourceforge.net/projects/boost/files/boost/${BOOST_VERSION}/boost_${BOOST_VERSION2}.tar.bz2/download
    fi
    if [ ! -s "$BOOST_TARBALL" ]; then
        echo "Downloading boost ${BOOST_VERSION} from ${DOWNLOAD_SRC}"
        curl -L -o "$BOOST_TARBALL" "$DOWNLOAD_SRC"
        doneSection
    fi
}

#===============================================================================

unpackBoost()
{
    [ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."

    echo Unpacking boost into "$SRCDIR"...

    [ -d "$SRCDIR" ]    || mkdir -p "$SRCDIR"
    [ -d "$BOOST_SRC" ] || ( cd_or_abort "$SRCDIR"; tar xjf "$BOOST_TARBALL" )
    [ -d "$BOOST_SRC" ] && echo "    ...unpacked as $BOOST_SRC"

    doneSection
}

#===============================================================================

patchBoost()
{
    BOOST_BUILD_DIR="$BOOST_SRC/tools/build"
    if [ "$(version "$BOOST_VERSION")" -le "$(version "1.73.0")" ] &&
       [ "$(version "$XCODE_VERSION")" -ge "$(version "11.4")" ]
    then
        echo "Patching boost in $BOOST_SRC"

        # https://github.com/boostorg/build/pull/560
        (cd "$BOOST_SRC" && patch --forward -p1 -d "$BOOST_BUILD_DIR" < "$CURRENT_DIR/patches/xcode-11.4.patch")

        doneSection
    fi

    # fixes boost passing `-arch arm` to linker which fails due to attempt to use armv4t
    sed -i '' -e "s/options = -arch arm ;/#options = -arch arm ;/" "$BOOST_BUILD_DIR/src/tools/darwin.jam"
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo "Inventing missing headers"

    cp "$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IOS_SDK_VERSION}.sdk/usr/include/"{crt_externs,bzlib}.h "$BOOST_SRC"

    doneSection
}

#===============================================================================

updateBoost()
{
    echo "Updating boost into $BOOST_SRC..."

    USING_MPI=
    if [[ $BOOST_LIBS == *"mpi"* ]]; then
        USING_MPI="using mpi ;" # trailing space needed
    fi

    COMMON_FLAGS_IOS="$OTHER_FLAGS ${IOS_ARCH_FLAGS[*]} $EXTRA_IOS_FLAGS -isysroot $IOS_SDK_PATH"
    COMMON_FLAGS_IOS_SIM="$OTHER_FLAGS ${IOS_SIM_ARCH_FLAGS[*]} $EXTRA_IOS_SIM_FLAGS -isysroot $IOSSIM_SDK_PATH"

    COMMON_FLAGS_TVOS="$OTHER_FLAGS -arch arm64 $EXTRA_TVOS_FLAGS -isysroot $TVOS_SDK_PATH"
    COMMON_FLAGS_TVOS_SIM="$OTHER_FLAGS -arch x86_64 $EXTRA_TVOS_SIM_FLAGS -isysroot $TVOSSIM_SDK_PATH"

    cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : $COMPILER_VERSION~iphone
: $COMPILER
: <architecture>arm
  <target-os>iphone
  <cxxflags>"$CXX_FLAGS $COMMON_FLAGS_IOS"
  <linkflags>"$LD_FLAGS $COMMON_FLAGS_IOS"
  <compileflags>"$COMMON_FLAGS_IOS"
  <threading>multi

;
using darwin : $COMPILER_VERSION~iphonesim
: $COMPILER
: <architecture>x86
  <target-os>iphone
  <cxxflags>"$CXX_FLAGS $COMMON_FLAGS_IOS_SIM"
  <linkflags>"$LD_FLAGS $COMMON_FLAGS_IOS_SIM"
  <compileflags>"$COMMON_FLAGS_IOS_SIM"
  <threading>multi
;
using darwin : $COMPILER_VERSION~appletv
: $COMPILER
: <architecture>arm
  <target-os>iphone
  <cxxflags>"$CXX_FLAGS $COMMON_FLAGS_TVOS"
  <linkflags>"$LD_FLAGS $COMMON_FLAGS_TVOS"
  <compileflags>"$COMMON_FLAGS_TVOS"
  <threading>multi
;
using darwin : $COMPILER_VERSION~appletvsim
: $COMPILER
: <architecture>x86
  <target-os>iphone
  <cxxflags>"$CXX_FLAGS $COMMON_FLAGS_TVOS_SIM"
  <linkflags>"$LD_FLAGS $COMMON_FLAGS_TVOS_SIM"
  <compileflags>"$COMMON_FLAGS_TVOS_SIM"
  <threading>multi
;
using darwin : $COMPILER_VERSION~macos
: $COMPILER
: <architecture>x86
  <target-os>darwin
  <cxxflags>"$CXX_FLAGS"
  <linkflags>"$LD_FLAGS"
  <compileflags>"$OTHER_FLAGS ${MACOS_ARCH_FLAGS[*]} $EXTRA_MACOS_FLAGS -isysroot $MACOS_SDK_PATH"
  <threading>multi
;
using darwin : $COMPILER_VERSION~macossilicon
: $COMPILER
: <architecture>arm
  <target-os>darwin
  <cxxflags>"$CXX_FLAGS"
  <linkflags>"$LD_FLAGS"
  <compileflags>"$OTHER_FLAGS ${MACOS_SILICON_ARCH_FLAGS[*]} $EXTRA_MACOS_SILICON_FLAGS -isysroot $MACOS_SILICON_SDK_PATH" -target arm64-apple-macos$MIN_MACOS_SILICON_VERSION
;
using darwin : $COMPILER_VERSION~maccatalyst
: $COMPILER
: <architecture>x86
  <target-os>darwin
  <cxxflags>"$CXX_FLAGS"
  <linkflags>"$LD_FLAGS"
  <compileflags>"$OTHER_FLAGS ${MAC_CATALYST_ARCH_FLAGS[*]} $EXTRA_MAC_CATALYST_FLAGS -isysroot $MAC_CATALYST_SDK_PATH -target x86_64-apple-ios$MIN_MAC_CATALYST_VERSION-macabi"
  <threading>multi
;
$USING_MPI
EOF

    doneSection
}

#===============================================================================

bootstrapBoost()
{
    cd_or_abort "$BOOST_SRC"
    if [[ -z $BOOST_LIBS ]]; then
        ./bootstrap.sh --without-libraries="${ALL_BOOST_LIBS// /,}"
    else
        BOOTSTRAP_LIBS=$BOOST_LIBS
        # Strip out unsupported / unavailable libraries
        if [[ "$1" == "iOS" ]]; then
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//context/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//coroutine/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//coroutine2/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//math/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//mpi/}"
        fi

        if [[ "$1" == "tvOS" ]]; then
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//container/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//context/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//coroutine/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//coroutine2/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//math/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//metaparse/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//mpi/}"
            BOOTSTRAP_LIBS="${BOOTSTRAP_LIBS//test/}"
        fi

        echo "Bootstrap libs ${BOOTSTRAP_LIBS}"
        BOOST_LIBS_COMMA="${BOOTSTRAP_LIBS// /,}"
        echo "Bootstrapping for $1 (with libs $BOOST_LIBS_COMMA)"
        ./bootstrap.sh --with-libraries="$BOOST_LIBS_COMMA"
    fi

    doneSection
}

#===============================================================================

buildBoost_iOS()
{
    cd_or_abort "$BOOST_SRC"
    mkdir -p "$IOS_OUTPUT_DIR"

    echo Building Boost for iPhone
    # Install this one so we can copy the headers for the frameworks...
    ./b2 "$THREADS" \
        --build-dir=iphone-build \
        --stagedir=iphone-build/stage \
        --prefix="$IOS_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~iphone" \
        link=static \
        variant=${BUILD_VARIANT} \
        stage >> "${IOS_OUTPUT_DIR}/ios-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error staging iPhone. Check log."; exit 1; fi

    ./b2 "$THREADS" \
        --build-dir=iphone-build \
        --stagedir=iphone-build/stage \
        --prefix="$IOS_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~iphone" \
        link=static \
        variant=${BUILD_VARIANT} \
        install >> "${IOS_OUTPUT_DIR}/ios-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error installing iPhone. Check log."; exit 1; fi
    doneSection

    echo Building Boost for iPhoneSimulator
    ./b2 "$THREADS"  \
        --build-dir=iphonesim-build \
        --stagedir=iphonesim-build/stage \
        toolset="darwin-$COMPILER_VERSION~iphonesim" \
        link=static \
        variant=${BUILD_VARIANT} \
        stage >> "${IOS_OUTPUT_DIR}/ios-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error staging iPhoneSimulator. Check log."; exit 1; fi
    doneSection
}

buildBoost_tvOS()
{
    cd_or_abort "$BOOST_SRC"
    mkdir -p "$TVOS_OUTPUT_DIR"

    echo Building Boost for AppleTV
    ./b2 "$THREADS" \
        --build-dir=appletv-build \
        --stagedir=appletv-build/stage \
        --prefix="$TVOS_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~appletv" \
        link=static \
        variant=${BUILD_VARIANT} \
        stage >> "${TVOS_OUTPUT_DIR}/tvos-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error staging AppleTV. Check log."; exit 1; fi

    ./b2 "$THREADS" \
        --build-dir=appletv-build \
        --stagedir=appletv-build/stage \
        --prefix="$TVOS_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~appletv" \
        link=static \
        variant=${BUILD_VARIANT} \
        install >> "${TVOS_OUTPUT_DIR}/tvos-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error installing AppleTV. Check log."; exit 1; fi
    doneSection

    echo "Building Boost for AppleTVSimulator"
    ./b2 "$THREADS"  \
        --build-dir=appletvsim-build \
        --stagedir=appletvsim-build/stage \
        --prefix="$TVOS_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~appletvsim" \
        link=static \
        variant=${BUILD_VARIANT} \
        stage >> "${TVOS_OUTPUT_DIR}/tvos-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error staging AppleTVSimulator. Check log."; exit 1; fi
    doneSection
}

buildBoost_macOS()
{
    cd_or_abort "$BOOST_SRC"
    mkdir -p "$MACOS_OUTPUT_DIR"

    echo building Boost for macOS
    ./b2 "$THREADS" \
        --build-dir=macos-build \
        --stagedir=macos-build/stage \
        --prefix="$MACOS_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~macos" \
        link=static \
        variant=${BUILD_VARIANT} \
        stage >> "${MACOS_OUTPUT_DIR}/macos-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error staging macOS. Check log."; exit 1; fi

    ./b2 "$THREADS" \
        --build-dir=macos-build \
        --stagedir=macos-build/stage \
        --prefix="$MACOS_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~macos" \
        link=static \
        variant=${BUILD_VARIANT} \
        install >> "${MACOS_OUTPUT_DIR}/macos-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error installing macOS. Check log."; exit 1; fi

    doneSection
}

buildBoost_macOS_silicon()
{
    cd_or_abort "$BOOST_SRC"
    mkdir -p "$MACOS_SILICON_OUTPUT_DIR"

    echo building Boost for macOS Silicon
    ./b2 "$THREADS" \
        --build-dir=macos-silicon-build \
        --stagedir=macos-silicon-build/stage \
        --prefix="$MACOS_SILICON_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~macossilicon" \
        link=static \
        variant=${BUILD_VARIANT} \
        stage >> "${MACOS_SILICON_OUTPUT_DIR}/macos-silicon-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error staging macOS silicon. Check log."; exit 1; fi

    ./b2 "$THREADS" \
        --build-dir=macos-silicon-build \
        --stagedir=macos-silicon-build/stage \
        --prefix="$MACOS_SILICON_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~macossilicon" \
        link=static \
        variant=${BUILD_VARIANT} \
        install >> "${MACOS_SILICON_OUTPUT_DIR}/macos-silicon-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error installing macOS silicon. Check log."; exit 1; fi
}

buildBoost_mac_catalyst()
{
    cd_or_abort "$BOOST_SRC"
    mkdir -p "$MAC_CATALYST_OUTPUT_DIR"

    echo Building Boost for Mac Catalyst
    # Install this one so we can copy the headers for the frameworks...
    ./b2 "$THREADS" \
        --build-dir=mac-catalyst-build \
        --stagedir=mac-catalyst-build/stage \
        --prefix="$MAC_CATALYST_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~maccatalyst" \
        link=static \
        variant=${BUILD_VARIANT} \
        stage >> "${MAC_CATALYST_OUTPUT_DIR}/mac-catalyst-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error staging Mac Catalyst. Check log."; exit 1; fi

    ./b2 "$THREADS" \
        --build-dir=mac-catalyst-build \
        --stagedir=mac-catalyst-build/stage \
        --prefix="$MAC_CATALYST_OUTPUT_DIR/prefix" \
        toolset="darwin-$COMPILER_VERSION~maccatalyst" \
        link=static \
        variant=${BUILD_VARIANT} \
        install >> "${MAC_CATALYST_OUTPUT_DIR}/mac-catalyst-build.log" 2>&1
    # shellcheck disable=SC2181
    if [ $? != 0 ]; then echo "Error installing Mac Catalyst. Check log."; exit 1; fi
    doneSection
}

#===============================================================================

unpackArchive()
{
    BUILDDIR="$1"
    LIBNAME="$2"

    echo "Unpacking $BUILDDIR/$LIBNAME"

    if [[ -d "$BUILDDIR/$LIBNAME" ]]; then
        cd_or_abort "$BUILDDIR/$LIBNAME"
        rm ./*.o
        rm ./*.SYMDEF*
    else
        mkdir -p "$BUILDDIR/$LIBNAME"
    fi

    (
        cd_or_abort "$BUILDDIR/$NAME"; ar -x "../../libboost_$NAME.a";
        for FILE in *.o; do
            NEW_FILE="${NAME}_${FILE}"
            mv "$FILE" "$NEW_FILE"
        done
    )
}

scrunchAllLibsTogetherInOneLibPerPlatform()
{
    cd_or_abort "$BOOST_SRC"

    if [[ -n $BUILD_IOS ]]; then
        # iOS Device
        for ARCH in "${IOS_ARCHS[@]}"; do
            mkdir -p "$IOS_BUILD_DIR/$ARCH/obj"
        done

        # iOS Simulator
        for ARCH in "${IOS_SIM_ARCHS[@]}"; do
            mkdir -p "$IOS_BUILD_DIR/$ARCH/obj"
        done
    fi

    if [[ -n $BUILD_TVOS ]]; then
        # tvOS Device
        mkdir -p "$TVOS_BUILD_DIR/arm64/obj"

        # tvOS Simulator
        mkdir -p "$TVOS_BUILD_DIR/x86_64/obj"
    fi

    if [[ -n $BUILD_MACOS ]]; then
        # macOS
        for ARCH in "${MACOS_ARCHS[@]}"; do
            mkdir -p "$MACOS_BUILD_DIR/$ARCH/obj"
        done
    fi

    if [[ -n $BUILD_MACOS_SILICON ]]; then
        # macOS Silicon
        for ARCH in "${MACOS_SILICON_ARCHS[@]}"; do
            mkdir -p "$MACOS_SILICON_BUILD_DIR/$ARCH/obj"
        done
    fi
    if [[ -n $BUILD_MAC_CATALYST ]]; then
        # Mac Catalyst
        for ARCH in "${MAC_CATALYST_ARCHS[@]}"; do
            mkdir -p "$MAC_CATALYST_BUILD_DIR/$ARCH/obj"
        done
    fi

    ALL_LIBS=""

    echo Splitting all existing fat binaries...

    for NAME in $BOOTSTRAP_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        ALL_LIBS="$ALL_LIBS libboost_$NAME.a"

        if [[ -n $BUILD_IOS ]]; then
            if [[ "${#IOS_ARCHS[@]}" -gt 1 ]]; then
                for ARCH in "${IOS_ARCHS[@]}"; do
                    $IOS_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" \
                        -thin "$ARCH" -o "$IOS_BUILD_DIR/$ARCH/libboost_$NAME.a"
                done
            else
                cp "iphone-build/stage/lib/libboost_$NAME.a" \
                    "$IOS_BUILD_DIR/${IOS_ARCHS[0]}/libboost_$NAME.a"
            fi

            if [[ "${#IOS_SIM_ARCHS[@]}" -gt 1 ]]; then
                for ARCH in "${IOS_SIM_ARCHS[@]}"; do
                    $IOS_SIM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" \
                        -thin "$ARCH" -o "$IOS_BUILD_DIR/$ARCH/libboost_$NAME.a"
                done
            else
                cp "iphonesim-build/stage/lib/libboost_$NAME.a" \
                    "$IOS_BUILD_DIR/${IOS_SIM_ARCHS[0]}/libboost_$NAME.a"
            fi
        fi

        if [[ -n $BUILD_TVOS ]]; then
            cp "appletv-build/stage/lib/libboost_$NAME.a" \
                "$TVOS_BUILD_DIR/arm64/libboost_$NAME.a"

            cp "appletvsim-build/stage/lib/libboost_$NAME.a" \
                "$TVOS_BUILD_DIR/x86_64/libboost_$NAME.a"
        fi

        if [[ -n $BUILD_MACOS ]]; then
            if [[ "${#MACOS_ARCHS[@]}" -gt 1 ]]; then
                for ARCH in "${MACOS_ARCHS[@]}"; do
                    $MACOS_DEV_CMD lipo "macos-build/stage/lib/libboost_$NAME.a" \
                        -thin "$ARCH" -o "$MACOS_BUILD_DIR/$ARCH/libboost_$NAME.a"
                done
            else
                cp "macos-build/stage/lib/libboost_$NAME.a" \
                    "$MACOS_BUILD_DIR/${MACOS_ARCHS[0]}/libboost_$NAME.a"
            fi
        fi

        if [[ -n $BUILD_MACOS_SILICON ]]; then
            if [[ "${#MACOS_SILICON_ARCHS[@]}" -gt 1 ]]; then
                for ARCH in "${MACOS_SILICON_ARCHS[@]}"; do
                    $MACOS_SILICON_DEV_CMD lipo "macos-silicon-build/stage/lib/libboost_$NAME.a" \
                        -thin "$ARCH" -o "$MACOS_SILICON_BUILD_DIR/$ARCH/libboost_$NAME.a"
                done
            else
                cp "macos-silicon-build/stage/lib/libboost_$NAME.a" \
                    "$MACOS_SILICON_BUILD_DIR/${MACOS_SILICON_ARCHS[0]}/libboost_$NAME.a"
            fi
        fi
        
        if [[ -n $BUILD_MAC_CATALYST ]]; then
            if [[ "${#MAC_CATALYST_ARCHS[@]}" -gt 1 ]]; then
                for ARCH in "${MAC_CATALYST_ARCHS[@]}"; do
                    $MAC_CATALYST_DEV_CMD lipo "mac-catalyst-build/stage/lib/libboost_$NAME.a" \
                        -thin "$ARCH" -o "$MAC_CATALYST_BUILD_DIR/$ARCH/libboost_$NAME.a"
                done
            else
                cp "mac-catalyst-build/stage/lib/libboost_$NAME.a" \
                    "$MAC_CATALYST_BUILD_DIR/${MAC_CATALYST_ARCHS[0]}/libboost_$NAME.a"
            fi
        fi
    done

    echo "Decomposing each architecture's .a files"

    for NAME in $BOOTSTRAP_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        echo "Decomposing libboost_${NAME}.a"
        if [[ -n $BUILD_IOS ]]; then
            for ARCH in "${IOS_ARCHS[@]}"; do
                unpackArchive "$IOS_BUILD_DIR/$ARCH/obj" $NAME
            done
            for ARCH in "${IOS_SIM_ARCHS[@]}"; do
                unpackArchive "$IOS_BUILD_DIR/$ARCH/obj" $NAME
            done
        fi

        if [[ -n $BUILD_TVOS ]]; then
            unpackArchive "$TVOS_BUILD_DIR/arm64/obj" $NAME
            unpackArchive "$TVOS_BUILD_DIR/x86_64/obj" $NAME
        fi

        if [[ -n $BUILD_MACOS ]]; then
            for ARCH in "${MACOS_ARCHS[@]}"; do
                unpackArchive "$MACOS_BUILD_DIR/$ARCH/obj" $NAME
            done
        fi

        if [[ -n $BUILD_MACOS_SILICON ]]; then
            for ARCH in "${MACOS_SILICON_ARCHS[@]}"; do
                unpackArchive "$MACOS_SILICON_BUILD_DIR/$ARCH/obj" $NAME
            done
        fi

        if [[ -n $BUILD_MAC_CATALYST ]]; then
            for ARCH in "${MAC_CATALYST_ARCHS[@]}"; do
                unpackArchive "$MAC_CATALYST_BUILD_DIR/$ARCH/obj" $NAME
            done
        fi
    done

    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
    if [[ -n $BUILD_IOS ]]; then
        for ARCH in "${IOS_ARCHS[@]}"; do
            rm "$IOS_BUILD_DIR/$ARCH/libboost.a"
        done
    fi
    if [[ -n $BUILD_TVOS ]]; then
        rm "$TVOS_BUILD_DIR"/*/libboost.a
    fi
    if [[ -n $BUILD_MACOS ]]; then
        for ARCH in "${MACOS_ARCHS[@]}"; do
            rm "$MACOS_BUILD_DIR/$ARCH/libboost.a"
        done
    fi
    if [[ -n $BUILD_MACOS_SILICON ]]; then
        for ARCH in "${MACOS_SILICON_ARCHS[@]}"; do
            rm "$MACOS_SILICON_BUILD_DIR/$ARCH/libboost.a"
        done
    fi
    if [[ -n $BUILD_MAC_CATALYST ]]; then
        for ARCH in "${MAC_CATALYST_ARCHS[@]}"; do
            rm "$MAC_CATALYST_BUILD_DIR/$ARCH/libboost.a"
        done
    fi

    for NAME in $BOOTSTRAP_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        echo "Archiving $NAME"

        if [[ -n $BUILD_IOS ]]; then
            for ARCH in "${IOS_ARCHS[@]}"; do
                echo "...ios-$ARCH"
                (cd_or_abort "$IOS_BUILD_DIR/$ARCH"; $IOS_DEV_CMD ar crus libboost.a "obj/$NAME/"*.o; )
            done

            for ARCH in "${IOS_SIM_ARCHS[@]}"; do
                echo "...ios-sim-$ARCH"
                (cd_or_abort "$IOS_BUILD_DIR/$ARCH"; $IOS_SIM_ARM_DEV_CMD ar crus libboost.a "obj/$NAME/"*.o; )
            done
        fi

        if [[ -n $BUILD_TVOS ]]; then
            echo "...tvOS-arm64"
            (cd_or_abort "$TVOS_BUILD_DIR/arm64"; $TVOS_DEV_CMD ar crus libboost.a "obj/$NAME/"*.o; )
            echo "...tvOS-x86_64"
            (cd_or_abort "$TVOS_BUILD_DIR/x86_64";  $TVOS_SIM_DEV_CMD ar crus libboost.a "obj/$NAME/"*.o; )
        fi

        if [[ -n $BUILD_MACOS ]]; then
            for ARCH in "${MACOS_ARCHS[@]}"; do
                echo "...macos-$ARCH"
                (cd_or_abort "$MACOS_BUILD_DIR/$ARCH";  $MACOS_DEV_CMD ar crus libboost.a "obj/$NAME/"*.o; )
            done
        fi

        if [[ -n $BUILD_MACOS_SILICON ]]; then
            for ARCH in "${MACOS_SILICON_ARCHS[@]}"; do
                echo "...macos-silicon-$ARCH"
                (cd_or_abort "$MACOS_SILICON_BUILD_DIR/$ARCH";  $MACOS_SILICON_DEV_CMD ar crus libboost.a "obj/$NAME/"*.o; )
            done
        fi
        if [[ -n $BUILD_MAC_CATALYST ]]; then
            for ARCH in "${MAC_CATALYST_ARCHS[@]}"; do
                echo "...mac-catalyst-$ARCH"
                (cd_or_abort "$MAC_CATALYST_BUILD_DIR/$ARCH";  $MAC_CATALYST_DEV_CMD ar crus libboost.a "obj/$NAME/"*.o; )
            done
        fi
    done
}

buildUniversal()
{
    echo "Creating universal library..."
    if [[ -n $BUILD_IOS ]]; then
        mkdir -p "$IOS_BUILD_DIR/universal"

        cd_or_abort "$IOS_BUILD_DIR"
        for NAME in $BOOTSTRAP_LIBS; do
            if [ "$NAME" == "test" ]; then
                NAME="unit_test_framework"
            fi

            ARCH_FILES=()
            for ARCH in "${IOS_ARCHS[@]}"; do
                ARCH_FILES+=("$ARCH/libboost_$NAME.a")
            done
            for ARCH in "${IOS_SIM_ARCHS[@]}"; do
                ARCH_FILES+=("$ARCH/libboost_$NAME.a")
            done
            if [[ "${#ARCH_FILES[@]}" -gt 0 ]]; then
                echo "... $NAME"
                $IOS_DEV_CMD lipo -create "${ARCH_FILES[@]}" -o "universal/libboost_$NAME.a" || abort "Lipo $NAME failed"
            fi
        done
    fi
    if [[ -n $BUILD_TVOS ]]; then
        mkdir -p "$TVOS_BUILD_DIR/universal"

        cd_or_abort "$TVOS_BUILD_DIR"
        for NAME in $BOOTSTRAP_LIBS; do
            if [ "$NAME" == "test" ]; then
                NAME="unit_test_framework"
            fi

            ARCH_FILES=()
            if [ -f "arm64/libboost_$NAME.a" ]; then
                ARCH_FILES+=("arm64/libboost_$NAME.a")
            fi
            if [ -f "x86_64/libboost_$NAME.a" ]; then
                ARCH_FILES+=("x86_64/libboost_$NAME.a")
            fi
            if [[ "${#ARCH_FILES[@]}" -gt 0 ]]; then
                echo "... $NAME"
                $TVOS_DEV_CMD lipo -create "${ARCH_FILES[@]}" -o "universal/libboost_$NAME.a" || abort "Lipo $NAME failed"
            fi
        done
    fi
    if [[ -n $BUILD_MACOS ]]; then
        mkdir -p "$MACOS_BUILD_DIR/universal"

        cd_or_abort "$MACOS_BUILD_DIR"
        for NAME in $BOOTSTRAP_LIBS; do
            if [ "$NAME" == "test" ]; then
                NAME="unit_test_framework"
            fi

            ARCH_FILES=()
            for ARCH in "${MACOS_ARCHS[@]}"; do
                ARCH_FILES+=("$ARCH/libboost_$NAME.a")
            done
            if [[ "${#ARCH_FILES[@]}" -gt 0 ]]; then
                echo "... $NAME"
                $MACOS_DEV_CMD lipo -create "${ARCH_FILES[@]}" -o "universal/libboost_$NAME.a" || abort "Lipo $NAME failed"
            fi
        done
    fi

    if [[ -n $BUILD_MACOS_SILICON ]]; then
        mkdir -p "$MACOS_SILICON_BUILD_DIR/universal"

        cd_or_abort "$MACOS_SILICON_BUILD_DIR"
        for NAME in $BOOTSTRAP_LIBS; do
            if [ "$NAME" == "test" ]; then
                NAME="unit_test_framework"
            fi

            ARCH_FILES=()
            for ARCH in "${MACOS_SILICON_ARCHS[@]}"; do
                ARCH_FILES+=("$ARCH/libboost_$NAME.a")
            done
            if [[ "${#ARCH_FILES[@]}" -gt 0 ]]; then
                echo "... $NAME"
                $MACOS_SILICON_DEV_CMD lipo -create "${ARCH_FILES[@]}" -o "universal/libboost_$NAME.a" || abort "Lipo $NAME failed"
            fi
        done
    fi

    if [[ -n $BUILD_MAC_CATALYST ]]; then
        mkdir -p "$MAC_CATALYST_BUILD_DIR/universal"

        cd_or_abort "$MAC_CATALYST_BUILD_DIR"
        for NAME in $BOOTSTRAP_LIBS; do
            if [ "$NAME" == "test" ]; then
                NAME="unit_test_framework"
            fi

            ARCH_FILES=()
            for ARCH in "${MAC_CATALYST_ARCHS[@]}"; do
                ARCH_FILES+=("$ARCH/libboost_$NAME.a")
            done
            if [[ "${#ARCH_FILES[@]}" -gt 0 ]]; then
                echo "... $NAME"
                $MAC_CATALYST_DEV_CMD lipo -create "${ARCH_FILES[@]}" -o "universal/libboost_$NAME.a" || abort "Lipo $NAME failed"
            fi
        done
    fi
}

#===============================================================================

buildXCFramework()
{
    : "${1:?}"
    DISTDIR="$1"

    FRAMEWORK_NAME=boost

    FRAMEWORK_CURRENT_VERSION="$BOOST_VERSION"

    FRAMEWORK_BUNDLE="$DISTDIR/$FRAMEWORK_NAME.xcframework"
    echo "Framework: Building $FRAMEWORK_BUNDLE..."

    rm -rf "$FRAMEWORK_BUNDLE"

    SLICES_COUNT=0
    LIB_ARGS=()
    # We'll take any of the paths we find, headers should be the same for all
    # archs / plaforms.
    HEADERS_PATH=""
    if [[ -n $BUILD_IOS ]]; then
        for LIBPATH in "$IOS_OUTPUT_DIR"/build/*/libboost.a; do
            LIB_ARGS+=('-library' "$LIBPATH")
            SLICES_COUNT=$((SLICES_COUNT + 1))
        done

        INCLUDE_DIR="$IOS_OUTPUT_DIR/prefix/include"
        if [ -d "$INCLUDE_DIR" ]; then
            HEADERS_PATH="$INCLUDE_DIR"
        fi
    fi
    if [[ -n $BUILD_TVOS ]]; then
        for LIBPATH in "$TVOS_OUTPUT_DIR"/build/*/libboost.a; do
            LIB_ARGS+=('-library' "$LIBPATH")
            SLICES_COUNT=$((SLICES_COUNT + 1))
        done

        INCLUDE_DIR="$TVOS_OUTPUT_DIR/prefix/include"
        if [ -d "$INCLUDE_DIR" ]; then
            HEADERS_PATH="$INCLUDE_DIR"
        fi
    fi
    if [[ -n $BUILD_MACOS ]] || [[ -n $BUILD_MACOS_SILICON ]]; then
        # all macOS binaries need to be lipo'd together before putting them in the xcframework.
        # grab all the boost build files for macOS (e.g. i386, x86_64, arm64):
        MACOS_BOOST_FILES=()
        if [[ -n $BUILD_MACOS ]]; then
            for LIBPATH in "$MACOS_OUTPUT_DIR"/build/*/libboost.a; do
                MACOS_BOOST_FILES+=("$LIBPATH")
            done
        fi
        if [[ -n $BUILD_MACOS_SILICON ]]; then
            for LIBPATH in "$MACOS_SILICON_OUTPUT_DIR"/build/*/libboost.a; do
                MACOS_BOOST_FILES+=("$LIBPATH")
            done
        fi
        # if we have any mac files to add together...
        if [ ${#MACOS_BOOST_FILES[@]} -gt 0 ]; then
            # lipo the files together
            mkdir -p "$MACOS_COMBINED_OUTPUT_DIR/build"
            COMBINED_MACOS_BUILD="$MACOS_COMBINED_OUTPUT_DIR/build/libboost.a"
            lipo -create -output "$MACOS_COMBINED_OUTPUT_DIR/build/libboost.a" "${MACOS_BOOST_FILES[@]}"
            LIB_ARGS+=('-library' "$COMBINED_MACOS_BUILD")
            SLICES_COUNT=$((SLICES_COUNT + 1))
            # make sure headers are set up properly!
            if [[ -n $BUILD_MACOS ]]; then
                INCLUDE_DIR="$MACOS_OUTPUT_DIR/prefix/include"
                if [ -d "$INCLUDE_DIR" ]; then
                    HEADERS_PATH="$INCLUDE_DIR"
                fi
            fi
            if [[ -n $BUILD_MACOS_SILICON ]]; then
                INCLUDE_DIR="$MACOS_SILICON_OUTPUT_DIR/prefix/include"
                if [ -d "$INCLUDE_DIR" ]; then
                    HEADERS_PATH="$INCLUDE_DIR"
                fi
            fi
        fi
    fi
    if [[ -n $BUILD_MAC_CATALYST ]]; then
        for LIBPATH in "$MAC_CATALYST_OUTPUT_DIR"/build/*/libboost.a; do
            LIB_ARGS+=('-library' "$LIBPATH")
            SLICES_COUNT=$((SLICES_COUNT + 1))
        done

        INCLUDE_DIR="$MAC_CATALYST_OUTPUT_DIR/prefix/include"
        if [ -d "$INCLUDE_DIR" ]; then
            HEADERS_PATH="$INCLUDE_DIR"
        fi
    fi

    # create the xcframework file
    xcrun xcodebuild -create-xcframework \
        "${LIB_ARGS[@]}" \
        -headers "$HEADERS_PATH" \
        -output "$FRAMEWORK_BUNDLE"

    # Fix the 'Headers' directory location in the xcframework, and update the
    # Info.plist accordingly for all slices.
    FRAMEWORK_HEADERS_PATH=$(find "${FRAMEWORK_BUNDLE}" -name 'Headers')
    mv "$FRAMEWORK_HEADERS_PATH" "$FRAMEWORK_BUNDLE"

    for I in $(seq 0 $((SLICES_COUNT - 1))); do
      plutil -replace "AvailableLibraries.$I.HeadersPath" -string '../Headers' "$FRAMEWORK_BUNDLE/Info.plist"
    done

    echo "$FRAMEWORK_CURRENT_VERSION" > "$FRAMEWORK_BUNDLE/VERSION"

    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

parseArgs "$@"

if [[ -z $BUILD_IOS && -z $BUILD_TVOS && -z $BUILD_MACOS && -z $BUILD_MAC_CATALYST && -z $BUILD_MACOS_SILICON ]]; then
    BUILD_IOS=1
    BUILD_TVOS=1
    BUILD_MACOS=1
    BUILD_MACOS_SILICON=1
    BUILD_MAC_CATALYST=1
fi

# Must set these after parseArgs to fill in overriden values
EXTRA_FLAGS="-fembed-bitcode -Wno-unused-local-typedef -Wno-nullability-completeness"

# The EXTRA_ARM_FLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Note these flags (BOOST_AC_USE_PTHREADS and BOOST_SP_USE_PTHREADS) should
# only be defined for arm targets. They will cause random (but repeatable)
# shared_ptr crashes on macOS in boost thread destructors.
EXTRA_ARM_FLAGS="-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS -g -DNDEBUG"

EXTRA_IOS_FLAGS="$EXTRA_FLAGS $EXTRA_ARM_FLAGS -mios-version-min=$MIN_IOS_VERSION"
EXTRA_IOS_SIM_FLAGS="$EXTRA_FLAGS $EXTRA_ARM_FLAGS -mios-simulator-version-min=$MIN_IOS_VERSION"
EXTRA_TVOS_FLAGS="$EXTRA_FLAGS $EXTRA_ARM_FLAGS -mtvos-version-min=$MIN_TVOS_VERSION"
EXTRA_TVOS_SIM_FLAGS="$EXTRA_FLAGS $EXTRA_ARM_FLAGS -mtvos-simulator-version-min=$MIN_TVOS_VERSION"
EXTRA_MACOS_FLAGS="$EXTRA_FLAGS -mmacosx-version-min=$MIN_MACOS_VERSION"
EXTRA_MACOS_SILICON_FLAGS="$EXTRA_FLAGS $EXTRA_ARM_FLAGS -mmacosx-version-min=$MIN_MACOS_SILICON_VERSION"

BOOST_VERSION2="${BOOST_VERSION//./_}"
BOOST_TARBALL="$CURRENT_DIR/boost_$BOOST_VERSION2.tar.bz2"
BOOST_SRC="$SRCDIR/boost_${BOOST_VERSION2}"
OUTPUT_DIR="$CURRENT_DIR/build/boost/$BOOST_VERSION"
IOS_OUTPUT_DIR="$OUTPUT_DIR/ios/$BUILD_VARIANT"
TVOS_OUTPUT_DIR="$OUTPUT_DIR/tvos/$BUILD_VARIANT"
MACOS_OUTPUT_DIR="$OUTPUT_DIR/macos/$BUILD_VARIANT"
MACOS_SILICON_OUTPUT_DIR="$OUTPUT_DIR/macos-silicon/$BUILD_VARIANT"
MACOS_COMBINED_OUTPUT_DIR="$OUTPUT_DIR/macos-combined/$BUILD_VARIANT"
IOS_BUILD_DIR="$IOS_OUTPUT_DIR/build"
TVOS_BUILD_DIR="$TVOS_OUTPUT_DIR/build"
MACOS_BUILD_DIR="$MACOS_OUTPUT_DIR/build"
MACOS_SILICON_BUILD_DIR="$MACOS_SILICON_OUTPUT_DIR/build"
MAC_CATALYST_OUTPUT_DIR="$OUTPUT_DIR/mac-catalyst/$BUILD_VARIANT"
MAC_CATALYST_BUILD_DIR="$MAC_CATALYST_OUTPUT_DIR/build"

MACOS_ARCH_FLAGS=()
for ARCH in "${MACOS_ARCHS[@]}"; do
    MACOS_ARCH_FLAGS+=("-arch $ARCH")
done

MACOS_SILICON_ARCH_FLAGS=()
for ARCH in "${MACOS_SILICON_ARCHS[@]}"; do
    MACOS_SILICON_ARCH_FLAGS+=("-arch $ARCH")
done
MAC_CATALYST_ARCH_FLAGS=()
for ARCH in "${MAC_CATALYST_ARCHS[@]}"; do
    MAC_CATALYST_ARCH_FLAGS+=("-arch $ARCH")
done

IOS_ARCH_FLAGS=()
for ARCH in "${IOS_ARCHS[@]}"; do
    IOS_ARCH_FLAGS+=("-arch $ARCH")
done

IOS_SIM_ARCH_FLAGS=()
for ARCH in "${IOS_SIM_ARCHS[@]}"; do
    IOS_SIM_ARCH_FLAGS+=("-arch $ARCH")
done

printVar()
{
    VAR_NAME="$1"
    VALUE="${2:-${!1}}"
    printf "%-20s: %s\n" "$VAR_NAME" "$VALUE"
}
asBool() { test -n "$1" && echo "YES" || echo "NO"; }

printVar "BOOST_VERSION"
echo
printVar "BUILD_IOS" "$(asBool "$BUILD_IOS")"
printVar "IOS_ARCHS"
printVar "IOS_SDK_VERSION"
printVar "IOS_SDK_PATH"
printVar "IOSSIM_SDK_PATH"
printVar "MIN_IOS_VERSION"
echo
printVar "BUILD_TVOS" "$(asBool "$BUILD_TVOS")"
printVar "TVOS_SDK_VERSION"
printVar "TVOS_SDK_PATH"
printVar "TVOSSIM_SDK_PATH"
printVar "MIN_TVOS_VERSION"
echo
printVar "BUILD_MACOS" "$(asBool "$BUILD_MACOS")"
printVar "MACOS_ARCHS"
printVar "MACOS_SDK_VERSION"
printVar "MACOS_SDK_PATH"
printVar "MIN_MACOS_VERSION"
echo
printVar "BUILD_MACOS_SILICON" "$(asBool "$BUILD_MACOS_SILICON")"
printVar "MACOS_SILICON_ARCHS"
printVar "MACOS_SILICON_SDK_VERSION"
printVar "MACOS_SILICON_SDK_PATH"
printVar "MIN_MACOS_SILICON_VERSION"
printVar "BUILD_MAC_CATALYST" "$(asBool "$BUILD_MAC_CATALYST")"
printVar "MAC_CATALYST_ARCHS"
printVar "MAC_CATALYST_SDK_VERSION"
printVar "MAC_CATALYST_SDK_PATH"
printVar "MIN_MAC_CATALYST_VERSION"
echo
printVar "BOOST_LIBS"
printVar "BOOST_SRC"
printVar "XCODE_ROOT"
printVar "IOS_BUILD_DIR"
printVar "TVOS_BUILD_DIR"
printVar "MACOS_BUILD_DIR"
printVar "MACOS_SILICON_BUILD_DIR"
printVar "MAC_CATALYST_BUILD_DIR"
printVar "THREADS"
printVar "BUILD_VARIANT"
echo

if [[ -n "$PURGE" ]]; then
    echo "Purging everything..."
    rm -r boost_*.tar.bz2
    rm -r build
    rm -r src
    echo "Done"
    exit 0
fi

if [[ -n $CLEAN ]]; then
    cleanup
    exit
fi

if [[ -z $NO_CLEAN ]]; then
    cleanup
fi

downloadBoost
unpackBoost
inventMissingHeaders
patchBoost
updateBoost

if [[ -n $BUILD_IOS ]]; then
    bootstrapBoost "iOS"
    buildBoost_iOS
fi
if [[ -n $BUILD_TVOS ]]; then
    bootstrapBoost "tvOS"
    buildBoost_tvOS
fi
if [[ -n $BUILD_MACOS ]]; then
    bootstrapBoost "macOS"
    buildBoost_macOS
fi
if [[ -n $BUILD_MACOS_SILICON ]]; then
    updateBoost "macOSSilicon"
    bootstrapBoost "macOSSilicon"
    buildBoost_macOS_silicon
fi
if [[ -n $BUILD_MAC_CATALYST ]]; then
    bootstrapBoost "iOS"
    buildBoost_mac_catalyst
fi

scrunchAllLibsTogetherInOneLibPerPlatform
if [[ -n $UNIVERSAL ]]; then
    buildUniversal
fi

if [[ -z $NO_FRAMEWORK ]]; then
    DIST_DIR="$CURRENT_DIR/dist"
    mkdir -p "$DIST_DIR"
    buildXCFramework "$DIST_DIR"
fi

echo "Completed successfully"
