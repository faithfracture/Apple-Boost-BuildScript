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
#    BOOST_VERSION:   Which version of Boost to build (e.g. 1.61.0)
#    BOOST_LIBS:      Which Boost libraries to build
#    IOS_SDK_VERSION: iOS SDK version (e.g. 10.0)
#    MIN_IOS_VERSION: Minimum iOS Target Version (e.g. 10.0)
#    TVOS_SDK_VERSION: iOS SDK version (e.g. 10.0)
#    MIN_TVOS_VERSION: Minimum iOS Target Version (e.g. 10.0)
#    MACOS_SDK_VERSION: macOS SDK version (e.g. 10.11)
#    MIN_MACOS_VERSION: Minimum macOS Target Version (e.g. 10.10)
#
# If a boost tarball (a file named “boost_$BOOST_VERSION2.tar.bz2”) does not
# exist in the current directory, this script will attempt to download the
# version specified by BOOST_VERSION2. You may also manually place a matching 
# tarball in the current directory and the script will use that.
#
#===============================================================================

BOOST_VERSION=1.67.0

BOOST_LIBS="atomic chrono date_time exception filesystem program_options random signals system thread test"
ALL_BOOST_LIBS=\
"atomic chrono container context coroutine coroutine2 date_time exception fiber filesystem graph"\
" graph_parallel iostreams locale log math metaparse mpi program_options python random regex"\
" serialization signals system test thread timer type_erasure wave"
BOOTSTRAP_LIBS=""

MIN_IOS_VERSION=10.0
IOS_SDK_VERSION=`xcrun --sdk iphoneos --show-sdk-version`

MIN_TVOS_VERSION=10.0
TVOS_SDK_VERSION=`xcrun --sdk appletvos --show-sdk-version`
TVOS_SDK_PATH=`xcrun --sdk appletvos --show-sdk-path`
TVOSSIM_SDK_PATH=`xcrun --sdk appletvsimulator --show-sdk-path`

MIN_MACOS_VERSION=10.10
MACOS_SDK_VERSION=`xcrun --sdk macosx --show-sdk-version`
MACOS_SDK_PATH=`xcrun --sdk macosx --show-sdk-path`

MACOS_ARCHS=("x86_64")
IOS_ARCHS=("armv7 arm64")

# Applied to all platforms
CXX_FLAGS="-std=c++14 -stdlib=libc++"

XCODE_ROOT=`xcode-select -print-path`
COMPILER="$XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++" 

THREADS="-j$(sysctl -n hw.ncpu)"

CURRENT_DIR=`pwd`
SRCDIR="$CURRENT_DIR/src"

IOS_ARM_DEV_CMD="xcrun --sdk iphoneos"
IOS_SIM_DEV_CMD="xcrun --sdk iphonesimulator"
TVOS_ARM_DEV_CMD="xcrun --sdk appletvos"
TVOS_SIM_DEV_CMD="xcrun --sdk appletvsimulator"
MACOS_DEV_CMD="xcrun --sdk macosx"

#===============================================================================
# Functions
#===============================================================================

