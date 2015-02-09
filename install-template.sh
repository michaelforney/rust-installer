#!/bin/sh
# Copyright 2014 The Rust Project Developers. See the COPYRIGHT
# file at the top-level directory of this distribution and at
# http://rust-lang.org/COPYRIGHT.
#
# Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
# http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
# <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
# option. This file may not be copied, modified, or distributed
# except according to those terms.

# No undefined variables
set -u

msg() {
    echo "install: ${1-}"
}

step_msg() {
    msg
    msg "$1"
    msg
}

warn() {
    echo "install: WARNING: $1" >&2
}

err() {
    echo "install: error: $1" >&2
    exit 1
}

need_ok() {
    if [ $? -ne 0 ]
    then
        err "$1"
    fi
}

assert_nz() {
    if [ -z "$1" ]; then err "assert_nz $2"; fi
}

need_cmd() {
    if command -v $1 >/dev/null 2>&1
    then msg "found $1"
    else err "need $1"
    fi
}

putvar() {
    local t
    local tlen
    eval t=\$$1
    eval tlen=\${#$1}
    if [ $tlen -gt 35 ]
    then
        printf "install: %-20s := %.35s ...\n" $1 "$t"
    else
        printf "install: %-20s := %s %s\n" $1 "$t"
    fi
}

valopt() {
    VAL_OPTIONS="$VAL_OPTIONS $1"

    local op=$1
    local default=$2
    shift
    shift
    local doc="$*"
    if [ $HELP -eq 0 ]
    then
        local uop=$(echo $op | tr '[:lower:]' '[:upper:]' | tr '\-' '\_')
        local v="CFG_${uop}"
        eval $v="$default"
        for arg in $CFG_ARGS
        do
            if echo "$arg" | grep -q -- "--$op="
            then
                local val=$(echo "$arg" | cut -f2 -d=)
                eval $v=$val
            fi
        done
        putvar $v
    else
        if [ -z "$default" ]
        then
            default="<none>"
        fi
        op="${default}=[${default}]"
        printf "    --%-30s %s\n" "$op" "$doc"
    fi
}

opt() {
    BOOL_OPTIONS="$BOOL_OPTIONS $1"

    local op=$1
    local default=$2
    shift
    shift
    local doc="$*"
    local flag=""

    if [ $default -eq 0 ]
    then
        flag="enable"
    else
        flag="disable"
        doc="don't $doc"
    fi

    if [ $HELP -eq 0 ]
    then
        for arg in $CFG_ARGS
        do
            if [ "$arg" = "--${flag}-${op}" ]
            then
                op=$(echo $op | tr 'a-z-' 'A-Z_')
                flag=$(echo $flag | tr 'a-z' 'A-Z')
                local v="CFG_${flag}_${op}"
                eval $v=1
                putvar $v
            fi
        done
    else
        if [ ! -z "$META" ]
        then
            op="$op=<$META>"
        fi
        printf "    --%-30s %s\n" "$flag-$op" "$doc"
     fi
}

flag() {
    BOOL_OPTIONS="$BOOL_OPTIONS $1"

    local op=$1
    shift
    local doc="$*"

    if [ $HELP -eq 0 ]
    then
        for arg in $CFG_ARGS
        do
            if [ "$arg" = "--${op}" ]
            then
                op=$(echo $op | tr 'a-z-' 'A-Z_')
                local v="CFG_${op}"
                eval $v=1
                putvar $v
            fi
        done
    else
        if [ ! -z "$META" ]
        then
            op="$op=<$META>"
        fi
        printf "    --%-30s %s\n" "$op" "$doc"
     fi
}

validate_opt () {
    for arg in $CFG_ARGS
    do
        local is_arg_valid=0
        for option in $BOOL_OPTIONS
        do
            if test --disable-$option = $arg
            then
                is_arg_valid=1
            fi
            if test --enable-$option = $arg
            then
                is_arg_valid=1
            fi
            if test --$option = $arg
            then
                is_arg_valid=1
            fi
        done
        for option in $VAL_OPTIONS
        do
            if echo "$arg" | grep -q -- "--$option="
            then
                is_arg_valid=1
            fi
        done
        if [ "$arg" = "--help" ]
        then
            echo
            echo "No more help available for Configure options,"
            echo "check the Wiki or join our IRC channel"
            break
        else
            if test $is_arg_valid -eq 0
            then
                err "Option '$arg' is not recognized"
            fi
        fi
    done
}

absolutify() {
    local file_path="$1"
    local file_path_dirname="$(dirname "$file_path")"
    local file_path_basename="$(basename "$file_path")"
    local file_abs_path="$(cd "$file_path_dirname" && pwd)"
    local file_path="$file_abs_path/$file_path_basename"
    # This is the return value
    RETVAL="$file_path"
}

get_host_triple() {
    local _uname_value=$(uname -s)
    local _ostype
    case $_uname_value in

	Linux)
            _ostype=unknown-linux-gnu
            ;;

	FreeBSD)
            _ostype=unknown-freebsd
            ;;

	DragonFly)
            _ostype=unknown-dragonfly
            ;;

	Darwin)
            _ostype=apple-darwin
            ;;

	MINGW*)
            _ostype=pc-windows-gnu
            ;;

	MSYS*)
            _ostype=pc-windows-gnu
            ;;

	# Vista 32 bit
	CYGWIN_NT-6.0)
            _ostype=pc-windows-gnu
            ;;

	# Vista 64 bit
	CYGWIN_NT-6.0-WOW64)
            _ostype=pc-windows-gnu
            ;;

	# Win 7 32 bit
	CYGWIN_NT-6.1)
            _ostype=pc-windows-gnu
            ;;

	# Win 7 64 bit
	CYGWIN_NT-6.1-WOW64)
            _ostype=pc-windows-gnu
            ;;

	*)
	    err "unknown value from uname -s: $uname_value"
	    ;;
    esac

    RETVAL="$_ostype"
}

