#!/bin/bash

if [ "$BASH_VERSION" = "" ] ; then
	echo "This is a Bash script. Please either start it normally (e.g.: \"./script.sh\"), or with Bash directly (e.g.: \"bash script.sh\")"
	exit 1
fi

if [ "$UID" == "0" ] && [ "$WINEWRAP_ALLOW_ROOT" != "1" ] ; then
	echo -e "You are trying to run this script as root - this is not recommended.\nTo avoid any undesirable results this script will abort.\nIf you want to run this as root anyway, set the environment variable WINEWRAP_ALLOW_ROOT=1"
	exit 1
fi

STARTWD="$PWD"
cd "$(dirname "$0")"
LOCALDIR="$PWD"

WRAP_NAME="Fallout 2"
WRAP_DIRNAME_DEF="Fallout 2"
WRAP_DIRNAME="$WRAP_DIRNAME_DEF"
WRAP_WINEVER=4.0
WRAP_WINEARCH=32
WRAP_WINESOURCE=playonlinux
WRAP_FILES=( "d8c41f8cf64340dd79e8cb0f9f4a0457e2f987722d3cc67d026f15382aa4a856"  "fallout2_res.tar.xz"
	"5dc5db430749ddcdfe856613fcb60ae8acc1405877952e872814bbc140f7ffa6"  "setup_fallout2_2.1.0.18.exe"
	)
WRAP_ALT_WINE_HASH=""
MAKEARCHIVE=""
TEST=0

echo "$WRAP_NAME (Wine wrapper)"

while [ "$1" != "" ] ; do
	ARGSTR=$(awk -F'=' '{print $1}' <<<"$1")
	if [ "$ARGSTR" == "-xz" ] ; then
		echo "Will build a .tar.xz archive"
		MAKEARCHIVE="xz"
	elif [ "$ARGSTR" == "-gz" ] ; then
		echo "Will build a .tar.gz archive"
		MAKEARCHIVE="gz"
	elif [ "$ARGSTR" == "-test" ] && [ "$TEST" != "1" ] ; then
		echo "Test mode; will not attempt to build wrapper"
		TEST=1
	elif [ "$ARGSTR" == "-winearch" ] ; then
		WRAP_WINEARCH="${1:10}"
		WRAP_ALT_WINE_HASH=""
	elif [ "$ARGSTR" == "-winesource" ] ; then
		WRAP_WINESOURCE="${1:12}"
	elif [ "$ARGSTR" == "-winever" ] ; then
		WRAP_WINEVER="${1:9}"
		WRAP_ALT_WINE_HASH=""
	elif [ "$ARGSTR" == "-buildpath" ] ; then
		WINEWRAP_BUILDPATH="${1:11}"
	elif [ "$ARGSTR" == "-respath" ] ; then
		WINEWRAP_RESPATH="${1:9}"
	elif [ "$ARGSTR" == "-dirname" ] ; then
		WRAP_DIRNAME="${1:9}"
	else
		echo "Unrecognised argument: $1"
		exit 3
	fi
	shift
done

if [ ! -v WINEWRAP_BUILDPATH ] || [ "$WINEWRAP_BUILDPATH" == "" ] ; then
	WINEWRAP_BUILDPATH="$STARTWD"
elif [ "${WINEWRAP_BUILDPATH:0:1}" != "/" ] ; then
	WINEWRAP_BUILDPATH="$STARTWD/$WINEWRAP_BUILDPATH"
fi
WINEWRAP_BUILDPATH="$(realpath -m "$WINEWRAP_BUILDPATH")"
if [ "$?" != "0" ] ; then
	echo "ERROR: realpath returned non-zero exit status."
	exit 2
fi
TEMP="$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/temp"

CHECKPATH="$WINEWRAP_BUILDPATH"
while [ ! -e "$CHECKPATH" ] ; do
	CHECKPATH="$(dirname "$CHECKPATH")"
done
if [ ! -d "$CHECKPATH" ] ; then
	echo -e "ERROR: Path to intended output directory \"$WINEWRAP_BUILDPATH/$WRAP_DIRNAME\" is invalid\n(\"$CHECKPATH\" is not a directory)"
	exit 2
fi
if [ "$(df -T "$CHECKPATH" | grep -e fuseblk -e fat)" != "" ] ; then
	echo -e "FAT or (probable) NTFS filesystem detected.\nPlease use a partition formatted with a Linux filesystem; this will not work on Windows-formatted partitions."
	exit 1