usage()
{
cat << EOF
usage: $0 [{-ios,-tvos,-macos} ...] options
Build Boost for iOS, iOS Simulator, tvOS, tvOS Simulator, and macOS 
The -ios, -tvos, and -macOS options may be specified together. Default
is to build all of them.

Examples:
    ./boost.sh -ios -tvos --boost-version 1.63.0
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
        Specify the minimum iOS version to target. Since iOS 11 is 64-bit only,
        if the minimum iOS version is set to iOS 11.0 or later, iOS archs is
        automatically set to 'arm64', unless '--ios-archs' is also specified.
        Defaults to $MIN_IOS_VERSION

    --ios-archs "(archs, ...)"
        Specify the iOS architectures to build for. Space-separate list.
        Defaults to ${IOS_ARCHS[*]}

    --tvos-sdk [num]
        Specify the tvOS SDK version to build with.
        Defaults to $TVOS_SDK_VERSION

    --min-tvos_version [num]
        Specify the minimum tvOS version to target.
        Defaults to $MIN_TVOS_VERSION

    --macos-sdk [num]
        Specify the macOS SDK version to build with.
        Defaults to $MACOS_SDK_VERSION

    --min-macos-version [num]
        Specify the minimum macOS version to target.
        Defaults to $MIN_MACOS_VERSION

    --macos-archs "(archs, ...)"
        Specify the macOS architectures to build for. Space-separate list.
        Defaults to ${MACOS_ARCHS[*]}

    --no-framework
        Do not create the framework.

    --universal
        Create universal FAT binary.

    --framework-header-root
        Place headers in a 'boost' root directory in the framework rather than
        directly in the 'Headers' directory.
        Added for compatibility with projects that expect this structure.

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

            -macos)
                BUILD_MACOS=1
                ;;

            --boost-version)
                if [ -n $2 ]; then
                    BOOST_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --boost-libs)
                if [ -n "$2" ]; then
                    CUSTOM_LIBS=$2
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

            --ios-archs)
                if [ -n "$2" ]; then
                    CUSTOM_IOS_ARCHS=$2
                    shift;
                else
                    missingParameter $1
                fi
                ;;

            --tvos-sdk)
                if [ -n $2 ]; then
                    TVOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-tvos-version)
                if [ -n $2 ]; then
                    MIN_TVOS_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --macos-sdk)
                 if [ -n $2 ]; then
                    MACOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-macos-version)
                if [ -n $2 ]; then
                    MIN_MACOS_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --macos-archs)
                if [ -n "$2" ]; then
                    CUSTOM_MACOS_ARCHS=$2
                    shift;
                else
                    missingParameter $1
                fi
                ;;

            --universal)
                UNIVERSAL=1
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

            --framework-header-root)
                HEADER_ROOT=1
                ;;

            -j | --threads)
                if [ -n $2 ]; then
                    THREADS="-j$2"
                    shift
                else
                    missingParameter $1
                fi
                ;;

            *)
                unknownParameter $1
                ;;
        esac

        shift
    done

    if [[ -n $CUSTOM_LIBS ]]; then
        if [[ "$CUSTOM_LIBS" == "none" ]]; then
            CUSTOM_LIBS=
        elif [[ "$CUSTOM_LIBS" == "all" ]]; then
            CUSTOM_LIBS=$ALL_BOOST_LIBS
        fi
        BOOST_LIBS=$CUSTOM_LIBS
    fi

    if [[ -n $CUSTOM_MACOS_ARCHS ]]; then
        MACOS_ARCHS=($CUSTOM_MACOS_ARCHS)
    fi

    if [[ -n $CUSTOM_IOS_ARCHS ]]; then
        IOS_ARCHS=($CUSTOM_IOS_ARCHS)
    elif (( $(echo "$MIN_IOS_VERSION >= 11.0" | bc -l) )); then
        IOS_ARCHS=("arm64")
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

    doneSection
}

#===============================================================================