uninstall_legacy() {
    local _abs_libdir="$1"

    local _uninstalled_something=false

    # Replace commas in legacy manifest list with spaces
    _legacy_manifest_dirs=`echo "$TEMPLATE_LEGACY_MANIFEST_DIRS" | sed "s/,/ /g"`

    # Uninstall from legacy manifests
    local _md
    for _md in $_legacy_manifest_dirs; do
	# First, uninstall from the installation prefix.
	# Errors are warnings - try to rm everything in the manifest even if some fail.
	if [ -f "$_abs_libdir/$_md/manifest" ]
	then

	    # iterate through installed manifest and remove files
	    local _p;
	    while read _p; do
		# the installed manifest contains absolute paths
		msg "removing legacy file $_p"
		if [ -f "$_p" ]
		then
		    rm -f "$_p"
		    if [ $? -ne 0 ]
		    then
			warn "failed to remove $_p"
		    fi
		else
		    warn "supposedly installed file $_p does not exist!"
		fi
	    done < "$_abs_libdir/$_md/manifest"

	    # If we fail to remove $md below, then the
	    # installed manifest will still be full; the installed manifest
	    # needs to be empty before install.
	    msg "removing legacy manifest $_abs_libdir/$_md/manifest"
	    rm -f "$_abs_libdir/$_md/manifest"
	    # For the above reason, this is a hard error
	    need_ok "failed to remove installed manifest"

	    # Remove $template_rel_manifest_dir directory
	    msg "removing legacy manifest dir $_abs_libdir/$_md"
	    rm -Rf "$_abs_libdir/$_md"
	    if [ $? -ne 0 ]
	    then
		warn "failed to remove $_md"
	    fi

	    _uninstalled_something=true
	fi
    done

    RETVAL="$_uninstalled_something"
}

