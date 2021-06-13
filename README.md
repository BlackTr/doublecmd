## Double Commander

Double Commander is a cross platform open source file manager with two panels
side by side. It is inspired by Total Commander and features some new ideas.

[Home](https://doublecmd.sourceforge.io/)  
[Download&Install](https://sourceforge.net/p/doublecmd/wiki/Download/)

## Compiling Double Commander

1) What you need?

Double Commander is developed with Free Pascal and Lazarus.
Current version requires at least FPC 3.2.0 and Lazarus 2.0.10.

2) Using the IDE to develop and build DC.

If you want to use Lazarus IDE to develop Double Commander, first you have to
install a few additional components all of which reside in components
directory of DC sources. You must open each .lpk package file:

- chsdet/chsdet.lpk
- CmdLine/cmdbox.lpk
- multithreadprocs/multithreadprocslaz.lpk
- dcpcrypt/dcpcrypt.lpk
- doublecmd/doublecmd_common.lpk
- gifanim/pkg_gifanim.lpk
- KASToolBar/kascomp.lpk
- synunihighlighter/synuni.lpk
- viewer/viewerpackage.lpk

and install it into Lazarus (menu: Package -> Open package file (.lpk) -> Browse
to needed .lpk file -> Press "Install", if "Install" disabled then press
"Compile" instead). Choose "No" when asked for rebuilding Lazarus after each
package then rebuild Lazarus when you have installed all of them.

After rebuilding Lazarus open the project file src/doublecmd.lpi.

Compile.

3) Building DC from command line.

#### From command line (Windows)

Use build.bat script to build DC on Windows.

First you need the lazbuild utility of Lazarus to be somewhere in your PATH or
you need to edit the build script and change the lazpath variable to point to
it.

Execute the script to start the build process. Make sure you use all parameter
if you're building for the first time, so that also components and plugins are
built:

```
build.bat all
```
or alternatively without plugins

```
build.bat components
build.bat
```

#### From command line (Linux)

Use build.sh script to build DC on Linux.

First you need the lazbuild utility of Lazarus to be somewhere in your PATH and
if you installed a Lazarus package it should already be there. Otherwise you
need to edit the build script and change the lazbuild variable to point to it.

On Linux three widgetsets are supported: GTK2, Qt4 and Qt5. You can choose one
by setting lcl environment variable before executing the script to either gtk2,
qt or qt5 for example:

```
lcl=qt ./build.sh
```

Execute the script to start the build process. Make sure you use all parameter
if you're building for the first time, so that also components and plugins are
built:

```
./build.sh all
```

or alternatively without plugins

```
./build.sh components
./build.sh
```

#### From command line (MacOS)

Use build.sh script to build DC on MacOS.

First you need the lazbuild utility of Lazarus to be somewhere in your PATH and
if you installed a Lazarus package it should already be there. Otherwise you
need to edit the build script and change the lazbuild variable to point to it.

On MacOS 1 widgetsets are supported: cocoa.

Execute the script to start the build process. Make sure you use all parameter
if you're building for the first time, so that also components and plugins are
built:

```
./build.sh all cocoa
```

or alternatively without plugins

```
./build.sh components cocoa
lcl=cocoa ./build.sh
```

build plugins

```
./build.sh plugins cocoa
```

generate dmg

```
cd install/
./create_packages.mac 
```
