
function startemacsclient() {
  if [ "x${OSFLAVOR}" = "xDarwin" ]; then
    emacsclient -n --socket=/tmp/emacs${AUID}/server $1 &
    disown $!
  else
    emacsclient --socket-name=server$DISPLAY -n $1 &
  fi
}

function startemacs() {
  local em="$EDITOR"
  if [ -z "$EDITOR" ]; then
    em=emacs
  fi
  ${em} $* &
  disown $!
}

function docmd() {
  echo "executing: $*"
  $*
}

function setdeflocale() {
  # I seem to need this only when chromoting... why?
  export LANG=en_US.UTF-8
  export LANGUAGE=en_US:
}

function anyprogbash() {
  local S="$1"
  anyprog.py "$S"
  declare -F | egrep "$S"
}

function format_process_for_btrfs() {
  # read
  echo read docs at http://btrfs.wiki.kernel.org
  # list disks with:
  echo list disks with: sudo lshw -class disk
  # run fdisk to create single partition
  echo to create single partition run: sudo fdisk /dev/sdx
  # create btrfs filesystem in single partition
  echo to create btrfs filesystem in partition run: sudo mkfs.btrfs /dev/sdx1
  # then add entry to /etc/fstab
  echo then add entry to fstab: sudo emacs /etc/fstab
}

function create_btrfs_subvolume() {
  local V=$1
  snapshotutil.py mkvol $V
}

function create_btrfs_snapshot() {
  local FROM=$1
  local TO=$2
  snapshotutil.py mksnap $FROM $TO
}

function remove_btrfs_snapshot() {
  local SNAME=$1
  snapshotutil.py rmsnap $SNAME
}

function remove_btrfs_subvolume() {
  local VNAME=$1
  snapshotutil.py rmvol $VNAME
}

function genfilelists() {
  prune-android-filelist.pl < filelist > allfiles.txt
  cat allfiles.txt | egrep '(.+\.cpp$|.+\.cc$|.+\.h$)' > cppfiles.txt
  cat allfiles.txt | egrep '.+\.c$' > cfiles.txt
  cat allfiles.txt | egrep '.+\.java$' > jfiles.txt
  cat allfiles.txt | egrep '.+\.py$' > pyfiles.txt
  cat allfiles.txt | egrep '.+\.proto$' > protofiles.txt
  cat cfiles.txt cppfiles.txt | sort > cxxfiles.txt
  find . -name "*.mk" -print > mkfiles.txt
}

function agtags () {
    croot
    rm -f GPATH GTAGS GRTAGS GSYMS
    rm -f filelist # force regeneration
    godir /dev/null > /dev/null
    genfilelists
    tmpdir=/tmp/gtags-$$-$RANDOM
    mkdir $tmpdir
    grep -v '\$assert.java' filelist | grep -v '^\./external/valgrind/memcheck/tests/' | grep -v '^\./external/pdfium' | grep -v '^\./external/markdown' | grep -v '^\./external/valgrind/main/memcheck/tests/' | filter-out-embedded-spaces.py | nice ionice -c 3 gtags --file - $tmpdir
    mv $tmpdir/* .
    rmdir $tmpdir
}

function agfiles () {
    croot
    rm -f filelist # force regeneration
    godir /dev/null > /dev/null
    genfilelists
}

function agmkid () {
    local HERE=""
    croot
    HERE=`pwd`
    echo "... regenerating filelist"
    rm -f filelist # force regeneration
    godir /dev/null > /dev/null
    genfilelists
    tr "\n" "\0" < cxxfiles.txt > cxxfiles0.txt
    echo "... running mkid in $HERE"
    mkid --files0-from cxxfiles0.txt
    rm -f cxxfiles0.txt
    echo "... ID file created in $HERE"
}

function help_btrfs() {
  echo "Options: "
  echo " showsnapshots.py   --   show subvolumes and snapshots"
  echo " bfmkvol ZZZ        --   create new subvolume /ssd*/ZZZ"
  echo " bfrmvol ZZZ        --   delete subvolume ZZZ"
  echo " bfmksnap ZZZ YYY   --   create new snapshot YYY from subvolume ZZZ"
  echo " bfrmsnap YYY       --   delete snapshot YYY"
}

# prev N6 ZX1G22CVN4
export DEVTAGS="N4:0192152d60190bd4 N5:021ea77ef0a69c95"
export CODENAMETOTAG="mako:N4 hammerhead:N5"

function which_android_device() {
  if [ -z $ANDROID_SERIAL ]; then
    echo "** ANDROID_SERIAL not set"
    return
  fi
  TAG=`echo $DEVTAGS | tr " " "\n" | egrep "\:${ANDROID_SERIAL}"`
  if [ -z $TAG ]; then
    echo "** unknown device serial number $ANDROID_SERIAL"
    return
  fi
  echo $TAG |  cut -f1 -d:
}

function select_android_device() {
  local WHICH=$1
  local ADB=$2
  local S=""
  local AOUT=""
  local ST=""

  if [ -z $WHICH ]; then
    echo "** supply device (N5, N9) as single arg"
    return
  fi
  TAG=`echo $DEVTAGS | tr " " "\n" | egrep "^${WHICH}\:"`
  if [ -z $TAG ]; then
    echo "** unknown device tag $TAG"
    return
  fi
  S=`echo $TAG |  cut -f2 -d:`
  export ANDROID_SERIAL=

  if [ "x$ADB" = "x" ]; then
    ADB=adb
  fi

  AOUT=`$ADB version`
  ST=$?
  if [ $ST -ne 0 ]; then
    echo "** unable to run '$ADB' "
    return
  fi

  AOUT=`$ADB devices | fgrep $S`
  if [ -z "$AOUT" ]; then
    echo "warning: device $WHICH (serial $S) apparently not connected"
  fi

  # Fix up for emulator (add port number)
  if [ "$WHICH" = "emulator" ]; then
    NW=`echo $AOUT | wc -w`
    if [ "$NW" -ne 2 ]; then
      echo "error: multiple emulator devices connected"
      ecoh "output from adb devices folllows:"
      $ADB devices
      exit 1
    fi
    S=`echo $AOUT | cut -f1 -d" "`
  fi

  echo export ANDROID_SERIAL=$S
  export ANDROID_SERIAL=$S
}

function reset_android_device() {
  local DEVICE=""
  local FC=""
  local SERIAL=""

  DEVICE=$(whichdevice.sh)
  if [ $? != 0 ]; then
    echo "bad return from whichdevice.sh: $DEVICE"
    return
  fi
  SERIAL=`echo $DEVTAGS | tr " " "\n" | egrep "${DEVICE}\:"`
  echo "issuing usb reset to device $TAG serial $SERIAL"
  usb-reset-by-serial.py $SERIAL
}

function dump_device_log() {
  local OPT=$1
  local DEVICE=""
  local FC=""

  DEVICE=$(whichdevice.sh)
  if [ $? != 0 ]; then
    echo "bad return from whichdevice.sh: $DEVICE"
    return
  fi
  if [ -z "$DEVICE" ]; then
    echo "** can't determine active device (whichdevice.sh output empty)"
    return
  fi
  FIRST=`echo $DEVICE | cut -f1 -d" "`
  if [ "$FIRST" != "$DEVICE" ]; then
    echo "** can't determine active device (bad output from whichdevice.sh)"
    return
  fi
  echo "adb logcat -d > /tmp/${DEVICE}log.txt"
  adb logcat -d > /tmp/${DEVICE}log.txt

  if [ "$OPT" = "" ]; then
    startemacsclient "/tmp/${DEVICE}log.txt"
  fi
}