fi

if [ -e "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME" ] ; then
	echo "ERROR: Intended output directory \"$WINEWRAP_BUILDPATH/$WRAP_DIRNAME\" already exists. Please remove it then try again."
	exit 2
fi

if [ "$WRAP_WINEVER" == "" ] ; then
	echo "ERROR: Wine version not specified!"
	exit 4
fi
case $WRAP_WINEARCH in
	64|amd64|win64|x64|x86_64)
		export WINEARCH=win64
		;;
	*)
		export WINEARCH=win32
esac
if [[ "${WRAP_WINEVER: -3}" == -[[:digit:]][[:digit:]] ]] ; then
	if [ "${WRAP_WINEVER: -2}" == "64" ] ; then
		WRAP_WINEARCH=amd64
	elif [ "${WRAP_WINEVER: -2}" == "32" ] ; then
		WRAP_WINEARCH=x86
	fi
	WRAP_WINEVER="${WRAP_WINEVER:0: -3}"
	if [ "$WRAP_WINEARCH" == "x86" ] && [ "$WINEARCH" == "win64" ] ; then
		echo "ERROR: Cannot use a 32-bit Wine build with a 64-bit prefix!"
		exit
	fi
else
	if [ "$WINEARCH" == "win64" ] ; then
		WRAP_WINEARCH=amd64
	else
		WRAP_WINEARCH=x86
	fi
fi
WRAP_WINESOURCE="${WRAP_WINESOURCE,,}"
case $WRAP_WINESOURCE in
	lutris)
		WRAP_WINESOURCE=Lutris
		;;
	winewrap-dropbox)
		;;
	*)
		WRAP_WINESOURCE=PlayOnLinux
esac
if [ "${WRAP_WINEVER:0:6}" == "proton" ] ; then
	WRAP_WINESOURCE="winewrap-dropbox"
	WINEUSER="steamuser"
	echo "Using Proton ${WRAP_WINEVER:7} ($WINEARCH prefix)"
else
	WINEUSER="$USER"
	if [ "$WRAP_WINESOURCE" == "winewrap-dropbox" ] ; then
		echo "Using $WRAP_WINEVER (winewrap-dropbox, $WINEARCH prefix)"
	else
		echo "Using Wine $WRAP_WINEVER $WRAP_WINEARCH ($WRAP_WINESOURCE build, $WINEARCH prefix)"
	fi
fi

CACHEDIR="${XDG_CACHE_HOME:-$HOME/.cache}"

INNOCMD=""
echo "Checking for innoextract..."
if (innoextract --version >/dev/null) ; then
	if (( $(echo "$(innoextract --version | awk 'NR==1 {print $2}') >= 1.7" | bc -l) )) ; then
		echo "Using system provided innoextract"
		INNOCMD="innoextract"
	else
		echo "The system's version of innoextract is too old."
	fi
else
	echo "System installed innoextract not found."
fi

if [ "$INNOCMD" == "" ] ; then
	if [ ! -e "$CACHEDIR/winewrap/innoextract/innoextract-1.7-linux.tar.xz" ] ; then
		echo "Attempting to download innoextract-1.7-linux.tar.xz"
		if (! wget "http://constexpr.org/innoextract/files/innoextract-1.7-linux.tar.xz" -P "$CACHEDIR/winewrap/innoextract") ; then
			echo "An error occurred downloading innoextract"
			rm "$CACHEDIR/winewrap/innoextract/innoextract-1.7-linux.tar.xz"
			ERROR=1
		fi
	else
		echo "Using previously downloaded innoextract-1.7-linux.tar.xz in $CACHEDIR/winewrap/innoextract"
	fi
	if (! echo b3a6e0887afd951479a2f2b0612815f282fc2027a4b80a618073c2b0710dbb4b  "$CACHEDIR/winewrap/innoextract/innoextract-1.7-linux.tar.xz" | sha256sum -c) ; then
		echo "ERROR: Checksum failed for innoextract-1.7-linux.tar.xz !"
		rm "$CACHEDIR/winewrap/innoextract/innoextract-1.7-linux.tar.xz"
		ERROR=1
	else
		INNOARC="$CACHEDIR/winewrap/innoextract/innoextract-1.7-linux.tar.xz"
		INNOCMD="$TEMP/innoextract-1.7-linux/innoextract"
	fi
