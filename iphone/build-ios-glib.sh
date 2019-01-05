#!/bin/bash


# Configurable globals
readonly MIN_IOS_VERSION="7.0"

# This is coming off a fork, arm support is not fully functional from the master repo
# See https://github.com/NativeScript/libffi
readonly LIBFFI_VERSION="1.5.2"

readonly GLIB_VERSION="2.47.1"
readonly GETTEXT_VERSION="0.19.6"
readonly ICONV_VERSION="1.14"
readonly PIXMAN_VERSION="0.36.0"
readonly LIBPNG_VERSION="1.6.36"

readonly ARCHS=(arm64 x86_64)

# Calculated globals
readonly ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly DEPS_DIR="${ROOT_DIR}/dependencies"
readonly WORK_DIR="${ROOT_DIR}/work"
readonly LOGFILE="${ROOT_DIR}/build.log"

readonly LIPO="$(xcrun --sdk iphoneos -f lipo)"

readonly IPHONEOS_AR="$(xcrun --sdk iphoneos -f ar)"
readonly IPHONEOS_AS="$(xcrun --sdk iphoneos -f as)"
readonly IPHONEOS_CC="$(xcrun --sdk iphoneos -f clang)"
readonly IPHONEOS_CXX="$(xcrun --sdk iphoneos -f clang++)"
readonly IPHONEOS_NM="$(xcrun --sdk iphoneos -f nm)"
readonly IPHONEOS_RANLIB="$(xcrun --sdk iphoneos -f ranlib)"
readonly IPHONEOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
readonly IPHONEOS_CFLAGS="-isysroot $IPHONEOS_SDK -miphoneos-version-min=$MIN_IOS_VERSION"

readonly IPHONESIM_AR="$(xcrun --sdk iphonesimulator -f ar)"
readonly IPHONESIM_AS="$(xcrun --sdk iphonesimulator -f as)"
readonly IPHONESIM_CC="$(xcrun --sdk iphonesimulator -f clang)"
readonly IPHONESIM_CXX="$(xcrun --sdk iphonesimulator -f clang++)"
readonly IPHONESIM_NM="$(xcrun --sdk iphonesimulator -f nm)"
readonly IPHONESIM_RANLIB="$(xcrun --sdk iphonesimulator -f ranlib)"
readonly IPHONESIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
readonly IPHONESIM_CFLAGS="-isysroot $IPHONESIM_SDK -mios-simulator-version-min=$MIN_IOS_VERSION"

log() {
  local msg=$1
  local now=$(date "+%Y-%m-%d% %H:%M:%S")

  echo "[${now}] $msg" >> ${LOGFILE}
}

is_file() {
  local file=$1

  [[ -f $file ]]
}

is_dir() {
  local dir=$1

  [[ -d $dir ]]
}

is_empty() {
  local var=$1

  [[ -z $var ]]
}

is_universal() {
  local path=$1

  file $path | grep -q universal
}

is_iphone_arch() {
  local arch=$1

  # latest SDKs don't ship crt_externs.h so we have to use the workaround
  # for x86 as well
  [[ $arch == arm* ]] || [[ $arch == *86* ]]
}

fetch() {
  local name=$1
  local url=$2
  local dest=$3

  run "curl -s -L -o $dest $url" "Fetching $name"
}


run() {
  local cmd=$1
  local msg=$2

  log "> ${cmd}"

  echo -n "${msg}..."
  $cmd >> $LOGFILE 2>&1 && echo "done." || {
    log "FAILED with exit code $?"
    echo "failed."
    echo "Build Failed. See ${LOGFILE} for details."
    exit 1
  }
  log "OK."
}

clean_up_prior_build() {
  is_file "${LOGFILE}" \
    && run "rm -f ${LOGFILE}" "Removing old logfile"

  is_dir "${WORK_DIR}" \
    && run "rm -rf ${WORK_DIR}" "Removing old work tree"

  mkdir -p "${WORK_DIR}"
}


# Given an architecture (armv7, i386, etc.) in $1,
# echo out the correct autoconf host triplet
host_for_arch() {
  local readonly arch=$1
  case "$arch" in
    armv*)
      echo "arm-apple-darwin"
      ;;
    arm64)
      echo "aarch64-apple-darwin"
      ;;
    x86_64)
      echo "x86_64-apple-darwin"
      ;;
    i386)
      echo "i386-apple-darwin"
      ;;
    *)
      local msg="ERROR: Unable to determine architecture triplet for $arch"
      log $msg
      echo $msg
      exit 1
  esac
}