function unpack_and_mount_system_image() {
  echo "Assuming that we have a system.img file here"
  simg2img system.img system.raw.img
  sudo mount -t ext4 -o loop system.raw.img /mnt/android_system
}

function create_android_root_gdbinit_file() {
  if [ -z "$ANDROID_PRODUCT_OUT" ]; then
    echo "unable to create .gdbinit (no setting for ANDROID_PRODUCT_OUT)"
    return
  fi
  if [ ! -d "$ANDROID_PRODUCT_OUT" ]; then
    echo "warning: ANDROID_PRODUCT_OUT setting $ANDROID_PRODUCT_OUT does not exist"
  fi

  croot
  echo "set solib-absolute-prefix $ANDROID_PRODUCT_OUT/symbols" > .gdbinit
  echo "set solib-search-path $ANDROID_PRODUCT_OUT/symbols/system/lib" >> .gdbinit
  echo "dir $ANDROID_BUILD_TOP"
  echo "# arm-linux-androideabi-gdb $ANDROID_PRODUCT_OUT/system/bin/SomeProg" >> .gdbinit
}

function add_change_id_git_hook() {
  echo "curl -Lo `git rev-parse --git-dir`/hooks/commit-msg https://gerrit-review.googlesource.com/tools/hooks/commit-msg ; chmod +x `git rev-parse --git-dir`/hooks/commit-msg"
}

function install_massif_visualizer() {
  echo "Download from http://www.ubuntuupdates.org/package/kubuntu-ppa_backports/trusty/main/base/massif-visualizer"
  echo "install 64-bit package with sudo dpkg -i <file>.deb"
}

function adb_push_to_sys() {
  local sfile=$1
  local which=$2
  local AOUT
  local spath

  AOUT=`adb version`
  ST=$?
  if [ $ST -ne 0 ]; then
    echo "** unable to run '$ADB' "
    return
  fi

  if [ "x$ANDROID_PRODUCT_OUT" = "x" ]; then
    echo "** no setting for ANDROID_PRODUCT_OUT"
    return
  fi

  dpath="/system/${which}/$sfile"
  spath="${ANDROID_PRODUCT_OUT}${dpath}"
  if [ ! -r $spath ]; then
    echo "** error: can't read $spath"
    return
  fi

  adb root
  adb remount
  echo adb push "\$ANDROID_PRODUCT_OUT/system/${which}/$sfile" $dpath
  adb push $spath $dpath
}

function adb_push_to_bin() {
  local binfile=$1
  adb_push_to_sys $binfile "bin"
}

function adb_push_to_lib() {
  local libfile=$1
  adb_push_to_sys $libfile "lib"
}

function adb_push_to_xbin() {
  local xbinfile=$1
  adb_push_to_sys $xbinfile "xbin"
}

function adbpulltotmp() {
  local sfile=$1
  local AOUT
  local ST
  local dpath
  local cmd

  AOUT=`adb version`
  ST=$?
  if [ $ST -ne 0 ]; then
    echo "** unable to run '$ADB' "
    return
  fi

  dpath=`echo $sfile | tr / :`
  dpath="/tmp/$dpath"
  cmd="adb pull $sfile $dpath"
  echo "executing: $cmd"
  $cmd
}

function llvmroot() {
  local HERE=`pwd`
  local CUR=$HERE
  while [ $CUR != "/" ]; do
    if [ -d $CUR/llvm -a -d $CUR/llvm/tools ]; then
      echo $CUR
      return 0
    fi
    CUR=`dirname $CUR`
  done
  echo "Unable to locate llvm root in $HERE" 1>&2
  return 1
}

function llvm-genfiles-flavor() {
  local S="$1"
  local PR="-print${S}"
  local CFINDARGS="$SKIPARGS \
    -name *.inc $PR -o \
    -name *.cc $PR -o \
    -name *.def $PR -o \
    -name *.c $PR -o \
    -name *.cpp $PR -o \
    -name *.h $PR"
  local MFINDARGS="$SKIPARGS \
    -name CMakeLists.txt $PR -o \
    -name *.cmake $PR"
  local LLVMROOT=`llvmroot`
  local DOFILT=filter-out-embedded-spaces.py
  local CLANGLOC="llvm/tools/clang"
  local COMPILERRTLOC="llvm/projects/compiler-rt"
  local TOFIND=llvm
  local BUILDDIR=""
  local SKIPARGS=""

  pushd $LLVMROOT 1> /dev/null
  BUILDDIR=`ls -trad */build.ninja | tail -1 | xargs dirname`

  if [ -d llvm -a -d $BUILDDIR ]; then
    echo "... llvm root is $LLVMROOT"
  else	 
    echo "unable to locate llvm dir / build dir in $LLVMROOT -- no action taken"
    return
  fi

  # Determine monorepo vs old setup
  if [ -d llvm -a -d clang -a -d compiler-rt ]; then
    CLANGLOC="clang"
    COMPILERRTLOC="compiler-rt"
    TOFIND="llvm clang"
    echo "... detected monorepo"
  fi    
  SKIPARGS="-path ${CLANGLOC}/tools/extra/test -prune -o -path ${CLANGLOC}/test -prune -o -path ${COMPILERRTLOC}/test -prune -o -name .svn -prune -o -name .git -prune -o -name mangle-ms-md5.cpp -o -name FormatTest.cpp -prune -o "

  if [ "$S" = "0" ]; then
    DOFILT=cat
  fi

  echo "... running find in $LLVMROOT"
  rm -f cxxfiles${S}.txt mkfiles${S}.txt
  echo "find  ${TOFIND} $BUILDDIR $CFINDARGS | $DOFILT"
  find ${TOFIND} $BUILDDIR $CFINDARGS | $DOFILT > $LLVMROOT/cxxfiles${S}.txt
  find ${TOFIND} $BUILDDIR $MFINDARGS | $DOFILT > $LLVMROOT/mkfiles${S}.txt
  popd 1> /dev/null

  echo "... generated cxxfiles${S}.txt and mkfiles${S}.txt in $LLVMROOT"
}

function llvm-genfiles() {
  local kid1=""
  local kid2=""
  llvm-genfiles-flavor 0 &
  kid1=$!
  llvm-genfiles-flavor &
  kid2=$!
  wait $kid1
  wait $kid2
}

function llvm-gentags() {
  local LLVMROOT=`llvmroot`
  if [ $? != 0 ]; then
    echo "unable to local llvm dir and build dir -- no action taken"
  else
    llvm-genfiles
    pushd $LLVMROOT 1> /dev/null
    rm -f GPATH GTAGS GRTAGS GSYMS
    echo "... running gtags in $LLVMROOT"
    gtags --file cxxfiles.txt
    rm -f cxxfiles0.txt mkfiles0.txt
    popd 1> /dev/null
    echo "... gtags created in $LLVMROOT"
  fi
}

