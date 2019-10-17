#!/bin/sh

# This shell library is meant to be used with `set -e`.

if [ "$(whoami)" != "root" ]; then
    echo "This library is useless for non-root users. Exiting..." >&2
    exit 1
fi

# Import the TBB_INSTALL and TBB_EXT variables, and
# configure_xulrunner_app_locale().
. /usr/local/lib/tails-shell-library/tor-browser.sh

# Import try_for().
. /usr/local/lib/tails-shell-library/common.sh

# Break down the chroot and kill all of its processes
try_cleanup_browser_chroot () {
    local chroot="${1}"
    local cow="${2}"
    local user="${3}"
    try_for 10 "pkill -u ${user} 1>/dev/null 2>&1" 0.1 || \
        pkill -9 -u "${user}" || :
    # findmnt sorts submounts so we just have to revert the list to
    # have the proper umount order. We use `tail` to suppress the
    # "TARGET" column header.
    local chroot_mounts="$(
        findmnt --output TARGET --list --submounts "${chroot}" | tail -n+2 | tac
    )"
    for mnt in ${chroot_mounts} "${cow}"; do
        try_for 10 "umount ${mnt} 2>/dev/null" 0.1
    done
    rmdir "${cow}" "${chroot}"
}

# Setup a chroot on a clean aufs "fork" of the root filesystem.
setup_chroot_for_browser () {
    local chroot="${1}"
    local cow="${2}"
    local user="${3}"

    # FIXME: When LXC matures to the point where it becomes a viable option
    # for creating isolated jails, the chroot can be used as its rootfs.

    local cleanup_cmd="try_cleanup_browser_chroot \"${chroot}\" \"${cow}\" \"${user}\""
    trap "${cleanup_cmd}" INT EXIT

    local rootfs_dir
    local rootfs_dirs_path="/lib/live/mount/rootfs"
    local tails_module_path="/lib/live/mount/medium/live/Tails.module"
    local aufs_dirs=

    # We have to pay attention to the order we stack the filesystems;
    # newest must be first, and remember that the .module file lists
    # oldest first, newest last.
    while read rootfs_dir; do
        rootfs_dir="${rootfs_dirs_path}/${rootfs_dir}"
        mountpoint -q "${rootfs_dir}" && \
        aufs_dirs="${rootfs_dir}=rr+wh:${aufs_dirs}"
    done < "${tails_module_path}"
    # But our copy-on-write dir must be at the very top.
    aufs_dirs="${cow}=rw:${aufs_dirs}"

    mkdir -p "${cow}" "${chroot}" && \
    mount -t tmpfs tmpfs "${cow}" && \
    mount -t aufs -o "noatime,noxino,dirs=${aufs_dirs}" aufs "${chroot}" && \
    mount -t proc proc "${chroot}/proc" && \
    mount --bind "/dev" "${chroot}/dev" && \
    mount -t tmpfs -o rw,nosuid,nodev tmpfs "${chroot}/dev/shm" || \
        return 1

    # Workaround for #6110
    chmod -t "${cow}"
}

browser_conf_dir () {
    local browser_name="${1}"
    local browser_user="${2}"
    echo "/home/${browser_user}/.${browser_name}"
}

browser_profile_dir () {
    local conf_dir="$(browser_conf_dir "${@}")"
    echo "${conf_dir}/profile.default"
}

chroot_browser_conf_dir () {
    local chroot="${1}"; shift
    echo "${chroot}/$(browser_conf_dir "${@}")"
}

chroot_browser_profile_dir () {
    local conf_dir="$(chroot_browser_conf_dir "${@}")"
    echo "${conf_dir}/profile.default"
}

set_chroot_browser_permissions () {
    local chroot="${1}"
    local browser_name="${2}"
    local browser_user="${3}"
    local browser_conf="$(chroot_browser_conf_dir "${chroot}" "${browser_name}" "${browser_user}")"
    chown -R "${browser_user}:${browser_user}" "${browser_conf}"
}

configure_chroot_browser_profile () {
    local chroot="${1}" ; shift
    local browser_name="${1}" ; shift
    local browser_user="${1}" ; shift
    local home_page="${1}" ; shift
    # Now $@ is a list of paths (that must be valid after chrooting)
    # to extensions to enable.

    # Prevent sudo from complaining about failing to resolve the 'amnesia' host
    echo "127.0.0.1 localhost amnesia" > "${chroot}/etc/hosts"

    # Create a fresh browser profile for the clearnet user
    local browser_profile="$(chroot_browser_profile_dir "${chroot}" "${browser_name}" "${browser_user}")"
    local browser_ext="${browser_profile}/extensions"
    mkdir -p "${browser_profile}" "${browser_ext}"

    # Select extensions to enable
    local extension
    while [ -n "${*:-}" ]; do
        extension="${1}" ; shift
        if [ "$(basename "${extension}")" = 'red-2.0-an+fx.xpi' ]; then
           ln -s "${extension}" "${browser_ext}"/'{91a24c60-0f27-427c-b9a6-96b71f3984a9}.xpi'
        else
           ln -s "${extension}" "${browser_ext}"
        fi
    done

    # Set preferences
    local browser_prefs="${browser_profile}/user.js"
    local chroot_browser_config="/usr/share/tails/chroot-browsers"
    cat "${chroot_browser_config}/common/prefs.js" \
        "${chroot_browser_config}/${browser_name}/prefs.js" > "${browser_prefs}"

    # Install addonStartup.json.lz4. This is required to enable the red theme.
    cp "${chroot_browser_config}/${browser_name}/addonStartup.json.lz4" \
        "${browser_profile}"

    # Set browser home page to something that explains what's going on
    if [ -n "${home_page:-}" ]; then
        echo 'user_pref("browser.startup.homepage", "'"${home_page}"'");' >> \
            "${browser_prefs}"
    fi

    # Customize the GUI.
    for css in userChrome.css userContent.css ; do
        local browser_css="${browser_profile}/chrome/${css}"
        mkdir -p "$(dirname "${browser_css}")"
        cat "${chroot_browser_config}/common/${css}" \
            "${chroot_browser_config}/${browser_name}/${css}" >> \
            "${browser_css}"
    done

    set_chroot_browser_permissions "${chroot}" "${browser_name}" "${browser_user}"
}