fi
echo "Checking for icoutils..."
if (! icotool --version >/dev/null) ; then
	echo "ERROR: attempt to invoke icotool failed; please make sure that the icoutils package (or your distro's equivalent) is installed"
	ERROR=1
fi
if (! wrestool --version >/dev/null) ; then
	echo "ERROR: attempt to invoke wrestool failed; please make sure that the icoutils package (or your distro's equivalent) is installed"
	ERROR=1
fi
if [ "$ERROR" == "1" ] ; then
	echo "One or more dependencies were not found."
	exit 5
fi

echo "Checking for installer and wrapper resource files..."

WRAP_FILES[1]="$LOCALDIR/${WRAP_FILES[1]}"

if [ "${WRAP_FILES[3]}" != "" ] ; then
	WINEWRAP_RESPATH_BAK="$WINEWRAP_RESPATH"
	if [ -v WINEWRAP_RESPATH ] && [ "$WINEWRAP_RESPATH" != "" ] ; then
		if [ "${WINEWRAP_RESPATH:0:1}" != "/" ] ; then
			WINEWRAP_RESPATH="$STARTWD/$WINEWRAP_RESPATH"
		fi
		WINEWRAP_RESPATH="$(realpath -m "$WINEWRAP_RESPATH")"
		if [ ! -e "$WINEWRAP_RESPATH" ] ; then
			echo "WARNING: The specified resource path does not exist!"
			WINEWRAP_RESPATH=""
		elif [ ! -d "$WINEWRAP_RESPATH" ] ; then
			WINEWRAP_RESPATH="$(dirname "$WINEWRAP_RESPATH")"
		fi
	fi
	if [ ! -v WINEWRAP_RESPATH ] || [ "$WINEWRAP_RESPATH" == "" ] || [ ! -e "$WINEWRAP_RESPATH/${WRAP_FILES[3]}" ] ; then
		if [ -e "$STARTWD/${WRAP_FILES[3]}" ] ; then
			WINEWRAP_RESPATH="$STARTWD"
		elif [ -e "$WINEWRAP_BUILDPATH/${WRAP_FILES[3]}" ] ; then
			WINEWRAP_RESPATH="$WINEWRAP_BUILDPATH"
		else
			WINEWRAP_RESPATH="$LOCALDIR"
		fi
	fi
	if [ ! -e "$WINEWRAP_RESPATH/setup_fallout2_2.1.0.18.exe" ] ; then
		WRAP_FILES[2]=9570800cd7a0c53f47b0883a861d354e33e36b98eeafbc716874781503625228
		WRAP_FILES[3]=setup_fallout2_2.1.0.17.exe
		WINEWRAP_RESPATH="$WINEWRAP_RESPATH_BAK"
		if [ -v WINEWRAP_RESPATH ] && [ "$WINEWRAP_RESPATH" != "" ] ; then
			if [ "${WINEWRAP_RESPATH:0:1}" != "/" ] ; then
				WINEWRAP_RESPATH="$STARTWD/$WINEWRAP_RESPATH"
			fi
			WINEWRAP_RESPATH="$(realpath -m "$WINEWRAP_RESPATH")"
			if [ ! -e "$WINEWRAP_RESPATH" ] ; then
				echo "WARNING: The specified resource path does not exist!"
				WINEWRAP_RESPATH=""
			elif [ ! -d "$WINEWRAP_RESPATH" ] ; then
				WINEWRAP_RESPATH="$(dirname "$WINEWRAP_RESPATH")"
			fi
		fi
		if [ ! -v WINEWRAP_RESPATH ] || [ "$WINEWRAP_RESPATH" == "" ] || [ ! -e "$WINEWRAP_RESPATH/${WRAP_FILES[3]}" ] ; then
			if [ -e "$STARTWD/${WRAP_FILES[3]}" ] ; then
				WINEWRAP_RESPATH="$STARTWD"
			elif [ -e "$WINEWRAP_BUILDPATH/${WRAP_FILES[3]}" ] ; then
				WINEWRAP_RESPATH="$WINEWRAP_BUILDPATH"
			else
				WINEWRAP_RESPATH="$LOCALDIR"
			fi
		fi
	fi
fi

if [ ! -f "${WRAP_FILES[1]}" ] ; then
	echo "Missing wrapper resource archive"
	ERROR=1