downloadBoost()
{
    if [ ! -s "$BOOST_TARBALL" ]; then
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

    [ -d "$SRCDIR" ]    || mkdir -p "$SRCDIR"
    [ -d "$BOOST_SRC" ] || ( cd "$SRCDIR"; tar xfj "$BOOST_TARBALL" )
    [ -d "$BOOST_SRC" ] && echo "    ...unpacked as $BOOST_SRC"

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

    USING_MPI=
    if [[ $BOOST_LIBS == *"mpi"* ]]; then
        USING_MPI="using mpi ;" # trailing space needed
    fi

    if [[ "$1" == "iOS" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${IOS_SDK_VERSION}~iphone
: $COMPILER $IOS_ARCH_FLAGS $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${IOS_SDK_VERSION}~iphonesim
: $COMPILER -arch i386 -arch x86_64 $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
$USING_MPI
EOF
    fi

    if [[ "$1" == "tvOS" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${TVOS_SDK_VERSION}~appletv
: $COMPILER -arch arm64 $EXTRA_TVOS_FLAGS -isysroot $TVOS_SDK_PATH -I $TVOS_SDK_PATH
: <striper> <root>$XCODE_ROOT/Platforms/AppleTVOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${TVOS_SDK_VERSION}~appletvsim
: $COMPILER -arch x86_64 $EXTRA_TVOS_FLAGS -isysroot $TVOSSIM_SDK_PATH -I $TVOSSIM_SDK_PATH
: <striper> <root>$XCODE_ROOT/Platforms/AppleTVSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
$USING_MPI
EOF
    fi

    if [[ "$1" == "macOS" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${MACOS_SDK_VERSION}
: $COMPILER $MACOS_ARCH_FLAGS $EXTRA_MACOS_FLAGS -isysroot $MACOS_SDK_PATH
: <striper> <root>$XCODE_ROOT/Platforms/MacOSX.platform/Developer
: <architecture>x86 <target-os>darwin
;
$USING_MPI
EOF
    fi

    doneSection
}

#===============================================================================

bootstrapBoost()
{
    cd "$BOOST_SRC"
    if [[ -z $BOOST_LIBS ]]; then
        ./bootstrap.sh --without-libraries=${ALL_BOOST_LIBS// /,}
    else
        BOOTSTRAP_LIBS=$BOOST_LIBS
        # Strip out unsupported / unavailable libraries
        if [[ "$1" == "iOS" ]]; then
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/context//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/coroutine//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/coroutine2//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/math//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/mpi//')
        fi

        if [[ "$1" == "tvOS" ]]; then
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/container//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/context//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/coroutine//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/coroutine2//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/math//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/metaparse//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/mpi//')
            BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e 's/test//')
        fi

        echo "Bootstrap libs ${BOOTSTRAP_LIBS}"
        BOOST_LIBS_COMMA=$(echo $BOOTSTRAP_LIBS | sed -e 's/[[:space:]]/,/g')
        echo "Bootstrapping for $1 (with libs $BOOST_LIBS_COMMA)"
        ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA
    fi

    doneSection
}

#===============================================================================

buildBoost_iOS()
{
    cd "$BOOST_SRC"
    mkdir -p "$IOS_OUTPUT_DIR"

    echo Building Boost for iPhone
    # Install this one so we can copy the headers for the frameworks...
    ./b2 $THREADS --build-dir=iphone-build --stagedir=iphone-build/stage \
        --prefix="$IOS_OUTPUT_DIR/prefix" toolset=darwin \
        cxxflags="${CXX_FLAGS} ${IOS_ARCH_FLAGS}" architecture=arm target-os=iphone \
        macosx-version=iphone-${IOS_SDK_VERSION} define=_LITTLE_ENDIAN \
        link=static stage >> "${IOS_OUTPUT_DIR}/ios-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging iPhone. Check log."; exit 1; fi

    ./b2 $THREADS --build-dir=iphone-build --stagedir=iphone-build/stage \
        --prefix="$IOS_OUTPUT_DIR/prefix" toolset=darwin \
        cxxflags="${CXX_FLAGS} ${IOS_ARCH_FLAGS}" architecture=arm \
        target-os=iphone macosx-version=iphone-${IOS_SDK_VERSION} \
        define=_LITTLE_ENDIAN link=static install >> "${IOS_OUTPUT_DIR}/ios-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error installing iPhone. Check log."; exit 1; fi
    doneSection

    echo Building Boost for iPhoneSimulator
    ./b2 $THREADS --build-dir=iphonesim-build --stagedir=iphonesim-build/stage \
        toolset=darwin-${IOS_SDK_VERSION}~iphonesim cxxflags="${CXX_FLAGS}" architecture=x86 \
        target-os=iphone macosx-version=iphonesim-${IOS_SDK_VERSION} \
        link=static stage >> "${IOS_OUTPUT_DIR}/ios-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging iPhoneSimulator. Check log."; exit 1; fi
    doneSection
}

buildBoost_tvOS()
{
    cd "$BOOST_SRC"
    mkdir -p "$TVOS_OUTPUT_DIR"

    echo Building Boost for AppleTV
    ./b2 $THREADS --build-dir=appletv-build --stagedir=appletv-build/stage \
        --prefix="$TVOS_OUTPUT_DIR/prefix" toolset=darwin-${TVOS_SDK_VERSION}~appletv \
        cxxflags="${CXX_FLAGS}" architecture=arm target-os=iphone define=_LITTLE_ENDIAN \
        link=static stage >> "${TVOS_OUTPUT_DIR}/tvos-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging AppleTV. Check log."; exit 1; fi

    ./b2 $THREADS --build-dir=appletv-build --stagedir=appletv-build/stage \
        --prefix="$TVOS_OUTPUT_DIR/prefix" toolset=darwin-${TVOS_SDK_VERSION}~appletv \
        cxxflags="${CXX_FLAGS}" architecture=arm target-os=iphone define=_LITTLE_ENDIAN \
        link=static install >> "${TVOS_OUTPUT_DIR}/tvos-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error installing AppleTV. Check log."; exit 1; fi
    doneSection

    echo Building Boost for AppleTVSimulator
    ./b2 $THREADS --build-dir=appletv-build --stagedir=appletvsim-build/stage \
        toolset=darwin-${TVOS_SDK_VERSION}~appletvsim architecture=x86 \
        cxxflags="${CXX_FLAGS}" target-os=iphone link=static stage >> "${TVOS_OUTPUT_DIR}/tvos-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging AppleTVSimulator. Check log."; exit 1; fi
    doneSection
}

buildBoost_macOS()
{
    cd "$BOOST_SRC"
    mkdir -p "$MACOS_OUTPUT_DIR"

    echo building Boost for macOS
    ./b2 $THREADS --build-dir=macos-build --stagedir=macos-build/stage toolset=clang \
        --prefix="$MACOS_OUTPUT_DIR/prefix" \
        cxxflags="${CXX_FLAGS} ${MACOS_ARCH_FLAGS} ${EXTRA_MACOS_SDK_FLAGS}" \
        linkflags="-stdlib=libc++ ${EXTRA_MACOS_SDK_FLAGS}" link=static threading=multi \
        macosx-version=${MACOS_SDK_VERSION} stage >> "${MACOS_OUTPUT_DIR}/macos-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error staging macOS. Check log."; exit 1; fi

    ./b2 $THREADS --build-dir=macos-build --stagedir=macos-build/stage \
        --prefix="$MACOS_OUTPUT_DIR/prefix" toolset=clang \
        cxxflags="${CXX_FLAGS} ${MACOS_ARCH_FLAGS} ${EXTRA_MACOS_SDK_FLAGS}" \
        linkflags="-stdlib=libc++ ${EXTRA_MACOS_SDK_FLAGS}" link=static threading=multi \
        macosx-version=${MACOS_SDK_VERSION} install >> "${MACOS_OUTPUT_DIR}/macos-build.log" 2>&1
    if [ $? != 0 ]; then echo "Error installing macOS. Check log."; exit 1; fi

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
        for ARCH in ${IOS_ARCHS[@]}; do
            mkdir -p "$IOS_BUILD_DIR/$ARCH/obj"
        done

        # iOS Simulator
        mkdir -p "$IOS_BUILD_DIR/i386/obj"
        mkdir -p "$IOS_BUILD_DIR/x86_64/obj"
    fi

    if [[ -n $BUILD_TVOS ]]; then
        # tvOS Device
        mkdir -p "$TVOS_BUILD_DIR/arm64/obj"

        # tvOS Simulator
        mkdir -p "$TVOS_BUILD_DIR/x86_64/obj"
    fi

    if [[ -n $BUILD_MACOS ]]; then
        # macOS
        for ARCH in ${MACOS_ARCHS[@]}; do
            mkdir -p "$MACOS_BUILD_DIR/$ARCH/obj"
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
            for ARCH in ${IOS_ARCHS[@]}; do
                $IOS_ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" \
                    -thin $ARCH -o "$IOS_BUILD_DIR/$ARCH/libboost_$NAME.a"
            done

            $IOS_SIM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" \
                -thin i386 -o "$IOS_BUILD_DIR/i386/libboost_$NAME.a"
            $IOS_SIM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" \
                -thin x86_64 -o "$IOS_BUILD_DIR/x86_64/libboost_$NAME.a"
        fi

        if [[ -n $BUILD_TVOS ]]; then
            cp "appletv-build/stage/lib/libboost_$NAME.a" \
                "$TVOS_BUILD_DIR/arm64/libboost_$NAME.a"

            cp "appletvsim-build/stage/lib/libboost_$NAME.a" \
                "$TVOS_BUILD_DIR/x86_64/libboost_$NAME.a"
        fi

        if [[ -n $BUILD_MACOS ]]; then
            if (( ${#MACOS_ARCHS[@]} == 1 )); then
                cp "macos-build/stage/lib/libboost_$NAME.a" \
                    "$MACOS_BUILD_DIR/$ARCH/libboost_$NAME.a"
            else
                for ARCH in ${MACOS_ARCHS[@]}; do
                    $MACOS_DEV_CMD lipo "macos-build/stage/lib/libboost_$NAME.a" \
                        -thin $ARCH -o "$MACOS_BUILD_DIR/$ARCH/libboost_$NAME.a"
                done
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
            for ARCH in ${IOS_ARCHS[@]}; do
                unpackArchive "$IOS_BUILD_DIR/$ARCH/obj" $NAME
            done
            unpackArchive "$IOS_BUILD_DIR/i386/obj" $NAME
            unpackArchive "$IOS_BUILD_DIR/x86_64/obj" $NAME
        fi

        if [[ -n $BUILD_TVOS ]]; then
            unpackArchive "$TVOS_BUILD_DIR/arm64/obj" $NAME
            unpackArchive "$TVOS_BUILD_DIR/x86_64/obj" $NAME
        fi

        if [[ -n $BUILD_MACOS ]]; then
            for ARCH in ${MACOS_ARCHS[@]}; do
                unpackArchive "$MACOS_BUILD_DIR/$ARCH/obj" $NAME
            done
        fi
    done

    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
    if [[ -n $BUILD_IOS ]]; then
        for ARCH in ${IOS_ARCHS[@]}; do
            rm "$IOS_BUILD_DIR/$ARCH/libboost.a"
        done
    fi
    if [[ -n $BUILD_TVOS ]]; then
        cd "$TVOS_BUILD_DIR"
        rm */libboost.a
    fi
    if [[ -n $BUILD_MACOS ]]; then
        for ARCH in ${MACOS_ARCHS[@]}; do
            rm "$MACOS_BUILD_DIR/$ARCH/libboost.a"
        done
    fi

    for NAME in $BOOTSTRAP_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        echo "Archiving $NAME"

        # The obj/$NAME/*.o below should all be quoted, but I couldn't figure out how to do that elegantly.
        # Boost lib names probably won't contain non-word characters any time soon, though. ;) - Jan

        if [[ -n $BUILD_IOS ]]; then
            for ARCH in ${IOS_ARCHS[@]}; do
                echo ...ios-$ARCH
                (cd "$IOS_BUILD_DIR/$ARCH"; $IOS_ARM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            done

            echo ...ios-i386
            (cd "$IOS_BUILD_DIR/i386";  $IOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            echo ...ios-x86_64
            (cd "$IOS_BUILD_DIR/x86_64";  $IOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
        fi

        if [[ -n $BUILD_TVOS ]]; then
            echo ...tvOS-arm64
            (cd "$TVOS_BUILD_DIR/arm64"; $TVOS_ARM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            echo ...tvOS-x86_64
            (cd "$TVOS_BUILD_DIR/x86_64";  $TVOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
        fi

        if [[ -n $BUILD_MACOS ]]; then
            for ARCH in ${MACOS_ARCHS[@]}; do
                echo ...macos-$ARCH
                (cd "$MACOS_BUILD_DIR/$ARCH";  $MACOS_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            done
        fi
    done
}

buildUniversal()
{
        echo "Creating universal library..."
    if [[ -n $BUILD_IOS ]]; then
        mkdir -p "$IOS_BUILD_DIR/universal"

        cd "$IOS_BUILD_DIR"
        for NAME in $BOOTSTRAP_LIBS; do
            if [ "$NAME" == "test" ]; then
                NAME="unit_test_framework"
            fi

            ARCH_FILES=""
            for ARCH in ${IOS_ARCHS[@]}; do
                ARCH_FILES+=" $ARCH/libboost_$NAME.a"
            done
            # Ideally IOS_ARCHS contains i386 and x86_64 and simulator build steps are not treated out of band
            if [ -f "i386/libboost_$NAME.a" ]; then
                ARCH_FILES+=" i386/libboost_$NAME.a"
            fi
            if [ -f "x86_64/libboost_$NAME.a" ]; then
                ARCH_FILES+=" x86_64/libboost_$NAME.a"
            fi
            if [[ ${ARCH_FILES[@]} ]]; then
                echo "... $NAME"
                $IOS_ARM_DEV_CMD lipo -create $ARCH_FILES -o "universal/libboost_$NAME.a" || abort "Lipo $1 failed"
            fi
        done
    fi
    if [[ -n $BUILD_TVOS ]]; then
        mkdir -p "$TVOS_BUILD_DIR/universal"

        cd "$TVOS_BUILD_DIR"
        for NAME in $BOOTSTRAP_LIBS; do
            if [ "$NAME" == "test" ]; then
                NAME="unit_test_framework"
            fi

            ARCH_FILES=""
            if [ -f "arm64/libboost_$NAME.a" ]; then
                ARCH_FILES+=" arm64/libboost_$NAME.a"
            fi
            if [ -f "x86_64/libboost_$NAME.a" ]; then
                ARCH_FILES+=" x86_64/libboost_$NAME.a"
            fi
            if [[ ${ARCH_FILES[@]} ]]; then
                echo "... $NAME"
                $TVOS_ARM_DEV_CMD lipo -create $ARCH_FILES -o "universal/libboost_$NAME.a" || abort "Lipo $1 failed"
            fi
        done
    fi
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
    if [[ -n $HEADER_ROOT ]]; then
        FRAMEWORK_HEADERS="/Headers/boost/"
    else
        FRAMEWORK_HEADERS="/Headers/"
    fi

    echo "Framework: Setting up directories..."
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources"
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_HEADERS"
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation"

    echo "Framework: Creating symlinks..."
    ln -s "$FRAMEWORK_VERSION" "$FRAMEWORK_BUNDLE/Versions/Current"
    ln -s "Versions/Current/Headers" "$FRAMEWORK_BUNDLE/Headers"
    ln -s "Versions/Current/Resources" "$FRAMEWORK_BUNDLE/Resources"
    ln -s "Versions/Current/Documentation" "$FRAMEWORK_BUNDLE/Documentation"
    ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_BUNDLE/$FRAMEWORK_NAME"

    FRAMEWORK_INSTALL_NAME="$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME"

    if [[ -n $BOOTSTRAP_LIBS ]]; then
        echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
        cd "$BUILDDIR"
        if [[ -n $BUILD_IOS ]]; then
            $IOS_ARM_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
        fi
        if [[ -n $BUILD_TVOS ]]; then
            $TVOS_ARM_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
        fi
        if [[ -n $BUILD_MACOS ]]; then
            $MACOS_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
        fi
    fi

    echo "Framework: Copying includes..."
    cp -r "$PREFIXDIR/include/boost/"* "$FRAMEWORK_BUNDLE/$FRAMEWORK_HEADERS"

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

if [[ -z $BUILD_IOS && -z $BUILD_TVOS && -z $BUILD_MACOS ]]; then
    BUILD_IOS=1
    BUILD_TVOS=1
    BUILD_MACOS=1
fi

# The EXTRA_FLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

# Must set these after parseArgs to fill in overriden values
EXTRA_FLAGS="-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS -g -DNDEBUG"`
    `" -fvisibility=hidden -fvisibility-inlines-hidden"`
    `" -Wno-unused-local-typedef -fembed-bitcode -Wno-nullability-completeness"
EXTRA_IOS_FLAGS="$EXTRA_FLAGS -mios-version-min=$MIN_IOS_VERSION"
EXTRA_TVOS_FLAGS="$EXTRA_FLAGS -mtvos-version-min=$MIN_TVOS_VERSION"
EXTRA_MACOS_FLAGS="$EXTRA_FLAGS -mmacosx-version-min=$MIN_MACOS_VERSION"
EXTRA_MACOS_SDK_FLAGS="-isysroot ${MACOS_SDK_PATH} -mmacosx-version-min=${MIN_MACOS_VERSION}"

BOOST_VERSION2="${BOOST_VERSION//./_}"
BOOST_TARBALL="$CURRENT_DIR/boost_$BOOST_VERSION2.tar.bz2"
BOOST_SRC="$SRCDIR/boost_${BOOST_VERSION2}"
OUTPUT_DIR="$CURRENT_DIR/build/boost/$BOOST_VERSION"
IOS_OUTPUT_DIR="$OUTPUT_DIR/ios"
TVOS_OUTPUT_DIR="$OUTPUT_DIR/tvos"
MACOS_OUTPUT_DIR="$OUTPUT_DIR/macos"
IOS_BUILD_DIR="$IOS_OUTPUT_DIR/build"
TVOS_BUILD_DIR="$TVOS_OUTPUT_DIR/build"
MACOS_BUILD_DIR="$MACOS_OUTPUT_DIR/build"
IOSLOG="> $IOS_OUTPUT_DIR/iphone.log 2>&1"
IOS_FRAMEWORK_DIR="$IOS_OUTPUT_DIR/framework"
TVOS_FRAMEWORK_DIR="$TVOS_OUTPUT_DIR/framework"
MACOS_FRAMEWORK_DIR="$MACOS_OUTPUT_DIR/framework"

MACOS_ARCH_FLAGS=""
for ARCH in ${MACOS_ARCHS[@]}; do
    MACOS_ARCH_FLAGS="$MACOS_ARCH_FLAGS -arch $ARCH"
done

IOS_ARCH_FLAGS=""
for ARCH in ${IOS_ARCHS[@]}; do
    IOS_ARCH_FLAGS="$IOS_ARCH_FLAGS -arch $ARCH"
done

format="%-20s %s\n"
printf "$format" "BUILD_IOS:" $( [[ -n $BUILD_IOS ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_TVOS:" $( [[ -n $BUILD_TVOS ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_MACOS:" $( [[ -n $BUILD_MACOS ]] && echo "YES" || echo "NO")
printf "$format" "BOOST_VERSION:" "$BOOST_VERSION"
printf "$format" "IOS_SDK_VERSION:" "$IOS_SDK_VERSION"
printf "$format" "MIN_IOS_VERSION:" "$MIN_IOS_VERSION"
printf "$format" "TVOS_SDK_VERSION:" "$TVOS_SDK_VERSION"
printf "$format" "TVOS_SDK_PATH:" "$TVOS_SDK_PATH"
printf "$format" "TVOSSIM_SDK_PATH:" "$TVOSSIM_SDK_PATH"
printf "$format" "MIN_TVOS_VERSION:" "$MIN_TVOS_VERSION"
printf "$format" "MACOS_SDK_VERSION:" "$MACOS_SDK_VERSION"
printf "$format" "MACOS_SDK_PATH:" "$MACOS_SDK_PATH"
printf "$format" "MIN_MACOS_VERSION:" "$MIN_MACOS_VERSION"
printf "$format" "MACOS_ARCHS:" "${MACOS_ARCHS[*]}"
printf "$format" "IOS_ARCHS:" "${IOS_ARCHS[*]}"
printf "$format" "BOOST_LIBS:" "$BOOST_LIBS"
printf "$format" "BOOST_SRC:" "$BOOST_SRC"
printf "$format" "IOS_BUILD_DIR:" "$IOS_BUILD_DIR"
printf "$format" "MACOS_BUILD_DIR:" "$MACOS_BUILD_DIR"
printf "$format" "IOS_FRAMEWORK_DIR:" "$IOS_FRAMEWORK_DIR"
printf "$format" "MACOS_FRAMEWORK_DIR:" "$MACOS_FRAMEWORK_DIR"
printf "$format" "XCODE_ROOT:" "$XCODE_ROOT"
printf "$format" "THREADS:" "$THREADS"
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
if [[ -n $BUILD_MACOS ]]; then
    updateBoost "macOS"
    bootstrapBoost "macOS"
    buildBoost_macOS
fi

scrunchAllLibsTogetherInOneLibPerPlatform
if [[ -n $UNIVERSAL ]]; then
    buildUniversal
fi

if [[ -z $NO_FRAMEWORK ]]; then
    if [[ -n $BUILD_IOS ]]; then
        buildFramework "$IOS_FRAMEWORK_DIR" "$IOS_OUTPUT_DIR"
    fi

    if [[ -n $BUILD_TVOS ]]; then
        buildFramework "$TVOS_FRAMEWORK_DIR" "$TVOS_OUTPUT_DIR"
    fi

    if [[ -n $BUILD_MACOS ]]; then
        buildFramework "$MACOS_FRAMEWORK_DIR" "$MACOS_OUTPUT_DIR"
    fi
fi

echo "Completed successfully"