function llvm-mkid() {
  local LLVMROOT=`llvmroot`
  if [ $? != 0 ]; then
    echo "unable to local llvm dir and build dir -- no action taken"
  else
    llvm-genfiles
    pushd $LLVMROOT 1> /dev/null
    rm -f ID
    echo "... running mkid in $LLVMROOT"
    mkid --files0-from cxxfiles0.txt
    #    rm -f cxxfiles0.txt mkfiles0.txt
    echo "... ID file created in $LLVMROOT"
    find llvm -name "*.def" > deffiles.txt
    find llvm -name "*.td" > tdfiles.txt
    find llvm -name "*.ll" > llfiles.txt
    find llvm -name "*.cmake" -print -o -name "CMakeLists.txt" -print > cmakefiles.txt
    popd 1> /dev/null
  fi
}

function gcc-genfiles-single() {
  local S="$1"
  local PR="-print${S}"

  echo "... running find"
  find . -name .svn -prune -o -name .git -prune -o \
    -name out -prune -o \
    -name testsuite -prune -o \
    -name testdata -prune -o \
    -name "*.S" ${PR} -o \
    -name "*.md" ${PR} -o \
    -name "*.opt" ${PR} -o \
    -name "*.cc" ${PR} -o \
    -name "*.c" ${PR} -o \
    -name "*.cpp" ${PR} -o \
    -name "*.hpp" ${PR} -o \
    -name "*.h" ${PR} > cxxfiles${S}.txt
  echo "... generated cxxfiles${S}.txt"
}

function gcc-gentags() {
  gcc-genfiles-single
  rm -f GPATH GTAGS GRTAGS GSYMS
  cat cxxfiles.txt | gtags --file -
}

function gccgo-genfiles() {
  local S="$1"
  local PR="-print${S}"

  # Must be run from root
  if [ ! -d ./gofrontend ]; then
     echo "unable to locate gofrontend, can't continue."
     return
  fi
  if [ ! -d ./gcc-trunk/gcc ]; then
     echo "unable to locate ./gcc-trunk/gcc, can't continue."
     return
  fi

  # Gen file lists in gofrontend
  cd gofrontend
  find . -name .git -prune -o -type f -print > allfiles.txt
  find . -name "*.go" -print > gofiles.txt
  cd ..

  # Everything in gcc, libcpp, and gofrontend
  find ./gcc-trunk/gcc \
    -name testsuite -prune -o \
    -name "*.S" ${PR} -o \
    -name "*.md" ${PR} -o \
    -name "*.opt" ${PR} -o \
    -name "*.cc" ${PR} -o \
    -name "*.c" ${PR} -o \
    -name "*.cpp" ${PR} -o \
    -name "*.h" ${PR} > cxxfiles${S}.txt
  find ./gofrontend \
    -name "*.cc" ${PR} -o \
    -name "*.c" ${PR} -o \
    -name "*.cpp" ${PR} -o \
    -name "*.h" ${PR} >> cxxfiles${S}.txt
  find ./gcc-trunk/libcpp \
    -name "*.cc" ${PR} -o \
    -name "*.c" ${PR} -o \
    -name "*.cpp" ${PR} -o \
    -name "*.h" ${PR} >> cxxfiles${S}.txt
  find ./gcc-trunk/libbacktrace \
    -name "*.c" ${PR} -o \
    -name "*.h" ${PR} >> cxxfiles${S}.txt
  find ./gcc-trunk/libgcc \
    -name "*.c" ${PR} -o \
    -name "*.inc" ${PR} -o \
    -name "*.h" ${PR} >> cxxfiles${S}.txt
  find ./gcc-trunk/libffi \
    -name "*.c" ${PR} -o \
    -name "*.inc" ${PR} -o \
    -name "*.h" ${PR} >> cxxfiles${S}.txt
  find ./gcc-trunk/include \
    -name "*.h" ${PR} >> cxxfiles${S}.txt
}

function gccgo-mkid() {
  local kid1=""
  local kid2=""

  # Must be run from root
  if [ ! -d ./gofrontend ]; then
     echo "unable to locate gofrontend, can't continue."
     return
  fi
  if [ ! -d ./gcc-trunk/gcc ]; then
     echo "unable to locate ./gcc-trunk/gcc, can't continue."
     return
  fi

  echo "... generated cxxfiles"
  gccgo-genfiles 0 &
  kid1=$!
  gccgo-genfiles &
  kid2=$!
  wait $kid1
  wait $kid2

  echo "... running mkid"
  mkid --files0-from cxxfiles0.txt
  echo "... removing cxxfiles0.txt"
  rm -f cxxfiles0.txt mkfiles0.txt
}

function gcc-mkid() {
  gcc-genfiles-single 0
  gcc-genfiles-single 
  mkid --files0-from cxxfiles0.txt
  rm -f cxxfiles0.txt
}

function gitbasebranch() {
  git rev-parse --symbolic-full-name --abbrev-ref @{u} 
}

function mygitlogfile() {
  local WHATFILE=$1
  local DN
  local BN

  if [ -z $WHATFILE ]; then
    echo "** supply name of file to diff as single arg"
    return
  fi
  DN=`dirname $WHATFILE`
  BN=`basename $WHATFILE`
  (cd $DN; git log --name-only $BN)
}

function run_prebuilts_arm64_emulator() {
  local HERE=`pwd`
  local EMPID

  if [ -z "$ANDROID_BUILD_TOP" ]; then
    echo "error: ANDROID_BUILD_TOP not set."
    return
  fi
  if [ "$HERE" != "$ANDROID_BUILD_TOP" ]; then
    echo "error: must be run from \$ANDROID_BUILD_TOP ($ANDROID_BUILD_TOP)"
    return
  fi
  cd prebuilts/android-emulator/linux-x86_64 &&  \
    emulator-ranchu-arm64 \
      -verbose \
      -show-kernel 1> $HERE/emu-err.txt 2>&1   &
  EMPID=$!
  disown $EMPID
  echo PID is $EMPID
  echo Output is in: $HERE/emu-err.txt
}