uninstall_components() {
    local _abs_libdir="$1"
    local _dest_prefix="$2"
    local _components="$3"

    # We're going to start by uninstalling existing components. This
    local _uninstalled_something=false

    # First, try removing any 'legacy' manifests from before
    # rust-installer
    uninstall_legacy "$_abs_libdir"
    assert_nz "$RETVAL", "RETVAL"
    if [ "$RETVAL" = true ]; then
	_uninstalled_something=true;
    fi

    # Load the version of the installed installer
    local _installed_version=
    if [ -f "$abs_libdir/$TEMPLATE_REL_MANIFEST_DIR/rust-installer-version" ]; then
	_installed_version=`cat "$_abs_libdir/$TEMPLATE_REL_MANIFEST_DIR/rust-installer-version"`

	# Sanity check
	if [ ! -n "$_installed_version" ]; then err "rust installer version is empty"; fi
    fi

    # If there's something installed, then uninstall
    if [ -n "$_installed_version" ]; then
	# Check the version of the installed installer
	case "$_installed_version" in

	    # If this is a previous version, then upgrade in place to the
	    # current version before uninstalling.
	    2)
		;;

	    # This is the current version. Nothing need to be done except uninstall.
	    "$TEMPLATE_RUST_INSTALLER_VERSION")
		;;

	    # TODO: If this is an unknown (future) version then bail.
	    *)
		echo "The copy of $TEMPLATE_PRODUCT_NAME at $_dest_prefix was installed using an"
		echo "unknown version ($_installed_version) of rust-installer."
		echo "Uninstall it first with the installer used for the original installation"
		echo "before continuing."
		exit 1
		;;
	esac

	local _md="$_abs_libdir/$TEMPLATE_REL_MANIFEST_DIR"
	local _installed_components="$(cat "$_md/components")"

	# Uninstall (our components only) before reinstalling
	local _available_component
	for _available_component in $_components; do
	    local _installed_component
	    for _installed_component in $_installed_components; do
		if [ "$_available_component" = "$_installed_component" ]; then
		    local _component_manifest="$_md/manifest-$_installed_component"

		    # Sanity check: there should be a component manifest
		    if [ ! -f "$_component_manifest" ]; then
			err "installed component '$_installed_component' has no manifest"
		    fi

		    # Iterate through installed component manifest and remove files
		    local _directive
		    while read _directive; do

			local _command=`echo $_directive | cut -f1 -d:`
			local _file=`echo $_directive | cut -f2 -d:`

			# Sanity checks
			if [ ! -n "$_command" ]; then err "malformed installation directive"; fi
			if [ ! -n "$_file" ]; then err "malformed installation directive"; fi

			case "$_command" in
			    file)
				msg "removing file $_file"
				if [ -f "$_file" ]; then
				    rm -f "$_file"
				    if [ $? -ne 0 ]; then
					warn "failed to remove $_file"
				    fi
				else
				    warn "supposedly installed file $_file does not exist!"
				fi
				;;

			    dir)
				msg "removing directory $_file"
				rm -rf "$_file"
				if [ $? -ne 0 ]; then
				    warn "unable to remove directory $_file"
				fi
				;;

			    *)
				err "unknown installation directive"
				;;
			esac

		    done < "$_component_manifest"

		    # Remove the installed component manifest
		    msg "removing component manifest $_component_manifest"
		    rm -f "$_component_manifest"
		    # This is a hard error because the installation is unrecoverable
		    need_ok "failed to remove installed manifest for component '$_installed_component'"

		    # Update the installed component list
		    local _modified_components="$(sed "/^$_installed_component\$/d" "$_md/components")"
		    echo "$_modified_components" > "$_md/components"
		    need_ok "failed to update installed component list"
		fi
	    done
	done

	# If there are no remaining components delete the manifest directory
	local _remaining_components="$(cat "$_md/components")"
	if [ ! -n "$_remaining_components" ]; then
	    msg "removing manifest directory $_md"
	    rm -rf "$_md"
	    if [ $? -ne 0 ]; then
		warn "failed to remove $_md"
	    fi
	fi

	_uninstalled_something=true
    fi

    # There's no installed version. If we were asked to uninstall, then that's a problem.
    if [ -n "${CFG_UNINSTALL-}" -a "$_uninstalled_something" = false ]
    then
	err "unable to find installation manifest at $CFG_LIBDIR/$TEMPLATE_REL_MANIFEST_DIR"
    fi
}