# Given an architecture (armv7, i386, etc.) in $1,
# export CFLAGS, CXXFLAGS, etc. appropriate for that arch
set_build_env_for_arch() {
  local readonly arch=$1
  case "$arch" in
    arm*)
	  export AR=$IPHONEOS_AR
	  export AS=$IPHONEOS_AS
      export CC=$IPHONEOS_CC
      export CXX=$IPHONEOS_CXX
      export NM=$IPHONEOS_NM
      export RANLIB=$IPHONEOS_RANLIB
      export CFLAGS="$IPHONEOS_CFLAGS"
      ;;
    x86_64 | i386)
	  export AR=$IPHONESIM_AR
	  export AS=$IPHONESIM_AS
      export CC=$IPHONESIM_CC
      export CXX=$IPHONESIM_CXX
      export NM=$IPHONESIM_NM
      export RANLIB=$IPHONESIM_RANLIB
      export CFLAGS="$IPHONESIM_CFLAGS"
      ;;
    *)
      local msg="ERROR: Unable to set environment variables for $arch"
      log $msg
      echo $msg
      exit 1
  esac

  export PKG_CONFIG_PATH="${ROOT_DIR}/dependencies/libffi/${arch}/lib/pkgconfig"

  export CFLAGS="$CFLAGS -arch ${arch} -DPIXMAN_NO_TLS"
  export CFLAGS="$CFLAGS -I${ROOT_DIR}/dependencies/libffi/${arch}/lib/libffi-3.99999/include"
  export CFLAGS="$CFLAGS -I${ROOT_DIR}/dependencies/gettext/${arch}/include"
  export CFLAGS="$CFLAGS -I${ROOT_DIR}/dependencies/libiconv/${arch}/include"
  export CFLAGS="$CFLAGS -I${ROOT_DIR}/dependencies/libpng/${arch}/include"

  export CXXFLAGS=$CFLAGS
  export CPPFLAGS=$CFLAGS

  export LDFLAGS="-L${ROOT_DIR}/dependencies/libffi/fat/lib -lz"
  export LDFLAGS="$LDFLAGS -L${ROOT_DIR}/dependencies/gettext/fat/lib"
  export LDFLAGS="$LDFLAGS -L${ROOT_DIR}/dependencies/libiconv/fat/lib"
  export LDFLAGS="$LDFLAGS -L${ROOT_DIR}/dependencies/libpng/fat/lib"
  export LDFLAGS="$LDFLAGS -framework Foundation"

  export LIBFFI_LIBS="-lffi"

  export ac_cv_func__NSGetEnviron=no
  export glib_cv_stack_grows=no
  export glib_cv_uscore=no
  export ac_cv_func_posix_getgrgid_r=yes
  export ac_cv_func_posix_getpwuid_r=yes

  export PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH
  OLD_PATH=$PATH

  # It looks like previously simulator binaries would run on macOS/OSX
  # and it was enough to build gettext for the Simulator for the
  # msgfmt to work. Not anymore.
  # For now I don't want to fix building everything for macOS
  # so just use the tools from host gettext obtained via homebrew
  #export PATH="${ROOT_DIR}/dependencies/gettext/x86_64/bin:$PATH"
  export PATH=/usr/local/Cellar/gettext/0.19.8.1/bin:$PATH
  export PATH="${WORK_DIR}/fake_pkgconfig/bin":$PATH
}

unset_build_env() {
  unset \
    PKG_CONFIG_PATH \
    CC \
    CXX \
    CFLAGS \
    CXXFLAGS \
    CPPFLAGS \
    LDFLAGS \
    \
    ac_cv_func__NSGetEnviron \
    glib_cv_stack_grows \
    glib_cv_uscore \
    ac_cv_func_posix_getgrgid_r \
    ac_cv_func_posix_getpwuid_r

  export PATH=$OLD_PATH
}