function run_zgrviewer() {
  local FILE=$1
  local LOC=`pwd`
  local FP

  if [ -z "$FILE" ]; then
    echo "** supply single arg: name of *.dot file"
    return
  fi
  case "$FILE" in
    /*) FP=$FILE ;;
    *) FP=$LOC/$FILE ;;
  esac
  ( cd $HOME/zgrviewer/zgrviewer-0.10.0 && ./run.sh -P dot -f $FP )
}

function run_git_meld_hash() {
  local HASH1=$1
  local HASH2=$2
  local extr=""
  local shift1=1
  local shift2=1

  # If no args at all, use HEAD as hash
  if [ -z "$HASH1" ]; then
    echo "No hash argument provided, using HEAD"
    shift1=0
    HASH1=HEAD
  fi

  # Is first argument a file? If so, then use implicit HEAD
  if [ -r $HASH1 ]; then
    echo "No hash argument provided, using HEAD"
    shift1=0
    HASH1=HEAD
  fi

  # Check first hash
  git log -1 --oneline $HASH1 1> /dev/null 2>&1
  if [ $? != 0 ]; then
    echo "Unknown/inscrutable hash $HASH1, can't proceed"
    return
  fi
  shift $shift1

  # Do we have a second arg?
  if [ -z "$HASH2" ]; then
    shift2=0
    HASH2="${HASH1}^"
    echo "No second argument provided, using $HASH2"
  fi

  # Is second argument a file and not a hash?
  if [ -r $HASH2 ]; then
    # Second arg is not a hash
    shift2=0
    HASH2="${HASH1}^"
  else
    # Second arg is not a file, so it must be a hash
    git log -1 --oneline $HASH2 1> /dev/null 2>&1
    if [ $? != 0 ]; then
      echo "Unknown/inscrutable second hash $HASH2, can't proceed"
      return
    fi
  fi
  shift $shift2

  # Remaining args
  extr="$*"
  if [ ! -z "$extr" ]; then
    extr="-- $extr"
  fi

  if [ -z "$GRDIFF" ]; then
    echo "error: please set GRDIFF to graphical diff tool."
    return
  fi

  echo git difftool -y -d -t ${GRDIFF} $HASH1 $HASH2 $extr
  git difftool -y -d -t ${GRDIFF} $HASH1 $HASH2 $extr
}

function run_git_meld_branch() {
  local FILES=$*
  local WORKB=`git branch | fgrep '*' | cut -f2 -d" "`
  local EXTRA=""

  # Determine work branch
  if [ -z "$WORKB" ]; then
    echo "unable to determine work branch, output of 'git branch' is:"
    git branch
    return
  fi
  if [ "$WORKB" = "master" ]; then
    echo "current branch is master, please check out work branch"
    return
  fi

  if [ ! -z "$FILES" ]; then
     EXTRA="-- $FILES"
  fi

  if [ -z "$GRDIFF" ]; then
    echo "error: please set GRDIFF to graphical diff tool."
    return
  fi

  echo git difftool -y -d -t ${GRDIFF} master $WORKB $EXTRA
  git difftool -y -d -t ${GRDIFF} master $WORKB $EXTRA
}

function run_git_show_local_branch_status() {
  local WORKB=`git branch | fgrep '*' | cut -f2 -d" "`

  # Determine work branch
  if [ -z "$WORKB" ]; then
    echo "unable to determine work branch, output of 'git branch' is:"
    git branch
    return
  fi
  if [ "$WORKB" = "master" ]; then
    echo "current branch is master, please check out work branch"
    return
  fi

  echo git diff --name-status master  $WORKB
  git diff --name-status master  $WORKB
}

function set_git_upstream_tracking_branch() {
  local UPSTREAMBR="$1"
  local WORKB=`git branch | fgrep '*' | cut -f2 -d" "`
  local PARENTBR=`git rev-parse --symbolic-full-name --abbrev-ref @{u} 2>/dev/null`

  if [ -z "$UPSTREAMBR" ]; then
    echo "set_git_upstream_tracking_branch: invoked without arg, bailing"
    return
  fi
  UPSTREAMBR="origin/$UPSTREAMBR"

  # Determine work branch
  if [ -z "$WORKB" ]; then
    echo "unable to determine work branch, output of 'git branch' is:"
    git branch
    return
  fi

  # echo "=-= UPSTREAMBR $UPSTREAMBR"
  # echo "=-= WORKB $WORKB"
  # echo "=-= PARENTBR $PARENTBR"

  # Are we already set up?
  if [ "$UPSTREAMBR" = "$PARENTBR" ]; then
    echo "tracking branch already set to $PARENTBR, no work needed"
    return
  fi

  # Don't allow setting of tracking branch for master, etc.
  if [ "$WORKB" = "master" -o "$WORKB" = "$UPSTREAMBR" ]; then
    echo "current branch is $WORKB, can't set tracking"
    return
  fi

  if [ ! -z "$PARENTBR" ]; then
    echo "previous tracking branch was: $PARENTBR"
    echo "new tracking branch is: $UPSTREAMBR"
  fi	 

  echo git branch --set-upstream-to=$UPSTREAMBR
  git branch --set-upstream-to=$UPSTREAMBR
}

function set_git_upstream_tracking_branch_to_master() {
  set_git_upstream_tracking_branch master
}

function prependToPathIfNotAlreadyPresent () {
  local D="$1"
  case ":$PATH:" in
    *":${D}:"*) echo "dir $D already in PATH" ;;
    *) echo "dir $D prepended to PATH" ; export PATH="${D}:${PATH}" ;;
  esac
}

function appendToPathIfNotAlreadyPresent () {
  local D=$1
  case ":$PATH:" in
    *":$D:"*) echo "dir $D already in PATH" ;;
    *) echo "dir $D appended to PATH" ; export PATH="${PATH}:${D}" ;;
  esac
}

function silentAppendToPathIfNotAlreadyPresent () {
  local D=$1
  case ":$PATH:" in
    *":$D:"*) /bin/true ;;
    *) export PATH="${PATH}:${D}" ;;
  esac
}

function removeFromPathIfPresent() {
  local d="$1"
  local p=""
  local pd=""
  local sep=""
  local newpath=""

  if [ -z "$d" ]; then
    echo "error: supply an arg to removeFromPathIfPresent"
    return
  fi

  pd=`echo $PATH | tr ':' ' '`
  for p in $pd
  do
     if [ "${p}" != "$d" ]; then
       newpath="${newpath}${sep}${p}"
       sep=":"
     else
       echo "$d removed from PATH"
     fi
  done

  export PATH="$newpath"
}

function removeFromLdLibraryPathIfPresent() {
  local d="$1"
  local p=""
  local pd=""
  local sep=""
  local newpath=""

  if [ -z "$d" ]; then
    echo "error: supply an arg to removeFromLdLibraryPathIfPresent"
    return
  fi

  pd=`echo $LD_LIBRARY_PATH | tr ':' ' '`
  for p in $pd
  do
     if [ "${p}" != "$d" ]; then
       newpath="${newpath}${sep}${p}"
       sep=":"
     else
       echo "$d removed from LD_LIBRARY_PATH"
     fi
  done

  export LD_LIBRARY_PATH="$newpath"
}

function addllvmbintopath() {
  local BD=`pwd`/bin
  local LD=../llvm

  if [ ! -d ../llvm ]; then
     echo "unable to locate ../llvm dir, can't continue."
     return
  fi
  if [ ! -d $BD ]; then
     echo "unable to locate LLVM bin dir $BD, can't continue."
     return
  fi
  if [ ! -x $BD/opt ]; then
     echo "no executable 'opt' in bin dir $BD, can't continue."
     return
  fi
  echo "Starting subshell with $P added to PATH..."
  PATH=$BD:$PATH bash
}

function prependToLdLibraryPathIfNotAlreadyPresent () {
  local D="$1"
  local col=":"
  if [ -z "$LD_LIBRARY_PATH" ]; then
    col=""
  fi
  case ":$LD_LIBRARY_PATH:" in
    *":${D}:"*) echo "dir $D already in LD_LIBRARY_PATH" ;;
    *) echo "dir $D prepended to LD_LIBRARY_PATH" ; export LD_LIBRARY_PATH="${D}${col}${LD_LIBRARY_PATH}" ;;
  esac
}

function appendToLdLibraryPathIfNotAlreadyPresent () {
  local D=$1
  local col=":"
  if [ -z "$LD_LIBRARY_PATH" ]; then
    col=""
  fi
  case ":$LD_LIBRARY_PATH:" in
    *":$D:"*) echo "dir $D already in LD_LIBRARY_PATH" ;;
    *) echo "dir $D appended to LD_LIBRARY_PATH" ; export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}${col}${D}" ;;
  esac
}

function show_dpkg_contents {
  local PKG=$1

  if [ -z "$PKG" ]; then
    echo "supply package name as arg"
    return
  fi

  echo dpkg-query -L $PKG
  dpkg-query -L $PKG
}

function svnaddexec() {
  local FILES="$*"
  for F in $FILES
  do
    echo svn propset svn:executable on $F
    echo chmod 0755 $F
    svn propset svn:executable on $F
    chmod 0755 $F
  done
}

function gotoolcompile() {
  local ARGS="$*"
  local goarch=`go env | fgrep GOARCH | cut -f2 -d\"`
  local goos=`go env | fgrep GOOS | cut -f2 -d\"`

  # For some reason "go tool compile" is not smart enough
  # to add -I $GOPATH/$GOOS_$GOOARCH to the command line
  # automatically... here we do so by hand.
  echo go tool compile -I $GOPATH/pkg/${goos}_${goarch} $ARGS
  go tool compile -I $GOPATH/pkg/${goos}_${goarch} $ARGS
}

function warngodirs() {
  local d="$1"
  local x=""
  local xdirs="bin pkg src"

  if [ -z "$d" ]; then
    d=.
  fi

  for x in $xdirs
  do
    if [ ! -d "$d/$x" ]; then
      echo "warning: $d/$x does not exist"
    fi
  done
}

function makegodirs() {
  echo "mkdir -p bin pkg src"
  mkdir -p bin pkg src
}

function setgccgoroot() {
  local d=$1
  local which=$2

  if [ ! -z "$MYGCCGOROOT" ]; then
    echo "error: MYGCCGOROOT already set to $MYGCCGOROOT"
    return
  fi

  if [ -z "$d" ]; then
    echo "error: supply go root dir as arg"
    return
  fi

  if [ ! -d "$d" ]; then
    echo "error: arg $d is not a dir"
    return
  fi

  if [ ! -x "$d/bin/gccgo" ]; then
    echo "error: no executable gccgo in in $d/bin"
    return
  fi

  echo "MYGCCGOROOT set to $d"
  export MYGCCGOROOT=$d
  if [ -z "$which" -o "$which" = "secondary" ]; then
    appendToPathIfNotAlreadyPresent $MYGCCGOROOT/bin
    which=appended
  elif [ "$which" = "prepend" ]; then
    prependToPathIfNotAlreadyPresent $MYGCCGOROOT/bin
    which=prepended
  else
    unset MYGCCGOROOT
    echo "error: which tag is $which, can't understand that"
    return
  fi

  echo "$MYGCCGOROOT/bin $which to path"
  prependToLdLibraryPathIfNotAlreadyPresent "$MYGCCGOROOT/lib64"
}

function unsetgccgoroot() {

  if [ -z $MYGCCGOROOT ]; then
    echo "error: MYGCCGOROOT not set"
    return
  fi

  # Extract MYGCCGOROOT/bin from PATH
  removeFromPathIfPresent "$MYGCCGOROOT/bin"

  # Extract from LD_LIBRARY_PATH
  removeFromLdLibraryPathIfPresent "$MYGCCGOROOT/lib64"

  echo "Unsetting MYGCCGOROOT"
  unset MYGCCGOROOT
}

function setgoroot() {
  local d=$1

  if [ ! -z "$MYGOROOT" ]; then
    echo "error: MYGOROOT already set to $MYGOROOT"
    return
  fi

  if [ -z "$d" ]; then
    echo "error: supply go root dir as arg"
    return
  fi

  if [ ! -d "$d" ]; then
    echo "error: arg $d is not a dir"
    return
  fi

  if [ -x "$d/bin/gccgo" ]; then
    echo "setting LD_LIBRARY_PATH to $d/lib64"
    export LD_LIBRARY_PATH="$d/lib64"
  else
    warngodirs $d
  fi

  setgobootstrapifneeded

  echo "MYGOROOT set to $d"
  export MYGOROOT=$d
  prependToPathIfNotAlreadyPresent $MYGOROOT/bin
  echo "$MYGOROOT/bin prepended to path"
}

function unsetgoroot() {

  if [ -z $MYGOROOT ]; then
    echo "error: MYGOROOT not set"
    return
  fi

  # Extract MYGOROOT/bin from PATH
  removeFromPathIfPresent "$MYGOROOT/bin"

  if [ -x "$MYGOROOT/bin/gccgo" ]; then
    echo "Unsetting LD_LIBRARY_PATH"
    unset LD_LIBRARY_PATH
  fi

  echo "Unsetting MYGOROOT"
  unset MYGOROOT
  echo "Unsetting GOROOT_BOOTSTRAP"
  unset GOROOT_BOOTSTRAP

}

function setgobootstrapifneeded() {
  local d="$1"

  if [ ! -z "$GOROOT_BOOTSTRAP" ]; then
    return
  fi

  if [ -z "$d" ]; then
    # Infer bootstrap based on current go
    d=`which go`
    if [ -z "$d" ]; then
      echo "error: no 'go' in PATH, can't infer GOROOT_BOOTSTRAP"
      return
    fi
    d=`dirname $d`
    d=`dirname $d`
  fi

  if [ ! -x "$d/bin/go" ]; then
    echo "error: can't find bin/go in $d, unable to update GOROOT_BOOTSTRAP"
    return
  fi
  export GOROOT_BOOTSTRAP=$d
  echo "GOROOT_BOOTSTRAP set to $d"
}

function setgopath() {
  local d="$1"

  if [ ! -z "$GOPATH" ]; then
    echo "error: GOPATH already set to $GOPATH"
    return
  fi

  if [ -z "$d" ]; then
    echo "error: supply go path dir as arg"
    return
  fi

  if [ ! -d "$d" ]; then
    echo "error: arg $d is not a dir"
    return
  fi

  if [ "$d" = "." ]; then
    d=`pwd`
  fi

  warngodirs $d

  echo "GOPATH set to $d"
  export GOPATH=$d

  appendToPathIfNotAlreadyPresent $GOPATH/bin
}

function unsetgopath() {

  if [ -z $GOPATH ]; then
    echo "error: GOPATH not set"
    return
  fi

  # Extract GOPATH/bin from PATH
  removeFromPathIfPresent "$GOPATH/bin"

  echo "Unsetting GOPATH"
  unset GOPATH
}

function select_ssd_go_repo() {
  local which=$1
  local gopath=""

  if [ -z $which ]; then
    echo "error: supply an argument"
    return
  fi

  if [ -d /ssd/go${which} ]; then
    gopath=/ssd/go${which}
  elif [ -d /ssd2/go${which} ]; then
    gopath=/ssd2/go${which}
  else
    echo "error: unable to locate /ssd*/go${which}"
    return
  fi

  setgopath $gopath
  setgoroot /ssd2/go
  setgccgoroot /ssd/gcc-trunk/cross
}

