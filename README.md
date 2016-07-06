# devel-scripts

Assorted scripts for Android, GCC, LLVM, and Go development.

Android
-------

* analyze-android-loadmodule-layout.py

  Runs objdump to gather info on the symbols defined in one or more
executables or shared libraries, then tries to detect possible problems
with text/data layout (primarily padding).

* download-aosp-blobs.py

  This script automates the process of downloading vendor "blobs" needed for doing AOSP Android development. It works by scraping the public preview release blobs page, then downloading the artifacts mentioned on the page.

* blobinstall.py

  Helper script used by install-aosp-blobs.py. See also See download-aosp-blobs.py.

* install-aosp-blobs.py

  This script installs the correct set of vendor blobs for a specific Android device (ex: N5, N7, N9, etc).  See also blobinstall.py and download-aosp-blobs.py

* extract-compile-cmdline.py

  Post-processes the output of an Android platform build transcript to extract compile command lines (useful for reproducing compiler bugs).

* graph-loadmodule-deps.py

  Runs objdump to gather load module dependency relationships, then generates a DOT graph showing load module dependencies.

* mmm.py

  This script simulates the Android "m/mm/mmm" bash functions. Useful if you want to kick off an Android platform build from a script, without having to run "lunch" (or equivalent) as a precursor.

* multi-device-android-build.py

  For Android platform prebuilt compiler testing. Runs multiple device builds within the same repo client.

* run-java-program-on-device.py

  Compile and run a Java program on an Android device (directly with dalvik as opposed to creating a full-fledge Android app).

* showdevices.py

  Show connected Android devices (assumes that you have already set up the DEVTAGS and ANDROID_SERIAL environment vars).

* usb-reset-by-serial.py

  Perform a hardware USB reset operation on a connect Android device with a specific USB serial number.


GCC
---

* gcc-crosscompiler-build.py

  Swiss-army-knife script for partially automating the tricky process of building a cross-compiler version of GCC (runs on host X, targets machine Y).


Miscellaneous
-------------

* annotate-preprocessed.py
* detect_encoding.py
* freezelink.py
* gencode_classes.py
* gencode_package.py
* gencode_regpressure.py
* llsort.py
* StringTable.py
* script_utils.py
* svnpreddiff.py
* trimlines.py
* unit_test_for_script_utils.py

BTRFS
-----

* showsnapshots.py

  Displays information about BTRFS snapshots + volumes on local SSDs. See the script header comment for more info.

* snapshotutil.py

  Utility script for creation and removal of BTRFS subvolumes and snapshots.


LLVM
----

* irc-chat-filt.py

  A filter designed to be run on LLVM irc-chat transcripts-- strips out "XXX joined" and buildbot messages.

* setup-llvm-repos.py

  Helper script for setting up an LLVM development repo.

* setup-lnt-volume.py

  Helper script for setting up an LNT repo