install_components() {
    local _src_dir="$1"
    local _abs_libdir="$2"
    local _dest_prefix="$3"
    local _components="$4"

    local _component
    for _component in $_components; do

	# The file name of the manifest we're installing from
	local _input_manifest="$_src_dir/$_component/manifest.in"

	# Sanity check: do we have our input manifests?
	if [ ! -f "$_input_manifest" ]; then
	    err "manifest for $_component does not exist at $_input_manifest"
	fi

	# The installed manifest directory
	local _md="$_abs_libdir/$TEMPLATE_REL_MANIFEST_DIR"

	# The file name of the manifest we're going to create during install
	local _installed_manifest="$_md/manifest-$_component"

	# Create the installed manifest, which we will fill in with absolute file paths
	touch "$_installed_manifest"
	need_ok "failed to create installed manifest"

	# Now install, iterate through the new manifest and copy files
	local _directive
	while read _directive; do

	    local _command=`echo $_directive | cut -f1 -d:`
	    local _file=`echo $_directive | cut -f2 -d:`

	    # Sanity checks
	    if [ ! -n "$_command" ]; then err "malformed installation directive"; fi
	    if [ ! -n "$_file" ]; then err "malformed installation directive"; fi

	    # Decide the destination of the file
	    local _file_install_path="$_dest_prefix/$_file"

	    if echo "$_file" | grep "^lib/" > /dev/null
	    then
		local _f="$(echo "$_file" | sed 's/^lib\///')"
		_file_install_path="$CFG_LIBDIR/$_f"
	    fi

	    if echo "$_file" | grep "^share/man/" > /dev/null
	    then
		local _f="$(echo "$_file" | sed 's/^share\/man\///')"
		_file_install_path="$CFG_MANDIR/$_f"
	    fi

	    # Make sure there's a directory for it
	    umask 022 && mkdir -p "$(dirname "$_file_install_path")"
	    need_ok "directory creation failed"

	    # Make the path absolute so we can uninstall it later without
	    # starting from the installation cwd
	    absolutify "$_file_install_path"
	    _file_install_path="$RETVAL"
	    assert_nz "$_file_install_path" "file_install_path"

	    case "$_command" in
		file )

		    # Install the file
		    msg "copying file $_file_install_path"
		    if echo "$_file" | grep "^bin/" > /dev/null
		    then
			install -m755 "$_src_dir/$_component/$_file" "$_file_install_path"
		    else
			install -m644 "$_src_dir/$_component/$_file" "$_file_install_path"
		    fi
		    need_ok "file creation failed"

		    # Update the manifest
		    echo "file:$_file_install_path" >> "$_installed_manifest"
		    need_ok "failed to update manifest"

		    ;;

		dir )

		    # Copy the dir
		    msg "copying directory $_file_install_path"

		    # Sanity check: bulk dirs are supposed to be uniquely ours and should not exist
		    if [ -e "$_file_install_path" ]; then
			err "$_file_install_path already exists"
		    fi

		    cp -R "$_src_dir/$_component/$_file" "$_file_install_path"
		    need_ok "failed to copy directory"

                    # Set permissions. 0755 for dirs, 644 for files
                    chmod -R u+rwx,go+rx,go-w "$_file_install_path"
                    need_ok "failed to set permissions on directory"

		    # Update the manifest
		    echo "dir:$_file_install_path" >> "$_installed_manifest"
		    need_ok "failed to update manifest"
		    ;;

		*)
		    err "unknown installation directive"
		    ;;
	    esac
	done < "$_input_manifest"

	# Update the components
	echo "$_component" >> "$_md/components"
	need_ok "failed to update components list for $_component"

    done
}