function run_ddir_sync() {
  local PAIR=$1
  local DRYRUN=$2
  local SRC=""
  local DST=""
  local opt=""
  if [ "x$DRYRUN" = "xdryrun" ]; then
    opt="-n"
  fi

  pushd /d
  if [ $? != 0 ]; then
    echo "unable to cd to /d"
    return
  fi
  for P in $PAIR
  do
    SRC=`echo $P | cut -f1 -d:`
    DST=`echo $P | cut -f2 -d:`
    if [ ! -d $SRC ]; then
      echo "unable to locate src $SRC, skipping"
      continue
    fi
    if [ ! -d $DST ]; then
      echo "unable to locate dst $DST, skipping"
      continue
    fi
    echo rsync $opt -av ${SRC}/ ${DST}/
    rsync $opt -av ${SRC}/ ${DST}/
  done
  popd
}

function run_photovideo_rsync() {
  local DRYRUN="$1"
  local PAIRS=$PHOTOVIDEO_PAIRS

  pushd /d
  if [ $? != 0 ]; then
    echo "unable to cd to /d"
    return
  fi
  for P in $PAIRS
  do
    run_ddir_sync $P $DRYRUN
  done
  popd
}

function run_mp_rsync() {
  local DRYRUN="$1"
  local PAIRS=$MP_PAIRS

  pushd /d
  if [ $? != 0 ]; then
    echo "unable to cd to /d"
    return
  fi
  for P in $PAIRS
  do
    run_ddir_sync $P $DRYRUN
  done
  popd
}

