# Apple-Boost-BuildScript
Script for building Boost for Apple platforms (iOS, iOS Simulator, tvOS, tvOS Simulator, macOS)

This is a new location for my previous GIST:
    https://gist.github.com/faithfracture/c629ae4c7168216a9856

Builds a Boost framework for iOS, iOS Simulator, tvOS, tvOS Simulator, and macOS (including Apple Silicon).
Creates a set of universal libraries that can be used on iOS/tvOS/macOS and in the
iOS/tvOS simulators. Then creates a pseudo-framework to make using boost in Xcode
less painful.

To configure the script, define:
```
   BOOST_VERSION:     Which version of Boost to build (e.g. 1.70.0)
   BOOST_LIBS:        Which Boost libraries to build
   IOS_SDK_VERSION:   iOS SDK version (e.g. 12.0)
   MIN_IOS_VERSION:   Minimum iOS Target Version (e.g. 11.0)
   TVOS_SDK_VERSION:  tvOS SDK version (e.g. 12.0)
   MIN_TVOS_VERSION:  Minimum tvOS Target Version (e.g. 11.0)
   MACOS_SDK_VERSION:  macOS SDK version (e.g. 10.14)
   MIN_MACOS_VERSION:  Minimum macOS Target Version (e.g. 10.12)
   MACOS_SILICON_SDK_VERSION: macOS SDK version for Apple Silicon (e.g. 11.0)
   MIN_MACOS_SILICON_VERSION: Minimum macOS Target Version for Apple Silicon (e.g. 11.0)
```

If a boost tarball (a file named “boost_$BOOST_VERSION2.tar.bz2”) does not
exist in the current directory, this script will attempt to download the
version specified. You may also manually place a matching tarball in the 
current directory and the script will use that.

usage: `./boost.sh [{-ios,-tvos,-macos} ...] options`

Run `./boost.sh -h` for descriptions of all options.