# Given a pattern like dependencies/libffi/ARCH/lib/libffi.a
# fatify will locate the static libs for each arch in $ARCHS
# (replacing the magic string 'ARCH' with the appropriate architecture)
# and emit a fat binary in, e.g.,  dependencies/libffi/fat/lib/libffi.a
fatify() {
  local pattern=$1

  local libshortname=$(basename ${pattern})
  local destfile=$(echo ${pattern} | sed s/ARCH/fat/)
  local destdir=$(dirname ${destfile})
  local tempdir="${ROOT_DIR}/.lipo_tmp"

  is_dir "${tempdir}" \
    && run "rm -rf ${tempdir}" "Removing old universal prep temp directory"
  run "mkdir ${tempdir}" "Creating temp directory for universal binary prep"

  local archlist=""
  for arch in "${ARCHS[@]}"; do
    local path=$(echo $pattern | sed s/ARCH/$arch/)
    local libname=${path}

    if $(is_universal $path); then
      local tmpname="${tempdir}/${arch}_${libshortname}"
      local cmd="${LIPO} ${path} -thin ${arch} -output ${tmpname}"
      run "${cmd}" "Extracting $arch from ${path}"
      libname=${tmpname}
    fi

    archlist="${archlist} -arch ${arch} ${libname}"
  done

  run "mkdir -p ${destdir}" "Creating universal binary output directory ${destdir}"

  local cmd="${LIPO} -create -output ${destfile} ${archlist}"
  run "${cmd}" "Creating universal binary for $(basename ${destfile})"
}

build_iconv() {
  local iconvarchive="${WORK_DIR}/iconv.tar.gz"
  local iconvdir="${WORK_DIR}/libiconv-${ICONV_VERSION}"
  local prefix="${DEPS_DIR}/libiconv"

  echo "Beginning build of libiconv"

  ! is_file $iconvarchive \
    && fetch "libiconv" \
      "http://ftp.gnu.org/pub/gnu/libiconv/libiconv-${ICONV_VERSION}.tar.gz" \
      ${iconvarchive}

  for arch in "${ARCHS[@]}"; do
    set_build_env_for_arch ${arch}

    run "env" "Logging environment"

    echo "Building libiconv for $arch"

    is_dir $iconvdir \
      && run "rm -rf $iconvdir" "  Removing old libiconv build directory"

    cd "${WORK_DIR}"
    run "tar xzf ${iconvarchive}" "  Unpacking libiconv"

    cd "${iconvdir}"

    is_iphone_arch ${arch} \
      && sed -i '' 's/if defined __APPLE__ \&\& defined __MACH__/if defined __APPLE__ \&\& defined __MACH__ \&\& defined SKIPIT/' srclib/unistd.in.h

    local host_type=$(host_for_arch ${arch})
    if [ "$arch" == "arm64" ]; then
      host_type="arm-apple-darwin"
    fi

    read -d '' cmd <<EOF
      ./configure \
        --prefix=$prefix/${arch} \
        --enable-static \
        --disable-shared \
        --host=${host_type}
EOF

    run "${cmd}" "  Configuring libiconv for ${arch}"
    run "make -j12" "  Building libiconv for ${arch}"

    run "mkdir -p ${prefix}/${arch}" "  Creating output directory for ${arch}"
    run "make install" "  Installing libiconv for ${arch} into ${prefix}/${arch}"
  done

  cd ${ROOT_DIR}
  local iconvlibs=(libcharset.a libiconv.a)
  for lib in "${iconvlibs[@]}"; do
    fatify "dependencies/libiconv/ARCH/lib/${lib}"
  done

  unset_build_env
  unset cmd
}