function run_clang_format_gnustyle() {
  local CPPFILE="$1"
  local INDFILE="${CPPFILE}.ind"

  if [ -z "$CPPFILE" ]; then
    echo "** supply single C++ filename as argument"
    return
  fi
  touch $INDFILE
  if [ $? != 0 ]; then
    echo "** untable to write $INDFILE"
    return
  fi

  clang-format -style="{BasedOnStyle: Google, BreakBeforeBraces: GNU, AlwaysBreakAfterReturnType: All, AllowShortBlocksOnASingleLine: false, UseTab: ForIndentation}" < $CPPFILE > $INDFILE
  echo "indented version of $CPPFILE written to $INDFILE"
}

function cdgoroot() {
  local GR=`go env GOROOT`
  echo pushd $GR
  pushd $GR
}

function cdgopath() {
  local GP=`go env GOPATH`
  echo pushd $GP
  pushd $GP
}

function gccgobinutilsconfig() {
  local CMD=""
  local HERE=""
  local ROOT=""

  if [ ! -d ../binutils ]; then
    echo "** error: no ../binutils dir"
    return
  fi

  HERE=`pwd`
  cd ..
  ROOT=`pwd`
  cd $HERE

  mkdir -p $ROOT/binutils-cross
  CMD="../binutils/configure --prefix=$ROOT/binutils-cross --disable-multilib --enable-gold --enable-plugins"

  echo running $CMD
  $CMD
}

function gccgotrunkconfig() {
  local ARGS="$*"
  local ARG=""
  local ARGOPT=""
  local BS="--disable-bootstrap"
  local CMD=""
  local HERE=""
  local ROOT=""
  local PREFBASE=cross
  local TF=$(mktemp)
  local X=
  local Y=

  if [ ! -d ../gofrontend ]; then
    echo "** error: no ../gofrontend dir"
    return
  fi
  if [ ! -d ../gcc-trunk ]; then
    echo "** error: no ../gcc-trunk dir"
    return
  fi

  HERE=`pwd`
  cd ..
  ROOT=`pwd`
  cd $HERE

  echo "#!/bin/sh" > $TF
  echo "set -x" >> $TF
  echo "../gcc-trunk/configure \\" >> $TF
  echo "  --enable-languages=c,c++,go \\" >> $TF
  echo "  --enable-libgo \\" >> $TF
  echo "  --with-ld=$ROOT/binutils-cross/bin/ld.gold \\" >> $TF

  if [ ! -z "$ARGS" ]; then
    for ARG in $ARGS
    do
      X=$(echo $ARG | tr '=' 'x')
      if [ "$X" != "$ARG" ]; then
         ARGOPT=$(echo $ARG | cut -f2 -d=)
         ARG=$(echo $ARG | cut -f1 -d=)
      fi
      echo ARG is $ARG
      if [ "z${ARG}" = "zbootstrap" ]; then
        BS=""
      elif [ "z${ARG}" = "zprefix" ]; then
        PREFBASE=$ARGOPT
      elif [ "z${ARG}" = "zdebug" ]; then
        echo '   CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" CFLAGS_FOR_BUILD="-O0 -g" CXXFLAGS_FOR_BUILD="-O0 -g" \' >> $TF
      elif [ "z${ARG}" = "zcxx98" ]; then
        echo '   CXXFLAGS="-std=c++98" CXXFLAGS_FOR_BUILD="-std=c++98" \' >> $TF
      else
        echo "*** error -- unknown option/argument $ARG"
        return
      fi
    done
  fi

  echo "  --prefix=$ROOT/$PREFBASE \\" >> $TF
  echo "  $BS" >> $TF

  echo "script is:"
  cat $TF
  sh $TF
  rm $TF
}

function gccgotrunkconfigdebug() {
  gccgotrunkconfig debug
}

function gccgo_build() {
  local NP=`nproc`
  if [ $NP -gt 20 ]; then
    NP=20
  fi
  echo "make -j${NP} all 1> berr.txt 2>&1"
  make -j${NP} all 1> berr.txt 2>&1
  if [ $? != 0 ]; then
    echo "** build failed"
    startemacs berr.txt
    return
  fi
  echo "result: PASS"
}

function gccgo_build_and_test() {
  local NP=`nproc`
  if [ $NP -gt 20 ]; then
    NP=20
  fi
  echo "make -j${NP} all 1> berr.txt 2>&1"
  make -j${NP} all 1> berr.txt 2>&1
  if [ $? != 0 ]; then
    echo "** build failed, skipping tests"
    startemacs berr.txt
    return
  fi
  echo "make -j${NP} check-go 1> terr.txt 2>&1"
  make -j${NP} check-go 1> terr.txt 2>&1
  if [ $? != 0 ]; then
    echo "****************"
    echo "****************"
    echo "** TEST FAILED "
    echo "****************"
    echo "****************"
    startemacs berr.txt terr.txt
    return
  fi
  echo "result: PASS"
  startemacs berr.txt terr.txt
}

function gccgo_build_and_install() {
  local NP=`nproc`
  echo "make -j${NP} all 1> berr.txt 2>&1"
  make -j${NP} all 1> berr.txt 2>&1
  if [ $? != 0 ]; then
    echo "** build failed, skipping tests"
    startemacs berr.txt
    return
  fi
  echo "make -j${NP} install 1> ierr.txt 2>&1"
  make -j${NP} install 1> ierr.txt 2>&1
  if [ $? != 0 ]; then
    echo "** install FAILED "
    startemacs berr.txt ierr.txt
    return
  fi
  echo "result: PASS"
  startemacs berr.txt ierr.txt
}