fi
FCOUNT=1
while [ "${WRAP_FILES[(($FCOUNT*2+1))]}" != "" ] ; do
	if [ ! -f "$WINEWRAP_RESPATH/${WRAP_FILES[(($FCOUNT*2+1))]}" ] ; then
		echo "Missing file: ${WRAP_FILES[(($FCOUNT*2+1))]}"
		ERROR=1
	fi
	WRAP_FILES[(($FCOUNT*2+1))]="$WINEWRAP_RESPATH/${WRAP_FILES[(($FCOUNT*2+1))]}"
	((FCOUNT++))
done

if [ "$ERROR" == "1" ] ; then
	echo -e "\nERROR: One or more required files are missing."
	exit 6
fi

echo "All files found."

# Check for Wine and Winetricks, download if needed

if [ ! -e "$CACHEDIR/winewrap" ] ; then
	mkdir "$CACHEDIR/winewrap"
fi

cd "$CACHEDIR/winewrap"

if [ "$WRAP_WINESOURCE" == "winewrap-dropbox" ] ; then
	WINEARCHIVE="$WRAP_WINEVER.tar.xz"
	if [ ! -e "$CACHEDIR/winewrap/$WINEARCHIVE" ] ; then
		echo "Proton package not found, attempting to download..."
		if (! wget -N "https://www.dropbox.com/s/dl/x8d5z6nnzhj0lh8/winewrap-proton-index") ; then
			echo "ERROR: Failed to download index file"
			exit 7
		fi
		DBCODE=$(grep -m1 "^$WRAP_WINEVER#" "winewrap-proton-index" | awk '{print $2}')
		if [ "$DBCODE" == "" ] ; then
			echo "ERROR: The specified Proton build was not found!"
			exit 7
		fi
		if (! wget "https://www.dropbox.com/s/dl/$DBCODE/$WINEARCHIVE") ; then
			echo "ERROR: Failed to download the specified Proton build"
			rm "$WINEARCHIVE"
			exit 7
		fi
	fi
	if [ ! -e "winewrap-proton-index" ] ; then
		echo "WARNING: Index file not present; checksum for the specified Proton build cannot be tested."
	else
		WRAP_ALT_WINE_HASH=$(grep -m1 "^$WRAP_WINEVER#" "winewrap-proton-index" | awk '{print $3}')
		if [ "$WRAP_ALT_WINE_HASH" == "" ] ; then
			echo "WARNING: Index file does not contain information for the specified Proton build; its checksum cannot be tested."
		fi
	fi
	if [ "$WRAP_ALT_WINE_HASH" != "" ] ; then
		if (! echo $WRAP_ALT_WINE_HASH  $WINEARCHIVE | sha256sum -c) ; then
			echo "ERROR: Checksum failed for $WINEARCHIVE !"
			rm "$WINEARCHIVE"
			exit 8
		fi
	fi
elif [ "$WRAP_WINESOURCE" == "Lutris" ] ; then
	if [ "$WRAP_WINEARCH" == "amd64" ] ; then
		WINEARCHIVE=x86_64
	else
		WINEARCHIVE=i686
	fi
	if [ "${WRAP_WINEVER: -8}" == "-staging" ] ; then
		WINEARCHIVE="wine-staging-${WRAP_WINEVER:0: -8}-$WINEARCHIVE.tar.gz"
	else
		WINEARCHIVE="wine-$WRAP_WINEVER-$WINEARCHIVE.tar.gz"
	fi
	if [ ! -e "$CACHEDIR/winewrap/$WINEARCHIVE" ] ; then
		echo "Wine package not found, attempting to download..."
		WINEURL=$(wget "https://lutris.net/api/runners?search=wine" -O - | sed -e 's/"url":"/\n/g' -e 's/",/\n/g' | grep '^http' | grep -m1 "/$WINEARCHIVE\$")
		if [ "$WINEURL" == "" ] ; then
			echo "ERROR: Failed to download index or the specified Wine build was not found!"
			exit 7
		fi
		if (! wget "$WINEURL") ; then
			echo "ERROR: Failed to download the specified Wine build"
			rm "$WINEARCHIVE"
			exit 7
		fi
	fi
	if [ "$WRAP_ALT_WINE_HASH" == "" ] ; then
		echo "WARNING: Alternative Lutris Wine package specified; checksum cannot be tested"
	else
		echo "Testing checksum for $WINEARCHIVE"
		if (! echo $WRAP_ALT_WINE_HASH  $WINEARCHIVE | sha256sum -c) ; then
			echo "ERROR: Checksum failed for $WINEARCHIVE !"
			rm "$WINEARCHIVE"
			exit 8
		fi
	fi