maybe_run_ldconfig() {
    get_host_triple
    local _ostype="$RETVAL"
    assert_nz "$_ostype"  "ostype"

    if [ "$_ostype" = "unknown-linux-gnu" -a ! -n "${CFG_DISABLE_LDCONFIG-}" ]; then
	msg "running ldconfig"
	ldconfig
	if [ $? -ne 0 ]
	then
            warn "failed to run ldconfig."
            warn "this may happen when not installing as root and may be fine"
	fi
    fi
}

install_uninstaller() {
    local _src_dir="$1"
    local _src_basename="$2"
    local _abs_libdir="$3"

    local _uninstaller="$_abs_libdir/$TEMPLATE_REL_MANIFEST_DIR/uninstall.sh"
    msg "creating uninstall script at $_uninstaller"
    cp "$_src_dir/$_src_basename" "$_uninstaller"
    need_ok "unable to install uninstaller"
}

do_preflight_sanity_checks() {
    local _src_dir="$1"
    local _dest_prefix="$2"

    # Sanity check: can we can write to the destination?
    msg "verifying destination is writable"
    umask 022 && mkdir -p "$CFG_LIBDIR"
    need_ok "can't write to destination. consider \`sudo\`."
    touch "$CFG_LIBDIR/rust-install-probe" > /dev/null
    if [ $? -ne 0 ]
    then
	err "can't write to destination. consider \`sudo\`."
    fi
    rm -f "$CFG_LIBDIR/rust-install-probe"
    need_ok "failed to remove install probe"

    # Sanity check: don't install to the directory containing the installer.
    # That would surely cause chaos.
    msg "verifying destination is not the same as source"
    local _prefix_dir="$(cd "$dest_prefix" && pwd)"
    if [ "$_src_dir" = "$_dest_prefix" -a "${CFG_UNINSTALL-}" != 1 ]; then
	err "cannot install to same directory as installer"
    fi
}

msg "looking for install programs"
msg

need_cmd mkdir
need_cmd printf
need_cmd cut
need_cmd grep
need_cmd uname
need_cmd tr
need_cmd sed
need_cmd chmod

CFG_ARGS="$@"

HELP=0
if [ "${1-}" = "--help" ]
then
    HELP=1
    shift
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo
else
    step_msg "processing arguments"
fi

OPTIONS=""
BOOL_OPTIONS=""
VAL_OPTIONS=""

flag uninstall "only uninstall from the installation prefix"
valopt destdir "" "set installation root"
opt verify 1 "verify that the installed binaries run correctly"
valopt prefix "/usr/local" "set installation prefix"

# Avoid prepending an extra / to the prefix path if there's no destdir
if [ -z "$CFG_DESTDIR" ]; then
    CFG_DESTDIR_PREFIX="$CFG_PREFIX"
else
    CFG_DESTDIR_PREFIX="$CFG_DESTDIR/$CFG_PREFIX"
fi

# NB This isn't quite the same definition as in `configure`.
# just using 'lib' instead of configure's CFG_LIBDIR_RELATIVE
valopt libdir "$CFG_DESTDIR_PREFIX/lib" "install libraries"
valopt mandir "$CFG_DESTDIR_PREFIX/share/man" "install man pages in PATH"
opt ldconfig 1 "run ldconfig after installation (Linux only)"
valopt components "" "comma-separated list of components to install"
flag list-components "list available components"

if [ $HELP -eq 1 ]
then
    echo
    exit 0
fi

step_msg "validating arguments"
validate_opt

# Template configuration.
# These names surrounded by '%%` are replaced by sed when generating install.sh
# FIXME: Might want to consider loading this from a file and not generating install.sh

