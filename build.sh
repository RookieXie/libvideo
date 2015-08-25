#!/bin/bash

test=1
nuget=1
run=0
cache=0
config="Release"

scriptroot="$(cd "$(dirname $0)" && pwd -P)"
nugetpath="$scriptroot/NuGet.exe"
cachefile="$scriptroot/$(basename $0).cache"
targets="portable-net45+win+wpa81"

msbuildprompt="Please specify the directory where MSBuild is installed.
Example: ./build.sh --msbuild \"/C/Program Files (x86)/MSBuild/14.0/Bin\""

usage="Usage: ./build.sh [OPTION]...

Options:

-c, --config [DEBUG|RELEASE]   set build configuration to Debug or Release
-h, --help                     display this help text and exit
-m, --msbuild                  specify path to MSBuild.exe (required on first run)
--nocache                      do not cache the path to MSBuild.exe if specified
--norun                        build nothing unless specified by other options
-n, --nuget                    create NuGet package post-build"

usage() {
    echo "$usage" 1>&2
}

failerr() {
    exitcode=$?
    if [ "$exitcode" -ne 0 ]
    then
        echo "$1" 1>&2
        exit $exitcode
    fi
}

project() {
    if [ "$1" != "packages" ] && [ "$1" != ".vs" ] && [ "${1##*.}" != "sln" ]
    then
        return 0
    fi

    return 1
}

executable() {
    grep "<OutputType>Exe</OutputType>" "$1/$1.csproj" &> /dev/null
    return "$?"
}

buildproj() {
    $nugetpath restore
    "$msbuildpath" /property:Configuration=$config
}

# get options
while [[ "$#" > 0 ]]
do
    case "$1" in
        -t|--test)
            test=0
            ;;
        -n|--nuget)
            nuget=0
            ;;
        -c|--config)
            case "${2,,}" in
                "debug")
                    config="Debug"
                    ;;
                "release")
                    # enabled by default
                    ;;
                *)
                    usage
                    exit 1
                    ;;
            esac
            shift
            ;;
        --norun)
            run=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -m|--msbuild)
            # IMPORTANT: all reads/writes to $msbuildpath MUST be quoted
            # because the typical path for Windows users is in Program Files (x86).
            msbuildpath="$2/MSBuild.exe"
            shift
            ;;
        --nocache)
            cache=1
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

# determine path to MSBuild.exe
if [ -z "$msbuildpath" ]
then
    msbuildpath="$(cat $cachefile 2> /dev/null)"

    if [ $? -ne 0 ]
    then
        echo "$msbuildprompt" 1>&2
        exit 1
    elif [ ! -e "$msbuildpath" ]
    then
        echo "\"$msbuildpath\" was read from the cache, but it does not exist." 1>&2
        echo "$msbuildprompt" 1>&2
        exit 1
    fi
else
    if [ ! -e "$msbuildpath" ]
    then
        echo "\"$msbuildpath\" does not exist." 1>&2
        exit 1
    fi

    if [ $cache -eq 0 ]
    then
        echo "$msbuildpath" > $cachefile
    fi
fi

# restore NuGet.exe if not yet installed
# will admit I stole a few of these lines from the CoreFX build.sh...
if [ ! -e $nugetpath ]
then
    echo "Restoring NuGet.exe..."

    # curl has HTTPS CA trust-issues less often than wget, so try that first
    which curl &> /dev/null
    if [ $? -eq 0 ]; then
       curl -sSL -o $nugetpath https://api.nuget.org/downloads/nuget.exe
   else
       which wget &> /dev/null
       failerr "cURL or wget is required to build libvideo."
       wget -q -O $nugetpath https://api.nuget.org/downloads/nuget.exe
    fi

    failerr "Failed to restore NuGet.exe."
fi

# start the actual build

if [ "$run" -eq 0 ]
then
    echo "Building src..."
    cd $scriptroot/src
    buildproj

    failerr "MSBuild failed on libvideo.sln! Exiting..."
fi

if [ "$test" -eq 0 ]
then
    echo "Running tests..."

    for test in $scriptroot/tests/*
    do
        echo "Building test $test..."
        cd $test
        buildproj

        failerr "MSBuild failed on $test.sln! Exiting..."

        for subtest in *
        do
            if project "$subtest" && executable "$subtest"
            then
                echo "Running subtest $subtest..."
                cd $subtest/bin/$config
                ./$subtest.exe

                failerr "Subtest $subtest failed! Exiting..."
            fi
        done
    done
fi

if [ "$nuget" -eq 0 ]
then
    echo "Creating NuGet packages..."

    for packageroot in $scriptroot/nuget/*
    do
        package="$(basename $packageroot)"
        echo "Getting assemblies for $package..."
        mkdir -p $packageroot/lib/$targets
        cd $scriptroot/src/$package/bin/$config
        cp $package.dll $packageroot/lib/$targets

        echo "Cleaning existing $package packages..."
        cd $packageroot
        rm *.nupkg 2> /dev/null

        for spec in *.nuspec
        do
            echo "Packing $spec..."
            $nugetpath pack $spec

            failerr "Packing $spec failed! Exiting..."
        done
    done
fi