else
	if [ "${WRAP_WINEVER:0:8}" == "staging-" ] ; then
		WRAP_WINEVER="${WRAP_WINEVER:8}-staging"
	fi
	if [ "${WRAP_WINEVER: -8}" == "-staging" ] ; then
		WINEARCHIVE="PlayOnLinux-wine-$WRAP_WINEVER-linux-$WRAP_WINEARCH.tar.gz"
		WINEURL="https://www.playonlinux.com/wine/binaries/phoenicis/staging-linux-$WRAP_WINEARCH/$WINEARCHIVE"
	else
		WINEARCHIVE="PlayOnLinux-wine-$WRAP_WINEVER-upstream-linux-$WRAP_WINEARCH.tar.gz"
		WINEURL="https://www.playonlinux.com/wine/binaries/phoenicis/upstream-linux-$WRAP_WINEARCH/$WINEARCHIVE"
	fi
	if [ ! -e "$WINEARCHIVE" ] ; then
		echo "Wine package not found, attempting to download..."
		if (! wget "$WINEURL") ; then
			echo "ERROR: Failed to download $WINEARCHIVE"
			rm "$WINEARCHIVE"
			exit 7
		fi
	fi
	if [ ! -e "$WINEARCHIVE.sha1" ] ; then
		echo "Wine package hashfile not found, attempting to download..."
		if (! wget "$WINEURL.sha1") ; then
			echo "ERROR: Failed to download $WINEARCHIVE.sha1"
			rm "$WINEARCHIVE.sha1"
			exit 7
		fi
	fi
	echo "Testing checksum for $WINEARCHIVE"
	if (! sha1sum -c "$WINEARCHIVE.sha1") ; then
		echo "ERROR: Checksum failed for $WINEARCHIVE !"
		rm "$WINEARCHIVE"
		rm "$WINEARCHIVE.sha1"
		exit 8
	fi
fi

cd "$LOCALDIR"

if [ ! -f "$CACHEDIR/winewrap/winetricks" ] || ([ "$WINEWRAP_ALLOW_WTUPDATE" != "0" ] && [ $(($(date +%s)-$(date -r "$CACHEDIR/winewrap/winetricks" +%s))) -gt 2419200 ]) ; then
	echo "Winetricks not found or outdated, attempting to download..."
	if [ -f "$CACHEDIR/winewrap/winetricks" ] ; then
		mv "$CACHEDIR/winewrap/winetricks" "$CACHEDIR/winewrap/winetricks.bak"
	fi
	if (! wget "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" -P "$CACHEDIR/winewrap") ; then
		echo "An error occurred downloading Winetricks"
		rm "$CACHEDIR/winewrap/winetricks"
		if [ -f "$CACHEDIR/winewrap/winetricks.bak" ] ; then
			echo "Will continue using the old version."
			mv "$CACHEDIR/winewrap/winetricks.bak" "$CACHEDIR/winewrap/winetricks"
		else
			exit 9
		fi
	fi
	if [ -f "$CACHEDIR/winewrap/winetricks.bak" ] ; then
		rm "$CACHEDIR/winewrap/winetricks.bak"
	fi
	chmod +x "$CACHEDIR/winewrap/winetricks"
elif [ $(($(date +%s)-$(date -r "$CACHEDIR/winewrap/winetricks" +%s))) -gt 2419200 ] ; then
	echo "The previously downloaded copy of winetricks is over 28 days old. You might want to remove it to allow the script to download a newer version; alternatively you can set WINEWRAP_ALLOW_WTUPDATE=1 to have the wrapper script do it automatically."
fi

echo "Checking for the lnkread archive..."
if [ ! -f "$CACHEDIR/winewrap/lnkread-20180903.tar.xz" ] ; then
	echo "lnkread archive not found, attempting to download..."
	if (! wget "https://www.dropbox.com/s/dl/xrmp3hc0ite7hb8/lnkread-20180903.tar.xz" -P "$CACHEDIR/winewrap") ; then
		echo "An error occurred downloading the lnkread archive. Script will continue but the wrapper will be unable to create shortcuts from .lnk files without it."
		rm "$CACHEDIR/winewrap/lnkread-20180903.tar.xz"
	fi
fi