build_pixman() {
  local pixmanarchive="${WORK_DIR}/pixman.tar.gz"
  local pixmandir="${WORK_DIR}/pixman-${PIXMAN_VERSION}"
  local prefix="${DEPS_DIR}/pixman"

  echo "Beginning build of pixman"

  ! is_file $pixmanarchive \
    && fetch "pixman" \
      "https://www.cairographics.org/releases/pixman-${PIXMAN_VERSION}.tar.gz" \
      ${pixmanarchive}

  for arch in "${ARCHS[@]}"; do
    set_build_env_for_arch ${arch}

    run "env" "Logging environment"

    echo "Building pixman for $arch"

    is_dir $pixmandir \
      && run "rm -rf $pixmandir" "  Removing old pixman build directory"

    cd "${WORK_DIR}"
    run "tar xzf ${pixmanarchive}" "  Unpacking pixman"

    cd "${pixmandir}"
    export NOCONFIGURE=true
	run "sed -i. s/SUBDIRS.*/SUBDIRS=pixman/ Makefile.am" "disabling pixman tests and demos in Makefile.am"
	run "sed -i. s|test/Makefile|| configure.ac" "disabling pixman tests in configure.ac"
	run "sed -i. s|demos/Makefile|| configure.ac" "disabling pixman demos in configure.ac"
	run "autoreconf --force --install" "Running autoreconf for pixman"
    unset NOCONFIGURE

    local host_type=$(host_for_arch ${arch})
    if [ "$arch" == "arm64" ]; then
      host_type="arm-apple-darwin"
    fi

    read -d '' cmd <<EOF
      ./configure \
        --prefix=$prefix/${arch} \
        --enable-static \
        --disable-shared \
		--disable-libpng \
		--disable-static-testprogs \
        --host=${host_type}
EOF

    run "${cmd}" "  Configuring pixman for ${arch}"
    run "make -j12" "  Building pixman for ${arch}"

    run "mkdir -p ${prefix}/${arch}" "  Creating output directory for ${arch}"
    run "make install" "  Installing pixman for ${arch} into ${prefix}/${arch}"
  done

  cd ${ROOT_DIR}
  local pixmanlibs=(libpixman-1.a)
  for lib in "${pixmanlibs[@]}"; do
    fatify "dependencies/pixman/ARCH/lib/${lib}"
  done

  unset_build_env
  unset cmd
}

build_libpng() {
  local libpngarchive="${WORK_DIR}/libpng.tar.gz"
  local libpngdir="${WORK_DIR}/libpng-${LIBPNG_VERSION}"
  local prefix="${DEPS_DIR}/libpng"

  echo "Beginning build of libpng"

  ! is_file $libpngarchive \
    && fetch "libpng" \
      "https://download.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.gz" \
      ${libpngarchive}

  for arch in "${ARCHS[@]}"; do
    set_build_env_for_arch ${arch}

    run "env" "Logging environment"

    echo "Building libpng for $arch"

    is_dir $libpngdir \
      && run "rm -rf $libpngdir" "  Removing old libpng build directory"

    cd "${WORK_DIR}"
    run "tar xzf ${libpngarchive}" "  Unpacking libpng"

    cd "${libpngdir}"

    local host_type=$(host_for_arch ${arch})
    if [ "$arch" == "arm64" ]; then
      host_type="arm-apple-darwin"
    fi

    read -d '' cmd <<EOF
      ./configure \
        --prefix=$prefix/${arch} \
        --enable-static \
        --disable-shared \
        --host=${host_type}
EOF

    run "${cmd}" "  Configuring libpng for ${arch}"
    run "make -j12" "  Building libpng for ${arch}"

    run "mkdir -p ${prefix}/${arch}" "  Creating output directory for ${arch}"
    run "make install" "  Installing libpng for ${arch} into ${prefix}/${arch}"
  done

  cd ${ROOT_DIR}
  local libpnglibs=(libpng.a)
  for lib in "${libpnglibs[@]}"; do
    fatify "dependencies/libpng/ARCH/lib/${lib}"
  done

  unset_build_env
  unset cmd
}

build_gettext() {
  local gtarchive="${WORK_DIR}/gt.tar.gz"
  local gtdir="${WORK_DIR}/gettext-${GETTEXT_VERSION}"
  local prefix="${DEPS_DIR}/gettext"

  echo "Beginning build of gettext"

  ! is_file $gtarchive \
    && fetch "gettext" \
      "http://ftp.gnu.org/pub/gnu/gettext/gettext-${GETTEXT_VERSION}.tar.gz" \
      ${gtarchive}

  for arch in "${ARCHS[@]}"; do
    set_build_env_for_arch ${arch}

    run "env" "Logging environment"

    echo "Building gettext for $arch"

    is_dir $gtdir \
      && run "rm -rf $gtdir" "  Removing old gettext build directory"

    cd "${WORK_DIR}"
    run "tar xzf ${gtarchive}" "  Unpacking gettext"

    cd "${gtdir}"

    read -d '' cmd <<EOF
      ./configure \
        --prefix=$prefix/${arch} \
        --enable-static \
        --disable-shared \
        --host=$(host_for_arch ${arch})
EOF

    run "${cmd}" "  Configuring gettext for ${arch}"
    run "make -j12" "  Building gettext for ${arch}"

    run "mkdir -p ${prefix}/${arch}" "  Creating output directory for ${arch}"
    run "make install" "  Installing gettext for ${arch} into ${prefix}/${arch}"
  done

  cd ${ROOT_DIR}
  local gtlibs=(libasprintf.a libgettextpo.a libintl.a)
  for lib in "${gtlibs[@]}"; do
    fatify "dependencies/gettext/ARCH/lib/${lib}"
  done

  unset_build_env
  unset cmd

}