function binutilstrunkconfig() {
  local ARGS="$*"
  local ARG=""
  local ARGOPT=""
  local CMD=""
  local HERE=""
  local ROOT=""
  local PREFBASE=binutils-cross
  local TF=$(mktemp)
  local X=
  local Y=

  if [ ! -d ../binutils ]; then
    echo "** error: no ../binutils dir"
    return
  fi

  HERE=`pwd`
  cd ..
  ROOT=`pwd`
  cd $HERE

  echo "#!/bin/sh" > $TF
  echo "set -x" >> $TF
  echo "../binutils/configure \\" >> $TF
  echo "  --enable-gold=default \\" >> $TF
  echo "  --enable-plugins  \\" >> $TF

  if [ ! -z "$ARGS" ]; then
    for ARG in $ARGS
    do
      X=$(echo $ARG | tr '=' 'x')
      if [ "$X" != "$ARG" ]; then
         ARGOPT=$(echo $ARG | cut -f2 -d=)
         ARG=$(echo $ARG | cut -f1 -d=)
      fi
      echo ARG is $ARG
      if [ "z${ARG}" = "zprefix" ]; then
        PREFBASE=$ARGOPT
      elif [ "z${ARG}" = "zdebug" ]; then
        echo '   CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" CFLAGS_FOR_BUILD="-O0 -g" CXXFLAGS_FOR_BUILD="-O0 -g" \' >> $TF
      else
        echo "*** error -- unknown option/argument $ARG"
        return
      fi
    done
  fi

  echo "  --prefix=$ROOT/$PREFBASE \\" >> $TF
  echo "  $BS" >> $TF

  echo "script is:"
  cat $TF

  sh $TF
  rm $TF
}

