# Apple-Boost-BuildScript
Script for building Boost for Apple platforms (iOS, iOS Simulator, tvOS, tvOS Simulator, OS X)

This is a new location for my previous GIST:
    https://gist.github.com/faithfracture/c629ae4c7168216a9856

Builds a Boost framework for iOS, iOS Simulator, tvOS, tvOS Simulator, and OSX.
Creates a set of universal libraries that can be used on iOS/tvOS/OSX and in the
iOS/tvOS simulators. Then creates a pseudo-framework to make using boost in Xcode
less painful.

To configure the script, define:
```
   BOOST_VERSION:    Which version of Boost to build (e.g. 1.58.0)
   BOOST_VERSION2:   Same as BOOST_VERSION, but with _ instead of . (e.g. 1_58_0)
   BOOST_LIBS:       Which Boost libraries to build
   IOS_SDK_VERSION:  iOS SDK version (e.g. 9.0)
   MIN_IOS_VERSION:  Minimum iOS Target Version (e.g. 8.0)
   TVOS_SDK_VERSION: tvOS SDK version (e.g. 9.2)
   MIN_TVOS_VERSION: Minimum tvOS Target Version (e.g. 9.2)
   OSX_SDK_VERSION:  OSX SDK version (e.g. 10.11)
   MIN_OSX_VERSION:  Minimum OS X Target Version (e.g. 10.10)
```

If a boost tarball (a file named “boost_$BOOST_VERSION2.tar.bz2”) does not
exist in the current directory, this script will attempt to download the
version specified by BOOST_VERSION2. You may also manually place a matching 
tarball in the current directory and the script will use that.

usage: `./boost.sh [{-ios,-tvos,-osx} ...] options`

Run `./boost.sh -h` for descriptions of all options.