build_glib() {
  local glibzip="${WORK_DIR}/glib.zip"
  local glibdir="${WORK_DIR}/glib-${GLIB_VERSION}"
  local prefix="${DEPS_DIR}/glib"

  echo "Beginning build of glib"

  ! is_file $glibzip \
    && fetch "glib" \
      "https://github.com/GNOME/glib/archive/${GLIB_VERSION}.zip" \
      ${glibzip}

  for arch in "${ARCHS[@]}"; do
    set_build_env_for_arch ${arch}

    run "env" "Logging environment"

    echo "Building glib for $arch"

    is_dir $glibdir \
      && run "rm -rf $glibdir" "  Removing old glib build directory"

    cd "${WORK_DIR}"
    run "unzip ${glibzip}" "  Unpacking glib"

    cd "${glibdir}"
    export NOCONFIGURE=true
	run "sed -i. s/m4_copy/m4_copy_force/ m4macros/glib-gettext.m4"
    run "./autogen.sh" "  Bootstrapping autoconf for glib"
    unset NOCONFIGURE

    read -d '' cmd <<EOF
      ./configure \
        --prefix=$prefix/${arch} \
        --enable-static \
        --disable-shared \
        --host=$(host_for_arch ${arch}) \
        --with-libiconv=gnu \
		--disable-libelf \
        --disable-dtrace
EOF

    run "${cmd}" "  Configuring glib for ${arch}"
    run "make -j12" "  Building glib for ${arch}"

    run "mkdir -p ${prefix}/${arch}" "  Creating output directory for ${arch}"
    run "make install" "  Installing glib for ${arch} into ${prefix}/${arch}"
  done

  cd ${ROOT_DIR}
  local glibs=(libgio-2.0.a libglib-2.0.a libgmodule-2.0.a libgobject-2.0.a libgthread-2.0.a)
  for lib in "${glibs[@]}"; do
    fatify "dependencies/glib/ARCH/lib/${lib}"
  done

  unset_build_env
  unset cmd
}




build_libffi() {
  local ffizip="${WORK_DIR}/ffi.zip"
  local ffidir="${WORK_DIR}/libffi-${LIBFFI_VERSION}"
  local prefix="${DEPS_DIR}/libffi"

  echo "Beginning build of dependency: libffi"

  ! is_file $ffizip \
    && fetch "libffi" \
      "https://github.com/NativeScript/libffi/archive/${LIBFFI_VERSION}.zip" \
      ${ffizip}

  is_dir $ffidir \
    && run "rm -rf $ffidir" "Removing old libffi build directory"

  cd "${WORK_DIR}"
  run "unzip ${ffizip}" "Unpacking libffi"

  cd "${ffidir}"
  run "./autogen.sh" "Bootstrapping autoconf for libffi"

  for arch in "${ARCHS[@]}"; do
    set_build_env_for_arch ${arch}

    echo "Building libffi for $arch"

    is_file config.status \
      && run "make distclean" "  Cleaning up from last run"

    read -d '' cmd <<EOF
      ./configure \
        --prefix=$prefix/${arch} \
        --enable-static \
        --disable-shared \
        --host=$(host_for_arch ${arch})
EOF

    run "${cmd}" "  Configuring libffi for ${arch}"
    run "make -j12" "  Building libffi for ${arch}"

    run "mkdir -p ${prefix}/${arch}" "  Creating output directory for ${arch}"
    run "make install" "  Installing libffi for ${arch} into ${prefix}/${arch}"
  done

  cd ${ROOT_DIR}
  fatify "dependencies/libffi/ARCH/lib/libffi.a"

  unset_build_env
  unset cmd
}


main() {
  # clean_up_prior_build
  log "Beginning build"
  mkdir -p "${WORK_DIR}/fake_pkgconfig/bin" || true
  touch "${WORK_DIR}/fake_pkgconfig/bin/pkg-config"
  chmod +x "${WORK_DIR}/fake_pkgconfig/bin/pkg-config"

  build_libffi
  build_iconv
  build_gettext
  build_iconv
  build_glib

  #QEMU seems to work without PNG so skip it for now
  #build_libpng
  build_pixman
}

main