function setup_gofrontend_fakegoroot() {
  local WORKROOT=$1
  local HASH=`git log --oneline --no-abbrev-commit -1 | cut -f1 -d" "`
  local FGR="/tmp/fakegoroot/$HASH"
  mkdir -p $FGR
  rm -rf $FGR/*
  mkdir  $FGR/bin $FGR/pkg
  ln -s $WORKROOT/libgo/go $FGR/src 
  export GOROOT=$FGR
  echo "... GOROOT set to $FGR"
}

function emacswithgoroot() {
  local DOBRANCH="$1"
  local WHICH=""
  local BN=""
  local RFILES=""
  local FILES=""
  local REMOTE=""
  local WORKROOT=""
  local RBRANCH=""

  shift
  WHICH="$*"
  
  # In git?
  git status -sb 1> /dev/null 2>&1
  if [ $? != 0 ]; then
    echo "** not in git repo, can't proceed"
    return
  fi

  WORKROOT=`git rev-parse --show-toplevel`
  echo work root is $WORKROOT

  if [ "$DOBRANCH" = "BRANCH" ]; then

    # Determine branch name
    BN=`git symbolic-ref --short HEAD`
    echo branch is $BN

    # Is this an offical branch (ex: master, or dev.link)? If so
    # then it will appear in 'git branch -r' output.
    RBRANCH=`git branch -r | fgrep "origin/$BN"`
  
    # Determine files that have changed since the branch
    # forked off from parent branch.
    if [ "$BN" != "" ]; then
      if [ "$RBRANCH" == "" ]; then
        # Determine parent
	PARENTBRANCH=`git rev-parse --symbolic-full-name --abbrev-ref @{u} 2>/dev/null`
	if [ -z "$PARENTBRANCH" ]; then
	  PARENTBRANCH=master
        else
	  PARENTBRANCH=`echo $PARENTBRANCH | cut -f2- -d/`
        fi
        FORKPOINT=`git merge-base $BN $PARENTBRANCH`
        RFILES=`git diff --name-only $FORKPOINT $BN`
        for RF in $RFILES
        do
          FILES="$FILES ${WORKROOT}/${RF}"
        done
      fi
    fi
  fi
  FILES="$FILES $WHICH"

  # Which repo?
  REMOTE=`git remote -v | head -1 | expand | tr -s " " | cut -f2 -d" "`
  #echo remote is $REMOTE

  if [ "$REMOTE" = "https://go.googlesource.com/go" ]; then
    export GOROOT=$WORKROOT
    echo GOROOT=$WORKROOT
  fi

  if [ "$REMOTE" = "https://go.googlesource.com/gofrontend" ]; then
    setup_gofrontend_fakegoroot $WORKROOT
  fi

  startemacs $FILES

  if [ "$REMOTE" = "https://go.googlesource.com/go" -o "$REMOTE" = "https://go.googlesource.com/gofrontend" ]; then
    unset GOROOT
  fi
}

function emacsbranched() {
  local WHICH="$*"
  emacswithgoroot BRANCH $WHICH
}

function emacsgoroot() {
  local WHICH="$*"
  emacswithgoroot NOBRANCH $WHICH
}

function emacshash() {
  local HASH="$1"
  local BN=""
  local FILES=""
  local REMOTE=""
  local WORKROOT=""
  local SETGOROOT=false

  # In git?
  git status -sb 1> /dev/null 2>&1
  if [ $? != 0 ]; then
    echo "** not in git repo, can't proceed"
    return
  fi

  # Determine files for this hash
  FILES=`git diff --name-only ${HASH}^ ${HASH}`

  # Which repo?
  REMOTE=`git remote -v | head -1 | expand | tr -s " " | cut -f2 -d" "`
  #echo remote is $REMOTE

  WORKROOT=`git rev-parse --show-toplevel`

  if [ "$REMOTE" = "https://go.googlesource.com/go" ]; then
    SETGOROOT=true
  fi

  pushd $WORKROOT
  if [ $SETGOROOT = "true" ]; then
    GOROOT=`pwd` startemacs $FILES
  fi
  popd
}

function emacsmod() {
  local FILES=""

  # In git?
  git status -sb 1> /dev/null 2>&1
  if [ $? != 0 ]; then
    echo "** not in git repo, can't proceed"
    return
  fi

  # Collect modified files
  FILES=`git status -s --untracked-files=no | cut -f3 -d" "`
  if [ -z "$FILES" ]; then
    echo "** can't find any modifed files, unable to proceed"
    return
  fi

  startemacs $FILES
}

function runalldotbash() {
  local SCRIPT="$1"
  local GR=""
  local HERE=`pwd`
  local FILE=""
  local HASH=""
  local WORKB=`git branch | fgrep '*' | cut -f2 -d" "`

  GR=`go env GOROOT`
  if [ $? != 0 ]; then
    echo "** go env GOROOT failed"
    return
  fi

  # Go root set?
  if [ -z "$MYGOROOT" ]; then
    echo "warning, MYGOROOT not set"
  fi

  # In git?
  git status -sb 1> /dev/null 2>&1
  if [ $? != 0 ]; then
    echo "** not in git repo, can't proceed"
    return
  fi
  HASH=`git rev-parse --short HEAD`

  # Check spot
  if [ "$HERE" != "${GR}/src" ]; then
    echo "** not in \${GOROOT}/src, can't run"
    return
  fi

  # Select all.bash or race.bash
  if [ "x$SCRIPT" = "xrace" ]; then
    SCRIPT=race.bash
  else
    SCRIPT=all.bash
  fi
    
  # Check script
  if [ ! -x ./$SCRIPT ]; then
    echo "** no executable ./$SCRIPT"
    return
  fi

  # Decide where to put the results
  FILE=`echo $GR | tr / _`
  FILE=${SSDTMP}/tmp/${SCRIPT}.${FILE}.${WORKB}.${HASH}.txt

  # Echo, then run
  echo "bash $SCRIPT &> $FILE"
  ST=`seconds.py`
  bash $SCRIPT 1> $FILE 2>&1
  RC=$?
  EN=`seconds.py`
  EL=`expr $EN - $ST`

  echo "... complete in $EL seconds, return code: $RC"
  startemacs $FILE
}

function ge_no_aslr() {
  local ARGS="$*"
  setarch `uname -m` -R emacs $ARGS &
  disown $!
}

function git_track_remote_branch() {
  local B=$1
  if [ -z "$B" ]; then
    echo "error: supply branch name as arg"
    return
  fi	
  local RB=`git branch --list -r origin/$B | tr -d " "`
  echo RB is "=${RB}="
  if [ "$RB" != "origin/$B" ]; then
    echo "warning: can't find remote branch origin/$B, bailing"
    return
  fi
  echo git branch --track $B $RB
  git branch --track $B $RB
}


#......................................................................

alias hh='history 25'
alias e=startemacsclient
alias ge=startemacs
alias emgr=emacsgoroot
alias embr=emacsbranched
if [ "x${OSFLAVOR}" = "xDarwin" ]; then
  alias psaxu='ps -ef'
  alias psaxuw='ps -efww'
else
  alias psaxu='ps -ejH'
  alias psaxuw='ps -efwwjH'
fi
alias svnstat='svn status | egrep -v "^\?"'
alias svnaddexec='svn propset svn:executable on'
alias more=less
alias show_dir_tree='k4dirstat'
alias debuglinedump='readelf --debug-dump=decodedline '
alias anyprog=anyprogbash
alias simple_prompt="export PS1='% '"
# image viewer
alias show_image=eog
alias markdown_viewer=retext
alias show_pdf=evince
alias copy_file_with_progress_bar=gcp
alias gcc_show_errno='gcc -E -xc - < /usr/include/errno.h  | cut -f2 -d\" | fgrep / | sort | uniq | xargs cat | egrep "define\s+E"'

# Android
alias srcbuildsetup='. build/envsetup.sh'
alias selflunch='. build/envsetup.sh ; echo lunch `basename $PWD` ; lunch `basename $PWD`'
alias armobjdump64=prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/aarch64-linux-android/bin/objdump
alias armobjdump=prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/arm-linux-androideabi/bin/objdump
alias armobjcopy=prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/arm-linux-androideabi/bin/objcopy
alias armobjcopy64=prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/aarch64-linux-android/bin/objcopy
alias mips64objdump=prebuilts/gcc/linux-x86/mips/mips64el-linux-android-4.9/bin/mips64el-linux-android-objdump
alias aodsyms='armobjdump -w -t -h'

# Devices
alias pickdevice=select_android_device
alias resetdevice=reset_android_device
alias whichdevice=whichdevice.sh

# Logs
alias dumpdevlog=dump_device_log

# Emulator in prebuilts
alias run_arm64_emulator=run_prebuilts_arm64_emulator

# Linux / Debian
alias linuxpackagesearch='apt-cache search'
alias displaylinuxpackageversion='apt-cache policy'
alias showlinuxpackagecontents=show_dpkg_contents
alias showinstalledpackages="apt list --installed"
alias xtsmall='xterm -sb -fn 7x13 -sl 5000'
alias xtmed='xterm -sb -fn 9x15 -sl 5000'
alias xtbig='xterm -sb -fn 10x20 -sl 5000'
alias bash_no_aslr='setarch `uname -m` -R bash'
alias screendumparea='gnome-screenshot -a'

# BTRFS
alias show_fs_type='stat -f --printf="%T\n" .'
alias bflist='sudo btrfs subvolume list /ssd ; sudo btrfs subvolume list /ssd2'
alias bfmkvol=create_btrfs_subvolume
alias bfmksnap=create_btrfs_snapshot
alias bfrmsnap=remove_btrfs_snapshot
alias bfrmvol=remove_btrfs_subvolume
alias bfhelp=help_btrfs

# Python
alias py34=python3.4
alias android_python_lint=pep8

# Git
alias gitlogfile=mygitlogfile
alias gitlogwithfile='git log --name-only'
alias grbw="echo git codereview rebase-work; git codereview rebase-work"
alias grbcont="echo git rebase --continue; git rebase --continue"
alias gb="git branch"
alias gbl="git for-each-ref --sort='-authordate:iso8601' --format=' %(authordate:relative)%09%(refname:short)' refs/heads"
alias gca="echo git commit --amend ; git commit --amend"
alias gcar="echo git commit --amend --reuse-message=HEAD ; git commit --amend --reuse-message=HEAD"
alias gs="git status"
alias glo="git log --oneline"
alias glf='git log --name-only'
alias gld='git log -p'
alias gitshowhead="git show -s --oneline HEAD"
alias gitmeld='git difftool -d -t ${GRDIFF} -y'
alias gitmeldr='git difftool -t ${GRDIFF} -y'
alias gitmeldc='git difftool --cached -d -t ${GRDIFF} -y'
alias gitmeldh='git difftool -d -t ${GRDIFF} -y HEAD^ '
alias gittrackrbranch=git_track_remote_branch
alias gitlogdiff='git log -u -1 ' # supply sha as arg
alias gitlocalcredentialcache='git config --local credential.helper "cache --timeout=14400"'
alias gitmeldhash=run_git_meld_hash # supply sha as arg
alias gitmeldbranch=run_git_meld_branch # supply file as arg
alias gitshowbranch=run_git_show_local_branch_status
alias repolistgit='repo forall -c pwd'
alias localgitconfig='git config --local user.name "Than McIntosh" ; git config --local user.email thanm@google.com'
alias globalgitconfig='git config --global user.name "Than McIntosh" ; git config --global user.email thanm@google.com'

# Graphical diff
alias linux_graphical_diff=meld
alias macos_graphical_diff=opendiff

# adb stuff
alias adbstartservice='adb am startservice IntentName'
alias adbstart='adb shell stop; adb shell start'
alias adbnonroot="adb shell 'setprop service.adb.root 0; setprop ctl.restart adbd'"
# the following works on master/N
alias adbsetdate='adb shell date @`seconds.pl`'
# the following for M
alias adbsetdate2='adb shell date `date "+%m%d%H%M%Y"`'
alias adbclearlog='adb logcat -c'
alias adblogcatperfprofd="adb logcat 'perfprofd:*' '*:S'"
alias adbremount='adb remount'
alias adbpushbin=adb_push_to_bin
alias adbpushxbin=adb_push_to_xbin
alias adbpushlib=adb_push_to_lib

# llvm stuff
alias llvmpath=addllvmbintopath

# valgrind
alias runvalgrindformassif="/ssd2/valgrind-bin/bin/valgrind --massif-out-file=massif.out --tool=massif"

# zgrviewer
alias zgrviewit=run_zgrviewer

# Enable ptrace attach for gdb.
alias enable_gdb_ptrace_attach="echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope"

# Enable perf events
alias enable_perf_events="echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid"

# handbrake
alias handbrake=ghb
