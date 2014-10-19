function echo_fake_base_package () {
	local base_version
	expect_args base_version -- "$@"

	cat <<-EOF
		name:           halcyon-fake-base
		version:        ${base_version}
		build-type:     Simple
		cabal-version:  >= 1.2

		executable halcyon-fake-base
		  build-depends:  base == ${base_version}
EOF
}


function log_space () {
	if (( ${HALCYON_INTERNAL_SPACE:-0} )); then
		log
	else
		export HALCYON_INTERNAL_SPACE=1
	fi
}


function reset_space () {
	unset HALCYON_INTERNAL_SPACE
}


function deploy_app () {
	expect_vars HALCYON_DIR HALCYON_NO_PREPARE_CACHE HALCYON_NO_GHC HALCYON_NO_CABAL HALCYON_NO_SANDBOX HALCYON_NO_APP HALCYON_NO_CLEAN_CACHE

	local app_dir
	expect_args app_dir -- "$@"

	if ! (( HALCYON_NO_PREPARE_CACHE )); then
		log_space
		prepare_cache || die
	fi

	if ! (( HALCYON_NO_GHC )); then
		log_space
		install_ghc "${app_dir}" || return 1
	fi

	if ! (( HALCYON_NO_CABAL )); then
		log_space
		install_cabal "${app_dir}" || return 1
	fi

	local tmp_protected_sandbox
	tmp_protected_sandbox=''
	if [ -f "${HALCYON_DIR}/sandbox" ]; then
		tmp_protected_sandbox=$( echo_tmp_dir_name 'halcyon.protected-sandbox' ) || die
		mv "${HALCYON_DIR}/sandbox" "${tmp_protected_sandbox}" || die
	fi
	if ! (( HALCYON_NO_SANDBOX )); then
		log_space
		install_sandbox "${app_dir}" || return 1
	fi
	if [ -n "${tmp_protected_sandbox}" ]; then
		rm -rf "${HALCYON_DIR}/sandbox" || die
		mv "${tmp_protected_sandbox}/sandbox" "${HALCYON_DIR}" || die
	fi

	if ! (( HALCYON_NO_APP )); then
		log_space
		install_app "${app_dir}" || return 1
	fi

	if ! (( HALCYON_NO_CLEAN_CACHE )); then
		log_space
		clean_cache || die
	fi
}


function deploy_local_app () {
	local app_dir
	expect_args app_dir -- "$@"

	deploy_app "${app_dir}" || return 1
	reset_space
}


function deploy_base_package () {
	expect_vars HALCYON_DIR

	local name_or_label
	expect_args name_or_label -- "$@"

	HALCYON_NO_CABAL=1 HALCYON_NO_SANDBOX=1 HALCYON_NO_APP=1 HALCYON_NO_CLEAN_CACHE=1 \
		deploy_app '/dev/null' || return 1
	expect_existing "${HALCYON_DIR}/ghc/.halcyon-tag"

	local base_version tmp_app_dir
	base_version=''
	if [ "${name_or_label}" == 'base' ]; then
		base_version=$( detect_base_package_version ) || die
	else
		base_version="${name_or_label#base-}"
	fi
	tmp_app_dir=$( echo_tmp_dir_name 'halcyon.fake-base' ) || die

	mkdir -p "${tmp_app_dir}" || die
	echo_fake_base_package "${base_version}" >"${tmp_app_dir}/halcyon-fake-base.cabal" || die

	HALCYON_NO_PREPARE_CACHE=1 HALCYON_NO_GHC=1 HALCYON_NO_APP=1 \
		deploy_app "${tmp_app_dir}" || return 1

	rm -rf "${tmp_app_dir}" || die
	reset_space
}


function deploy_remote_app () {
	expect_vars HALCYON_DIR

	local url_or_name_or_label
	expect_args url_or_name_or_label -- "$@"

	local tmp_remote_dir
	tmp_remote_dir=$( echo_tmp_dir_name 'halcyon.remote' ) || die

	mkdir -p "${tmp_remote_dir}" || die

	case "${url_or_name_or_label}" in
	'https://'*);&
	'ssh://'*);&
	'git@'*);&
	'file://'*);&
	'http://'*);&
	'git://'*)
		if ! git clone --depth=1 "${url_or_name_or_label}" "${tmp_remote_dir}"; then
			die "Cannot install ${url_or_name_or_label}"
		fi
		deploy_app "${tmp_remote_dir}" || return 1
		;;
	*)
		HALCYON_NO_SANDBOX=1 HALCYON_NO_APP=1 HALCYON_NO_CLEAN_CACHE=1 \
			deploy_app '/dev/null' || return 1
		expect_existing "${HALCYON_DIR}/cabal/.halcyon-tag"

		local label
		if ! label=$(
			cabal_do "${tmp_remote_dir}" unpack "${url_or_name_or_label}" |
				filter_last |
				match_exactly_one |
				sed 's:^Unpacking to \(.*\)/$:\1:'
		); then
			die "Cannot install ${url_or_name_or_label}"
		fi

		if [ "${label}" != "${url_or_name_or_label}" ]; then
			log_space
			log_warning "Using newest available version of ${url_or_name_or_label}"
			log_warning 'Expected package name with explicit version'
		fi

		HALCYON_NO_PREPARE_CACHE=1 HALCYON_NO_GHC=1 HALCYON_NO_CABAL=1 \
			deploy_app "${tmp_remote_dir}/${label}" || return 1
	esac

	rm -rf "${tmp_remote_dir}" || die
	reset_space
}