set_chroot_browser_locale () {
    local chroot="${1}"
    local browser_name="${2}"
    local browser_user="${3}"
    local locale="${4}"
    local browser_profile="$(chroot_browser_profile_dir "${chroot}" "${browser_name}" "${browser_user}")"
    configure_xulrunner_app_locale "${browser_profile}" "${locale}"
}

set_chroot_browser_name () {
    local chroot="${1}"
    local human_readable_name="${2}"
    local browser_name="${3}"
    local browser_user="${4}"
    local locale="${5}"
    local ext_dir="${chroot}/${TBB_EXT}"
    local browser_profile_ext_dir="$(chroot_browser_profile_dir "${chroot}" "${browser_name}" "${browser_user}")/extensions"

    # Torbutton is installed in the browser's omni.ja and it decides
    # the browser name.
    local pack="${chroot}/${TBB_INSTALL}/omni.ja"
    local tmp="$(mktemp -d)"
    (
       cd "${tmp}"
       7z x -o"${tmp}" "${pack}" chrome/torbutton/locale
       local torbutton_locale_dir="chrome/torbutton/locale/${locale}"
       if [ ! -d "${torbutton_locale_dir}" ]; then
          torbutton_locale_dir="chrome/torbutton/locale/en-US"
       fi
       sed -i "s/<"'!'"ENTITY\s\+brand\(Full\|Short\|Shorter\)Name.*$/<"'!'"ENTITY brand\1Name \"${human_readable_name}\">/" "${torbutton_locale_dir}/brand.dtd"
       7z u -tzip "${pack}" .
    )
    chmod a+r "${pack}"
    rm -Rf "${tmp}"
}

delete_chroot_browser_searchplugins() {
    local chroot="${1}"
    local ext_dir="${chroot}/${TBB_EXT}"

    pack="${chroot}/${TBB_INSTALL}/browser/omni.ja"
    local searchplugins_dir="chrome/browser/search-extensions"
    local searchplugins_list="${searchplugins_dir}/list.json"
    local tmp="$(mktemp -d)"
    (
        cd "${tmp}"
        7z x -tzip "${pack}" "${searchplugins_dir}"
        ls -d "${searchplugins_dir}"/*/manifest.json | xargs 7z d -tzip "${pack}"
        echo '{"default": {"visibleDefaultEngines": []}, "experimental-hidden": {"visibleDefaultEngines": []}}' \
             > "${searchplugins_list}"
        7z u -tzip "${pack}" "${searchplugins_list}"
    )
    rm -r "${tmp}"
    chmod a+r "${pack}"
}

configure_chroot_browser () {
    local chroot="${1}" ; shift
    local browser_user="${1}" ; shift
    local browser_name="${1}" ; shift
    local human_readable_name="${1}" ; shift
    local home_page="${1}" ; shift
    # Now $@ is a list of paths (that must be valid after chrooting)
    # to extensions to enable.
    local best_locale="$(guess_best_tor_browser_locale)"

    configure_chroot_browser_profile "${chroot}" "${browser_name}" \
        "${browser_user}" "${home_page}" "${@}"
    set_chroot_browser_locale "${chroot}" "${browser_name}" "${browser_user}" \
        "${best_locale}"
    set_chroot_browser_name "${chroot}" "${human_readable_name}"  \
        "${browser_name}" "${browser_user}" "${best_locale}"
    delete_chroot_browser_searchplugins "${chroot}"
    set_chroot_browser_permissions "${chroot}" "${browser_name}" \
        "${browser_user}"
}

# Start the browser in the chroot
run_browser_in_chroot () {
    local chroot="${1}"
    local browser_name="${2}"
    local chroot_user="${3}"
    local local_user="${4}"
    local wm_class="${5}"
    local profile="$(browser_profile_dir ${browser_name} ${chroot_user})"

    sudo -u "${local_user}" xhost "+SI:localuser:${chroot_user}"
    chroot "${chroot}" sudo -u "${chroot_user}" /bin/sh -c \
        ". /usr/local/lib/tails-shell-library/tor-browser.sh && \
         export TOR_TRANSPROXY=1 && \
         exec_firefox --class='${wm_class}' \
                      -profile '${profile}'"
    sudo -u "${local_user}" xhost "-SI:localuser:${chroot_user}"
}