if [ -f "$CACHEDIR/winewrap/lnkread-20180903.tar.xz" ] && (! echo b4f4ff1558eed2862de8cda4a8017114e6bae9421b7fc74ee9615ce214e12470  "$CACHEDIR/winewrap/lnkread-20180903.tar.xz" | sha256sum -c) ; then
	echo "ERROR: Checksum failed for lnkread-20180903.tar.xz! Script will continue but the wrapper will be unable to create shortcuts from .lnk files without it."
	rm "$CACHEDIR/winewrap/lnkread-20180903.tar.xz"
fi

##### Additional resources #####

echo "Checking for Wine Mono..."
if [ ! -f "$CACHEDIR/wine/wine-mono-4.7.5.msi" ] ; then
	echo "Wine Mono not found, attempting to download..."
	if (! wget "https://dl.winehq.org/wine/wine-mono/4.7.5/wine-mono-4.7.5.msi" -P "$CACHEDIR/wine" ) ; then
		echo "An error occurred downloading Wine Mono"
		rm "$CACHEDIR/wine/wine-mono-4.7.5.msi"
		exit 10
	fi
fi

if (! echo 154d68d476cdedef56f159d837fbb5eef9358a9f85de89f86c189ec4da004b3f  "$CACHEDIR/wine/wine-mono-4.7.5.msi" | sha256sum -c) ; then
	echo "ERROR: Checksum failed for wine-mono-4.7.5.msi !"
	rm "$CACHEDIR/wine/wine-mono-4.7.5.msi"
	exit 11
fi

################################

if [ "$WINEWRAP_SKIP_CHECKSUMS" == "1" ] ; then
	echo "WARNING: skipping installer and resource archive checksum tests!"
else
	echo "Testing SHA256 hashes for installer and wrapper resource files..."
	for ((FNUM=0 ; FNUM < FCOUNT ; FNUM++)) ; do
		if (! echo "${WRAP_FILES[(($FNUM*2))]}  ${WRAP_FILES[(($FNUM*2+1))]}" | sha256sum -c) ; then
			ERROR=1
		fi
	done
	if [ "$ERROR" == "1" ] ; then
		echo "ERROR: checksum failed on one or more files"
		exit 12
	fi
fi



if [ "$TEST" == "1" ] ; then
	echo "Test complete"
	exit
fi

echo "Creating directories..."
mkdir -p "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/"{docs,support,wine} "$TEMP"

if [ "$INNOCMD" != "innoextract" ] ; then
	echo "Extracting innoextract..."
	tar -xf "$INNOARC" -C "$TEMP"
fi

echo "Extracting Wine..."
if [ "$WRAP_WINESOURCE" != "PlayOnLinux" ] ; then
	if (! tar -xf "$CACHEDIR/winewrap/$WINEARCHIVE" -C "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/wine" --strip-components=1) ; then
		echo "An error occurred trying to unpack Wine."
		exit 13
	fi
else
	if (! tar -xf "$CACHEDIR/winewrap/$WINEARCHIVE" -C "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/wine") ; then
		echo "An error occurred trying to unpack Wine."
		exit 13
	fi
fi

export WINEVERPATH="$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/wine"
export PATH="$WINEVERPATH/bin:$PATH"
export LD_LIBRARY_PATH="$WINEVERPATH/lib:$WINEVERPATH/lib64:$LD_LIBRARY_PATH"
export WINE="$WINEVERPATH/bin/wine"
export WINELOADER="$WINEVERPATH/bin/wine"
export WINESERVER="$WINEVERPATH/bin/wineserver"
export WINEDLLPATH="$WINEVERPATH/lib/wine:$WINEVERPATH/lib64/wine"
export WINEPREFIX="$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/prefix"
export WINEDLLOVERRIDES=mshtml,winemenubuilder.exe=d
export WINEDEBUG=-all

echo "Creating Wine prefix..."
if (! "$WINE" wineboot.exe) ; then
	echo "An error occurred trying to create the prefix."
	exit 14
fi

