#!/bin/bash -e

msg() {
    echo
    echo ==== $* ====
    echo
}

export CCACHE_DIR=~/.ccache.dna-kernel

# -----------------------

. kerneltools-build-config

TOOLS_DIR=`dirname "$0"`
MAKE=$TOOLS_DIR/make-common.sh

# -----------------------

ZIP=$TARGET_DIR/AROMA-$VERSION

UPDATE_ROOT=$LOCAL_BUILD_DIR/update
KEYS=$LOCAL_BUILD_DIR/keys
CERT=$KEYS/certificate.pem
KEY=$KEYS/key.pk8

if [ "$USE_CCACHE" = 1 ]; then
   export CROSS_COMPILE="ccache $CROSS_COMPILE"
   export HOST_CC="ccache $HOST_CC"
else
   export CROSS_COMPILE="$CROSS_COMPILE"
   export HOST_CC="$HOST_CC"
fi

msg Building: $VERSION
echo
echo "   Defconfig:       $DEFCONFIG"
echo
echo "   Local build dir: $LOCAL_BUILD_DIR"
echo
echo "   Target dir:      $TARGET_DIR"
echo
echo "   Tools dir:       $TOOLS_DIR"
echo
echo "   Cross compiler:  $CROSS_COMPILE"
echo
echo "   Host compiler:   $HOST_CC"
echo
echo "   Target system partition: $SYSTEM_PARTITION"
echo
echo "   Target boot partition: $BOOT_PARTITION"
echo

if [ -e $CERT -a -e $KEY ]
then
    msg Reusing existing $CERT and $KEY
else
    msg Regenerating keys, pleae enter the required information.

    (
	mkdir -p $KEYS
	cd $KEYS
	openssl genrsa -out key.pem 1024 && \
	openssl req -new -key key.pem -out request.pem && \
	openssl x509 -req -days 9999 -in request.pem -signkey key.pem -out certificate.pem && \
	openssl pkcs8 -topk8 -outform DER -in key.pem -inform PEM -out key.pk8 -nocrypt
    )
fi

if [ -e $UPDATE_ROOT ]
then
    rm -rf $UPDATE_ROOT
fi

if [ -e $LOCAL_BUILD_DIR/update.zip ]
then
    rm -f $LOCAL_BUILD_DIR/update.zip
fi

$MAKE $DEFCONFIG

perl -pi -e 's/(CONFIG_LOCALVERSION="[^"]*)/\1-'"$VERSION"'"/' .config

$MAKE -j$N_CORES

msg Kernel built successfully, building $ZIP.zip

mkdir -p $UPDATE_ROOT

if [ "$INITRD" == "" ]
then
    mkdir -p $UPDATE_ROOT/boot
    cp arch/arm/boot/zImage $UPDATE_ROOT/boot
else
    abootimg --create $UPDATE_ROOT/boot.img -k arch/arm/boot/zImage -f $LOCAL_BUILD_DIR/bootimg.cfg -r $INITRD
fi

if [ -e $LOCAL_BUILD_DIR/system ]
then
    mkdir -p $LOCAL_BUILD_DIR
    cp -r $LOCAL_BUILD_DIR/system $UPDATE_ROOT/system
    permissions=`( cd $LOCAL_BUILD_DIR/system && find . -type f -exec echo -n 'set_perm(0, 0, 0755, "/system/{}"); ' \; )`
fi

mkdir -p $UPDATE_ROOT/system/lib/modules
find . -name '*.ko' -exec cp {} $UPDATE_ROOT/system/lib/modules/ \;

mkdir -p $UPDATE_ROOT/META-INF/com/google/android
cp $TOOLS_DIR/aroma-update-binary $UPDATE_ROOT/META-INF/com/google/android/update-binary
(
    cat <<EOF
$BANNER
EOF
  sed -e "s|@@SYSTEM_PARTITION@@|$SYSTEM_PARTITION|" \
      -e "s|@@BOOT_PARTITION@@|$BOOT_PARTITION|" \
      -e "s|@@FIX_PERMISSIONS@@|$permissions |" \
      < $TOOLS_DIR/aroma-updater-script
) > $UPDATE_ROOT/META-INF/com/google/android/updater-script
cp -r $TOOLS_DIR/aroma $UPDATE_ROOT/META-INF/com/google/android
cp -r $TOOLS_DIR/tools $UPDATE_ROOT/tools
cp $TOOLS_DIR/aroma-config $UPDATE_ROOT/META-INF/com/google/android
cp $TOOLS_DIR/aroma-update-binary-installer $UPDATE_ROOT/META-INF/com/google/android/update-binary-installer
(
    cd $UPDATE_ROOT
    zip -r ../update.zip .
)

java -jar $TOOLS_DIR/signapk.jar $CERT $KEY $LOCAL_BUILD_DIR/update.zip $ZIP.zip

msg COMPLETE