# Rust or Cargo
TEMPLATE_PRODUCT_NAME=%%TEMPLATE_PRODUCT_NAME%%
# rustlib or cargo
TEMPLATE_REL_MANIFEST_DIR=%%TEMPLATE_REL_MANIFEST_DIR%%
# 'Rust is ready to roll.' or 'Cargo is cool to cruise.'
TEMPLATE_SUCCESS_MESSAGE=%%TEMPLATE_SUCCESS_MESSAGE%%
# Locations to look for directories containing legacy, pre-versioned manifests
TEMPLATE_LEGACY_MANIFEST_DIRS=%%TEMPLATE_LEGACY_MANIFEST_DIRS%%
# The installer version
TEMPLATE_RUST_INSTALLER_VERSION=%%TEMPLATE_RUST_INSTALLER_VERSION%%

# OK, let's get installing ...

# This is where we are installing from
src_dir="$(cd $(dirname "$0") && pwd)"

# The name of the script
src_basename="$(basename "$0")"

# If we've been run as 'uninstall.sh' (from the existing installation)
# then we're doing a full uninstall, as opposed to the --uninstall flag
# which just means 'uninstall my components'.
if [ "$src_basename" = "uninstall.sh" ]; then
    if [ "$*" != "" ]; then
	# Currently don't know what to do with arguments in this mode
	err "uninstall.sh does not take any arguments"
    fi
    CFG_UNINSTALL=1
    CFG_DESTDIR_PREFIX="$(cd "$src_dir/../../" && pwd)"
    CFG_LIBDIR="$(cd "$src_dir/../" && pwd)"
fi

# This is where we are installing to
dest_prefix="$CFG_DESTDIR_PREFIX"

# Open the components file to get the list of components to install.
# NB: During install this components file is read from the installer's
# source dir, during a full uninstall it's read from the manifest dir,
# and thus contains all installed components.
components=`cat "$src_dir/components"`

# Sanity check: do we have components?
if [ ! -n "$components" ]; then
    err "unable to find installation components"
fi

# If the user asked for a component list, do that and exit
if [ -n "${CFG_LIST_COMPONENTS-}" ]; then
    echo
    echo "# Available components"
    echo
    for component in $components; do
	echo "* $component"
    done
    echo
    exit 0
fi

# If the user specified which components to install/uninstall,
# then validate that they exist and select them for installation
if [ -n "$CFG_COMPONENTS" ]; then
    # Remove commas
    user_components="$(echo "$CFG_COMPONENTS" | sed "s/,/ /g")"
    for user_component in $user_components; do
	found=false
	for my_component in $components; do
	    if [ "$user_component" = "$my_component" ]; then
		found=true
	    fi
	done
	if [ "$found" = false ]; then
	    err "unknown component: $user_component"
	fi
    done
    components="$user_components"
fi

do_preflight_sanity_checks "$src_dir" "$dest_prefix"

# Using an absolute path to libdir in a few places so that the status
# messages are consistently using absolute paths.
absolutify "$CFG_LIBDIR"
abs_libdir="$RETVAL"
assert_nz "$abs_libdir" "abs_libdir"

# First do any uninstallation, including from legacy manifests. This
# will also upgrade the metadata of existing installs.
uninstall_components "$abs_libdir" "$dest_prefix" "$components"

# If we're only uninstalling then exit
if [ -n "${CFG_UNINSTALL-}" ]
then
    echo
    echo "    $TEMPLATE_PRODUCT_NAME is uninstalled."
    echo
    exit 0
fi

# Create the directory to contain the manifests
mkdir -p "$CFG_LIBDIR/$TEMPLATE_REL_MANIFEST_DIR"
need_ok "failed to create $TEMPLATE_REL_MANIFEST_DIR"

# Install each component
install_components "$src_dir" "$abs_libdir" "$dest_prefix" "$components"

# Drop the version number into the manifest dir
echo "$TEMPLATE_RUST_INSTALLER_VERSION" > "$abs_libdir/$TEMPLATE_REL_MANIFEST_DIR/rust-installer-version"

# Run ldconfig to make dynamic libraries available to the linker
maybe_run_ldconfig

# Install the uninstaller
install_uninstaller "$src_dir" "$src_basename" "$abs_libdir"

echo
echo "    $TEMPLATE_SUCCESS_MESSAGE"
echo