if [ "${WRAP_WINEVER:0:6}" == "proton" ] ; then
	echo "1" >"$WINEPREFIX/.proton-prefix"
	if [ "$WINEARCH" == "win32" ] ; then
		for X in d3d9 d3d10 d3d10_1 d3d10core d3d11 dxgi ; do
			ln -srf "$WINEVERPATH/lib/wine/fakedlls/$X.dll" "$WINEPREFIX/drive_c/windows/system32/$X.dll"
		done
	else
		for X in d3d9 d3d10 d3d10_1 d3d10core d3d11 dxgi ; do
			ln -srf "$WINEVERPATH/lib/wine/fakedlls/$X.dll" "$WINEPREFIX/drive_c/windows/syswow64/$X.dll"
			ln -srf "$WINEVERPATH/lib64/wine/fakedlls/$X.dll" "$WINEPREFIX/drive_c/windows/system32/$X.dll"
		done
	fi
else
	echo "0" >"$WINEPREFIX/.proton-prefix"
fi

echo "Extracting $WRAP_NAME..."
if [ ! -e "$WINEWRAP_RESPATH/setup_fallout2_2.1.0.18.exe" ] ; then
	if (! "$INNOCMD" "$WINEWRAP_RESPATH/setup_fallout2_2.1.0.17.exe" -g -d "$TEMP") ; then
		echo "ERROR: innoextract failed."
		exit 15
	fi
else
	if (! "$INNOCMD" "$WINEWRAP_RESPATH/setup_fallout2_2.1.0.18.exe" -g -d "$TEMP") ; then
		echo "ERROR: innoextract failed."
		exit 15
	fi
fi

if (! tar -xf "${WRAP_FILES[1]}" -C "$TEMP") ; then
	echo "An error occurred trying to unpack the wrapper resource archive."
	exit 16
fi

"$WINE" regedit "$TEMP/fallout2.reg"

echo "Moving files into place..."
mv "$TEMP/start.sh" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME"
mv "$TEMP/winewrap.shlib" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/support"
tar -xf "$CACHEDIR/winewrap/lnkread-20180903.tar.xz" -C "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/support" lnkread
mv "$TEMP/fallout2_rel_notes.txt" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/docs"
mv "$TEMP/winewrap-licenseinfo.txt" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/docs"
mv "$TEMP/tmp/GOG_EULA.txt" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/docs"
mv "$TEMP/app/manual.pdf" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/docs"
mv "$TEMP/app/refcard.pdf" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/docs"
mv "$TEMP/app/sfall-readme.txt" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/docs"
rm -rf "$TEMP/app/__support"
rm "$TEMP/app/f2_res.ini"
mkdir "$TEMP/app/userdata-defaults"
mv "$TEMP/f2_res.ini.1" "$TEMP/app/userdata-defaults"
mv "$TEMP/f2_res.ini.3" "$TEMP/app/userdata-defaults"

cp "$CACHEDIR/winewrap/winetricks" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/support"

if [ ! -e "$TEMP/app/goggame-1440151285.ico" ] ; then
	icotool -x -w256 "$TEMP/app/goggame-2.ico" -o "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/support/gog-fallout2-icon.png"
else
	icotool -x -w256 "$TEMP/app/goggame-1440151285.ico" -o "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/support/gog-fallout2-icon.png"
fi
wrestool -x -t14 "$TEMP/app/fallout2HR.exe" -o "$TEMP/fallout2-icon.ico"
icotool -x -i4 "$TEMP/fallout2-icon.ico" -o "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/support/fallout2-icon.png"

mv "$TEMP/app" "$WINEPREFIX/drive_c/$WRAP_DIRNAME_DEF"
ln -s -r "$WINEPREFIX/drive_c/$WRAP_DIRNAME_DEF" "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME/gamedir"

"$WINESERVER" -w

rm -rf "$TEMP"
rm -rf "$WINEPREFIX/drive_c/windows/Installer/"*
rm -rf "$WINEPREFIX/drive_c/users/$WINEUSER"

echo "Done."

if [ "$MAKEARCHIVE" == "xz" ] ; then
	echo "Building .tar.xz archive (this will take a while)"
	if (! tar -cf "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME_DEF-Linux.tar.xz" -C "$WINEWRAP_BUILDPATH" "$WRAP_DIRNAME" --xz) ; then
		echo "An error occurred building the tarball"
		exit 17
	fi
elif [ "$MAKEARCHIVE" == "gz" ] ; then
	echo "Building .tar.gz archive (this will take a while)"
	if (! tar -cf "$WINEWRAP_BUILDPATH/$WRAP_DIRNAME_DEF-Linux.tar.gz" -C "$WINEWRAP_BUILDPATH" "$WRAP_DIRNAME" --gz) ; then
		echo "An error occurred building the tarball"
		exit 17
	fi
fi
